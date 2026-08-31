/// The single-screen review surface (v3, owner refinement): every import line
/// renders as one [ReviewLineCard] — compact `amount · ingredient · notes` by
/// default, expanding IN PLACE (tap the row or the pencil) into the full
/// editable card: tap the ingredient to re-match (decision 5's seeded picker),
/// the tap-to-edit [AmountEditor] (the step-7.7 quantity + unit-chip sheet,
/// decision 6), and an inline notes field. Auto / suggest / none lines are all
/// equally editable; a needs-attention line only gets a visual flag. The
/// never-invent flags (0014) are shown, not hidden.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/picker_shell.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../recipes/presentation/format.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/reconciliation_payload.dart';
import 'import_view_models.dart';

/// One expandable review row. Collapsed, it reads as the recipe page will:
/// `amount · ingredient · notes` with a pencil. Expanded, it becomes the full
/// editable card (re-match, amount+unit, notes). The expand state is local so
/// several rows can be open at once and it survives the parent's rebuilds on
/// every edit.
class ReviewLineCard extends HookConsumerWidget {
  const ReviewLineCard({
    required this.line,
    required this.resolution,
    required this.controller,
    this.validation,
    super.key,
  });

  final ReconLine line;
  final LineResolution resolution;
  final ImportController controller;

  /// The line's validity + unit chips (from `importValidation`). Null while
  /// validation is still loading — the card falls back to the structural
  /// check (matched? range picked?) so it always renders something sane.
  final LineValidation? validation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = useState(false);
    final effective =
        validation ?? LineValidation(issues: lineIssues(resolution));
    final attention = effective.issues.isNotEmpty;
    final matched =
        resolution.chosenIngredientId != null ||
        resolution.createStubName != null;

    return _Card(
      attention: attention,
      child: expanded.value
          ? _Expanded(
              line: line,
              resolution: resolution,
              controller: controller,
              validation: effective,
              matched: matched,
              onCollapse: () => expanded.value = false,
            )
          : _Collapsed(
              line: line,
              resolution: resolution,
              issues: effective.issues,
              onExpand: () => expanded.value = true,
            ),
    );
  }
}

/// The short, human "why this line needs you" — a clear label, not a bare dot
/// (round-2 #4). Null when the line is done.
String? attentionLabel(List<LineIssue> issues) {
  if (issues.isEmpty) return null;
  if (issues.contains(LineIssue.unmatched)) return 'Match an ingredient';
  if (issues.contains(LineIssue.unitNotAllowed)) return 'Pick a supported unit';
  if (issues.contains(LineIssue.rangeUnpicked)) return 'Set the amount';
  return 'Needs a look';
}

/// The original imported line as written — amount + ingredient — shown as a
/// muted reference so the user always sees what the source said (round-2 #3:
/// "from a photo I wouldn't know the original amount").
String rawLineText(RawLineItem raw) => [
  raw.rawAmount.trim(),
  raw.ingredientText.trim(),
].where((s) => s.isNotEmpty).join('  ');

/// The compact three-part row: amount · ingredient · notes, a pencil, and (when
/// still open) a clear "needs you" label. Tapping anywhere expands it.
class _Collapsed extends StatelessWidget {
  const _Collapsed({
    required this.line,
    required this.resolution,
    required this.issues,
    required this.onExpand,
  });

  final ReconLine line;
  final LineResolution resolution;
  final List<LineIssue> issues;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final raw = line.raw;
    final imprecise = _isImprecise(resolution);
    final name =
        resolution.chosenName ??
        resolution.createStubName ??
        raw.ingredientText;
    final notes = resolution.notes?.trim();
    final amount = amountLabel(resolution, raw);
    final label = attentionLabel(issues);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(
                  amount.isEmpty ? '—' : amount,
                  style: miseMono(size: 14, color: MiseColors.muted).copyWith(
                    fontStyle: imprecise ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: name,
                        style: miseSans(size: 15, weight: FontWeight.w600),
                      ),
                      if (notes != null && notes.isNotEmpty) ...[
                        TextSpan(
                          text: '  ·  ',
                          style: miseSans(size: 15, color: MiseColors.line),
                        ),
                        TextSpan(
                          text: notes,
                          style: miseSans(
                            size: 14,
                            color: MiseColors.muted,
                          ).copyWith(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(FLucideIcons.pencil, size: 14, color: MiseColors.herb),
            ],
          ),
          if (label != null) ...[
            const SizedBox(height: 6),
            _AttentionTag(label: label),
          ],
        ],
      ),
    );
  }
}

/// The full editable card: the raw line for reference, the re-match resolver
/// (tap the ingredient), then the amount editor + notes — which stay disabled
/// until an ingredient is matched (round-2 #7: a unit/note is meaningless with
/// no ingredient to derive an allowed set from).
class _Expanded extends StatelessWidget {
  const _Expanded({
    required this.line,
    required this.resolution,
    required this.controller,
    required this.validation,
    required this.matched,
    required this.onCollapse,
  });

  final ReconLine line;
  final LineResolution resolution;
  final ImportController controller;
  final LineValidation validation;
  final bool matched;
  final VoidCallback onCollapse;

  int get _index => resolution.lineIndex;

  @override
  Widget build(BuildContext context) {
    final issues = validation.issues;
    final label = attentionLabel(issues);
    final reference = rawLineText(line.raw);
    // Offer inline unit chips only when the current unit actually needs a fix
    // — an ambiguous/unmapped unit (round-3 #2), parallel to the ingredient
    // "did you mean" pills. A valid unit needs no prompting.
    final showUnitChips =
        matched &&
        issues.contains(LineIssue.unitNotAllowed) &&
        validation.unitChoices.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                line.raw.ingredientText,
                style: miseSans(size: 15, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCollapse,
              child: const Icon(
                FLucideIcons.chevronUp,
                size: 18,
                color: MiseColors.muted,
              ),
            ),
          ],
        ),
        // Always show the source line as written — the reference the owner
        // wants while fixing a photo import (round-2 #3).
        if (reference.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'from source:  $reference',
              style: miseMono(size: 11, color: MiseColors.muted),
            ),
          ),
        _Flags(raw: line.raw),
        if (label != null) ...[
          const SizedBox(height: 8),
          _AttentionTag(label: label),
        ],
        const SizedBox(height: 10),
        // The ingredient match — tap the ingredient itself to re-match.
        Resolver(
          candidates: line.candidates,
          resolution: resolution,
          onResolveExisting: (id, name, {required correction}) =>
              controller.updateResolution(
                _index,
                (r) => r.resolveToIngredient(id, name, correction: correction),
              ),
          onResolveStub: (name) => controller.updateResolution(
            _index,
            (r) => r.resolveToNewStub(name),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(width: 64, child: Text('AMOUNT', style: miseLabel())),
            const SizedBox(width: 8),
            if (matched)
              AmountEditor(lineIndex: _index, controller: controller)
            else
              _DisabledChip(label: amountLabel(resolution, line.raw)),
          ],
        ),
        if (showUnitChips) ...[
          const SizedBox(height: 8),
          _UnitSuggestions(
            choices: validation.unitChoices,
            selected: resolution.unit,
            onPick: (token) => controller.updateResolution(
              _index,
              (r) => r.pickUnit(token),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _NotesEditor(
          lineIndex: _index,
          controller: controller,
          enabled: matched,
        ),
        if (!matched)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Match an ingredient first — then the amount and notes unlock.',
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
          ),
      ],
    );
  }
}

/// A greyed, non-interactive stand-in for the amount chip while the line has
/// no ingredient — units can't be chosen until the allowed set exists.
class _DisabledChip extends StatelessWidget {
  const _DisabledChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MiseColors.paper,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label.isEmpty ? '—' : label,
          style: miseMono(size: 12, color: MiseColors.line),
        ),
      ),
    );
  }
}

/// Inline unit "did you mean" chips (round-3 #2) — the matched ingredient's
/// valid units, offered when the current unit is unsupported so the user can
/// pick a good one in a tap, parallel to the ingredient candidate pills.
class _UnitSuggestions extends StatelessWidget {
  const _UnitSuggestions({
    required this.choices,
    required this.selected,
    required this.onPick,
  });

  final List<UnitSuggestion> choices;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text('UNIT', style: miseLabel())),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in choices)
                _Pill(
                  label: c.label,
                  onTap: () => onPick(c.token),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The clear "needs you" tag (round-2 #4) — a short amber label, not a bare
/// dot. Disappears the moment the line is done.
class _AttentionTag extends StatelessWidget {
  const _AttentionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          FLucideIcons.triangleAlert,
          size: 12,
          color: MiseColors.aging,
        ),
        const SizedBox(width: 5),
        Text(label, style: miseMono(size: 11, color: MiseColors.aging)),
      ],
    );
  }
}

/// The inline notes field — the missing "edit the notes" affordance. Blank
/// clears the note; a value is trimmed and stored.
class _NotesEditor extends ConsumerWidget {
  const _NotesEditor({
    required this.lineIndex,
    required this.controller,
    required this.enabled,
  });

  final int lineIndex;
  final ImportController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    final resolution = state.resolutions.firstWhere(
      (r) => r.lineIndex == lineIndex,
    );
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text('NOTES', style: miseLabel()),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FTextField(
            enabled: enabled,
            hint: 'e.g. finely chopped, to serve',
            control: FTextFieldControl.managed(
              initial: TextEditingValue(text: resolution.notes ?? ''),
              onChange: (v) => controller.updateResolution(
                lineIndex,
                (r) => r.setNotes(v.text),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The amount label. With a picked number: the quantity + unit (count shows
/// just its number). With NO picked number: the original printed amount is
/// preferred (so a range reads "2–3 cloves", never a bare "clove" — round-2
/// #3), else the imprecise/measure unit word ("to taste"), else empty (the
/// caller renders "—" or a "set amount" prompt — never an invented unit).
String amountLabel(LineResolution r, RawLineItem raw) {
  final mapped = r.unit == null ? null : unitById(r.unit!);
  if (r.quantity != null) {
    final unitLabel = mapped?.label ?? r.unit ?? '';
    if (mapped != null && mapped.family == UnitFamily.count) {
      return formatQuantity(r.quantity);
    }
    return '${formatQuantity(r.quantity)} $unitLabel'.trim();
  }
  // No number. A CLEAN catalog unit names itself — an imprecise amount reads
  // "pinch" / "to taste" / "handful", NEVER the raw phrase "A good pinch"
  // (round-3 #1a: an imprecise amount is a clean unit, not raw text).
  if (mapped != null) return mapped.label;
  // Unmapped/absent unit: fall back to the printed original (a range,
  // "2–3 cloves"), else the raw unit word, else empty.
  if (raw.rawAmount.trim().isNotEmpty) return raw.rawAmount.trim();
  if (r.unit != null && r.unit!.isNotEmpty) return r.unit!;
  return '';
}

bool _isImprecise(LineResolution r) {
  if (r.unit == null) return false;
  return unitById(r.unit!)?.family == UnitFamily.imprecise;
}

/// The card chrome — an aging border while the line needs the user, a quiet
/// line once it is done (the amber clears on resolution, round-2 #4).
class _Card extends StatelessWidget {
  const _Card({required this.attention, required this.child});

  final bool attention;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MiseColors.surface,
          border: Border.all(
            color: attention ? MiseColors.aging : MiseColors.line,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: child,
        ),
      ),
    );
  }
}

/// Opens the step-7.7 quantity + unit-chip sheet for the flattened line at
/// [lineIndex] and writes the picked quantity + unit back onto its resolution
/// (decision 6). Only ever called on a MATCHED line (round-2 #7); the chips are
/// the matched ingredient's allowed set + measures + the always-admitted
/// imprecise units ([amountSheetIngredient], ADR-0008).
///
/// Round-2 #1 fix: the matched ingredient is loaded DIRECTLY by id (not via a
/// name search that could fail to return it and silently leave the tap inert);
/// a load failure degrades to a stub stand-in, and the sheet ALWAYS opens.
///
/// Round-1 fixes still hold: a picked MEASURE chip ("clove") rides its LABEL
/// through [sheetChoiceUnit] not a degraded "piece", and a RANGE opens on its
/// printed low endpoint so confirming resolves it.
Future<void> editLineAmount(
  BuildContext context,
  WidgetRef ref,
  ImportController controller,
  int lineIndex,
) async {
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return;
  final raw = state.payload.flatLines[lineIndex].raw;
  final resolution = state.resolutions.firstWhere(
    (r) => r.lineIndex == lineIndex,
  );
  final matched =
      resolution.chosenIngredientId != null ||
      resolution.createStubName != null;
  if (!matched) return; // units need an ingredient to derive an allowed set

  Ingredient? loaded;
  if (resolution.chosenIngredientId != null) {
    try {
      loaded = await ref
          .read(ingredientRepositoryProvider)
          .byId(resolution.chosenIngredientId!);
    } on Object {
      loaded = null; // never leave the tap inert — fall back to a stand-in
    }
  }
  if (!context.mounted) return;

  final unit = resolution.unit == null ? null : unitById(resolution.unit!);
  final base =
      loaded ??
      Ingredient(
        id: resolution.chosenIngredientId ?? 'import-$lineIndex',
        canonicalName:
            resolution.chosenName ??
            resolution.createStubName ??
            resolution.ingredientText,
        defaultUnit: unit ?? (resolution.quantity == null ? toTaste : g),
        status: IngredientStatus.stub,
      );
  // A range with no picked number opens on its printed low endpoint (a real
  // printed value, not an invented one) so confirming the sheet resolves it.
  final initialQuantity =
      resolution.quantity ??
      (resolution.isRange ? (raw.qtyLow ?? raw.qtyHigh) : null);
  final result = await showQuantityUnitSheet(
    context,
    ingredient: amountSheetIngredient(base),
    initialQuantity: initialQuantity,
    initialChoice: unit != null ? UnitOption(unit) : null,
  );
  if (result is! QuantitySaved) return;
  controller.updateResolution(lineIndex, (r) {
    final picked = sheetChoiceUnit(
      choice: result.choice,
      unitPicked: result.unitPicked,
      currentUnit: r.unit,
    );
    return r.setAmount(quantity: result.quantity, unit: picked);
  });
}

/// The tap-to-edit amount chip (decision 6). Shows the resolved amount, else
/// the printed raw amount, else a prompt; tapping opens the amount sheet.
class AmountEditor extends ConsumerWidget {
  const AmountEditor({
    required this.lineIndex,
    required this.controller,
    super.key,
  });

  final int lineIndex;
  final ImportController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    final raw = state.payload.flatLines[lineIndex].raw;
    final resolution = state.resolutions.firstWhere(
      (r) => r.lineIndex == lineIndex,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => editLineAmount(context, ref, controller, lineIndex),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MiseColors.paper,
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Builder(
                  builder: (_) {
                    final label = amountLabel(resolution, raw);
                    return Text(
                      label.isEmpty ? 'set amount' : label,
                      style: miseMono(size: 12, color: MiseColors.muted),
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                FLucideIcons.pencil,
                size: 11,
                color: MiseColors.herb,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The honest-import flags for a line — shown, never hidden (0014).
class _Flags extends StatelessWidget {
  const _Flags({required this.raw});

  final RawLineItem raw;

  @override
  Widget build(BuildContext context) {
    final flags = <String>[
      if (raw.optional) 'optional',
      if (raw.confidence < 0.75)
        'low confidence ${(raw.confidence * 100).round()}%',
      if (!raw.unitMappable && (raw.unit?.isNotEmpty ?? false))
        'unit "${raw.unit}" needs a look',
    ];
    if (flags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [for (final f in flags) _MiniFlag(text: f)],
      ),
    );
  }
}

class _MiniFlag extends StatelessWidget {
  const _MiniFlag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text(text, style: miseMono(size: 10, color: MiseColors.aging)),
    );
  }
}

/// The band-appropriate resolver: the chosen ingredient (the whole row taps to
/// re-match) or, unresolved, the candidate chips / seeded-search entry point.
/// Resolving is delegated up so a caller could write several lines at once.
class Resolver extends StatelessWidget {
  const Resolver({
    required this.candidates,
    required this.resolution,
    required this.onResolveExisting,
    required this.onResolveStub,
    super.key,
  });

  final List<MatchCandidate> candidates;
  final LineResolution resolution;
  final void Function(String id, String name, {required bool correction})
  onResolveExisting;
  final ValueChanged<String> onResolveStub;

  Future<void> _openSearch(BuildContext context) async {
    final pick = await showReconcileIngredientSheet(
      context,
      seedName: resolution.ingredientText,
      candidates: candidates,
    );
    if (pick == null) return;
    switch (pick) {
      case PickExisting(:final ingredient):
        // A search override of the band's match is a correction → alias write.
        onResolveExisting(
          ingredient.id,
          ingredient.canonicalName,
          correction: true,
        );
      case PickCandidate(:final candidate):
        onResolveExisting(
          candidate.ingredientId,
          candidate.canonicalName,
          correction: false,
        );
      case CreateNewStub(:final name):
        onResolveStub(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (resolution.chosenIngredientId != null) {
      return _Chosen(
        label: resolution.chosenName ?? 'Matched',
        isNew: false,
        onTap: () => _openSearch(context),
      );
    }
    if (resolution.createStubName != null) {
      return _Chosen(
        label: 'new: ${resolution.createStubName}',
        isNew: true,
        onTap: () => _openSearch(context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (candidates.isNotEmpty) ...[
          Text('Did you mean', style: miseLabel()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in candidates)
                _Pill(
                  label: c.canonicalName,
                  onTap: () => onResolveExisting(
                    c.ingredientId,
                    c.canonicalName,
                    correction: false,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        FButton(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          prefix: const Icon(FLucideIcons.search),
          onPress: () => _openSearch(context),
          child: Text(
            candidates.isEmpty
                ? 'Find or create ingredient'
                : 'Something else',
          ),
        ),
      ],
    );
  }
}

/// The resolved ingredient — the WHOLE row is the re-match affordance now (the
/// tiny "change" link is gone): tap the ✓/＋ ingredient to open the picker.
class _Chosen extends StatelessWidget {
  const _Chosen({
    required this.label,
    required this.isNew,
    required this.onTap,
  });

  final String label;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MiseColors.paper,
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                isNew ? FLucideIcons.plus : FLucideIcons.check,
                size: 15,
                color: MiseColors.herb,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: miseSans(size: 14, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // A quiet hint that the row itself re-matches — the affordance is
              // the whole tap target, not a separate control.
              Text(
                'tap to change',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
              const SizedBox(width: 4),
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: MiseColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MiseColors.surface,
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: miseSans(size: 13)),
        ),
      ),
    );
  }
}

// --- The seeded search / create-new sheet ------------------------------------

/// A reconciliation pick: a server candidate, an existing vocab ingredient, or
/// the intent to create a new stub (deferred to commit so identical no-match
/// lines coalesce).
sealed class ReconcilePick {
  const ReconcilePick();
}

class PickCandidate extends ReconcilePick {
  const PickCandidate(this.candidate);
  final MatchCandidate candidate;
}

class PickExisting extends ReconcilePick {
  const PickExisting(this.ingredient);
  final Ingredient ingredient;
}

class CreateNewStub extends ReconcilePick {
  const CreateNewStub(this.name);
  final String name;
}

/// Opens the vocab search sheet PRE-SEEDED with this line's [candidates] +
/// recents + create-new — never blank (decision 5). Resolves to a
/// [ReconcilePick] or null if dismissed. Create-new returns the intent (it does
/// not write a stub here) so [buildCommit] can coalesce duplicates.
Future<ReconcilePick?> showReconcileIngredientSheet(
  BuildContext context, {
  required String seedName,
  List<MatchCandidate> candidates = const [],
}) {
  return showFSheet<ReconcilePick>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => _ReconcileSheet(seedName: seedName, candidates: candidates),
  );
}

class _ReconcileSheet extends HookConsumerWidget {
  const _ReconcileSheet({required this.seedName, required this.candidates});

  final String seedName;
  final List<MatchCandidate> candidates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    // The seeded candidates lead the list before any query; once the user
    // types, their own search takes over.
    final showSuggested = candidates.isNotEmpty && search.query.trim().isEmpty;

    return PickerShell(
      title: 'Match "$seedName"',
      searchHint: 'Search ingredients',
      searchAutofocus: true,
      onQueryChanged: search.run,
      aboveList: showSuggested
          ? _SuggestedForLine(
              candidates: candidates,
              onPick: (c) => Navigator.of(context).pop(PickCandidate(c)),
            )
          : null,
      body: IngredientResultList(
        results: search.results,
        query: search.query,
        showingRecents: search.showingRecents,
        onPick: (ing) => Navigator.of(context).pop(PickExisting(ing)),
      ),
      footer: _CreateNewRow(
        // Seed create-new with the query, else the raw line text — so two
        // identical no-match lines default to the same coalescing name.
        name: search.query.trim().isEmpty ? seedName : search.query,
        onCreate: (name) => Navigator.of(context).pop(CreateNewStub(name)),
      ),
    );
  }
}

/// The "Suggested for this line" block — the line's server candidates, offered
/// before the user searches so the picker opens with the likely answers.
class _SuggestedForLine extends StatelessWidget {
  const _SuggestedForLine({required this.candidates, required this.onPick});

  final List<MatchCandidate> candidates;
  final ValueChanged<MatchCandidate> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SUGGESTED FOR THIS LINE', style: miseLabel()),
          const SizedBox(height: 4),
          for (final c in candidates)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(c),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.canonicalName,
                        style: miseSans(size: 15, weight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      FLucideIcons.plus,
                      size: 18,
                      color: MiseColors.herb,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateNewRow extends StatelessWidget {
  const _CreateNewRow({required this.name, required this.onCreate});

  final String name;
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final enabled = trimmed.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onCreate(trimmed) : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? MiseColors.herb : MiseColors.line,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                FLucideIcons.plus,
                size: 13,
                color: enabled ? MiseColors.herb : MiseColors.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  enabled
                      ? 'create "$trimmed" as a new ingredient'
                      : 'type a name to create it',
                  overflow: TextOverflow.ellipsis,
                  style: miseMono(
                    size: 11,
                    color: enabled ? MiseColors.herb : MiseColors.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
