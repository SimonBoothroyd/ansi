/// The single-screen review surface (v3, owner refinement): every import line
/// renders as one [ReviewLineCard] — compact `amount · ingredient · notes` by
/// default, expanding IN PLACE (tap the row or the pencil) into the full
/// editable card: tap the ingredient to re-match (decision 5's seeded picker),
/// the tap-to-edit [AmountEditor] (the step-7.7 quantity + unit-chip sheet,
/// decision 6), and an inline notes field. Auto / suggest / none lines are all
/// equally editable; a needs-attention line only gets a visual flag. The
/// never-invent flags (0014) are shown, not hidden.
///
/// A line can also be DROPPED here (the bin on the expanded card): the card
/// greys into an "as deleted" state that says so and offers undo, and the line
/// stops being anyone's problem — no flag, no Save gate — until Save makes the
/// removal real (see [LineResolution.isDropped]).
///
/// And a line can be LINKED to a household recipe (step 8.6 / D6, design board
/// frame e): when the server offers a recipe-title candidate it rides the
/// existing did-you-mean chip row as "↪ your recipe · Romesco Aioli", ALONGSIDE
/// the ingredient candidates. Nothing links itself — the chip is an offer, at
/// any score. Tapping it turns the line into a component line: the identity
/// cell becomes the recipe chip, no ingredient match is wanted, no
/// allowed-units gate applies (admission is an ingredient concept), and the
/// line is valid for Save the moment its amount is set. Ignoring it leaves the
/// line exactly as it is today, and it commits byte-identically.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/picker_shell.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/component_quantity_sheet.dart';
import '../../recipes/presentation/recipe_chip.dart';
import '../domain/amount_text.dart';
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
    this.validation,
    super.key,
  });

  final ReconLine line;
  final LineResolution resolution;

  /// The line's validity + unit chips (from `importValidation`). Null while
  /// validation is still loading — the card falls back to the structural
  /// check (matched? range picked?) so it always renders something sane.
  final LineValidation? validation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = useState(false);
    final dropped = resolution.isDropped;
    // A dropped line has no issues by construction; the map handed in can still
    // be one recompute behind, so don't let a stale flag survive the drop.
    final effective = dropped
        ? const LineValidation(issues: [])
        : (validation ?? LineValidation(issues: lineIssues(resolution)));
    final attention = effective.issues.isNotEmpty;
    // A LINKED line counts as resolved for the card's purposes: it has an
    // identity, so the amount and notes unlock exactly as a matched line's do.
    final matched =
        resolution.chosenIngredientId != null || resolution.isComponent;
    // Read the notifier at CALL time, never captured (the file's rule).
    void setDropped({required bool value}) => ref
        .read(importControllerProvider.notifier)
        .updateResolution(
          resolution.lineIndex,
          (r) => value ? r.drop() : r.undrop(),
        );

    if (dropped) {
      return _Card(
        attention: false,
        dropped: true,
        child: _DroppedLine(
          line: line,
          resolution: resolution,
          onRestore: () => setDropped(value: false),
        ),
      );
    }
    return _Card(
      attention: attention,
      child: expanded.value
          ? _Expanded(
              line: line,
              resolution: resolution,
              validation: effective,
              matched: matched,
              onCollapse: () => expanded.value = false,
              onDrop: () => setDropped(value: true),
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

/// The "as deleted" card: the line stays on screen, greyed and plainly
/// labelled, with the un-delete beside it. Nothing is written until Save, so
/// this state is the whole deletion — reversible, visible, and out of the
/// Save gate.
class _DroppedLine extends StatelessWidget {
  const _DroppedLine({
    required this.line,
    required this.resolution,
    required this.onRestore,
  });

  final ReconLine line;
  final LineResolution resolution;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final name = resolution.chosenName ?? line.raw.ingredientText;
    return Row(
      children: [
        const Icon(FLucideIcons.trash2, size: 14, color: AnsiColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: ansiSans(
                  size: 15,
                  color: AnsiColors.muted,
                ).copyWith(decoration: TextDecoration.lineThrough),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'removed — this line will not be saved',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onRestore,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(FLucideIcons.undo2, size: 13, color: AnsiColors.herb),
              const SizedBox(width: 5),
              Text('undo', style: ansiMono(size: 11, color: AnsiColors.herb)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The short, human "why this line needs you" — a clear label, not a bare dot
/// (round-2 #4). Null when the line is done.
///
/// [hasRecipeOffer] widens the unmatched label to name the other door the card
/// is showing (board frame e): a line the server thinks names one of your own
/// recipes can be answered either way, and the tag should say so.
String? attentionLabel(List<LineIssue> issues, {bool hasRecipeOffer = false}) {
  if (issues.isEmpty) return null;
  if (issues.contains(LineIssue.unmatched)) {
    return hasRecipeOffer
        ? 'Match an ingredient — or link your recipe'
        : 'Match an ingredient';
  }
  if (issues.contains(LineIssue.unitNotAllowed)) return 'Pick a supported unit';
  if (issues.contains(LineIssue.rangeUnpicked) ||
      issues.contains(LineIssue.amountMissing)) {
    return 'Set the amount';
  }
  return 'Needs a look';
}

/// The original imported line as written — amount + ingredient — shown as a
/// muted reference so the user always sees what the source said (round-2 #3:
/// "from a photo I wouldn't know the original amount"). The two halves are
/// joined by [joinSourceLine], which drops the measure word they both print
/// rather than stuttering it ("2–3 cloves garlic cloves, sliced").
String rawLineText(RawLineItem raw) =>
    joinSourceLine(raw.rawAmount, raw.ingredientText);

/// The printed CROSS-REFERENCE a line carries — `"(page 38)"` — or null.
///
/// The board's frame (e) shows it as one more honest-import flag: the server
/// strips it before matching (the way parentheticals already are), so saying
/// so on the card is what keeps the stripping from looking like a
/// misreading — the identity text still says "(page 38)" and the chip below
/// says which recipe that turned out to be.
String? crossReferenceFlag(String ingredientText) {
  final match = RegExp(
    r'\((?:see\s+)?p(?:age|g)?\.?\s*\d+\)',
    caseSensitive: false,
  ).firstMatch(ingredientText);
  return match?.group(0);
}

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
    final name = resolution.chosenName ?? raw.ingredientText;
    final notes = resolution.notes?.trim();
    final amount = amountLabel(resolution, raw);
    final label = attentionLabel(
      issues,
      hasRecipeOffer: line.recipeCandidates.isNotEmpty,
    );

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
                  style: ansiMono(size: 14, color: AnsiColors.muted).copyWith(
                    fontStyle: imprecise ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // The identity cell is the ONLY part of the v3 line that changes
              // for a component (board frames a · e): the amount column and the
              // note modifier stay exactly as they are.
              if (resolution.isComponent)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: RecipeChip(
                          title: resolution.linkedRecipeTitle ?? name,
                          size: 14,
                        ),
                      ),
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            notes,
                            overflow: TextOverflow.ellipsis,
                            style: ansiSans(
                              size: 14,
                              color: AnsiColors.muted,
                            ).copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: ansiSans(size: 15, weight: FontWeight.w600),
                        ),
                        if (notes != null && notes.isNotEmpty) ...[
                          TextSpan(
                            text: '  ·  ',
                            style: ansiSans(size: 15, color: AnsiColors.line),
                          ),
                          TextSpan(
                            text: notes,
                            style: ansiSans(
                              size: 14,
                              color: AnsiColors.muted,
                            ).copyWith(fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(FLucideIcons.pencil, size: 14, color: AnsiColors.herb),
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
class _Expanded extends ConsumerWidget {
  const _Expanded({
    required this.line,
    required this.resolution,
    required this.validation,
    required this.matched,
    required this.onCollapse,
    required this.onDrop,
  });

  final ReconLine line;
  final LineResolution resolution;
  final LineValidation validation;
  final bool matched;
  final VoidCallback onCollapse;

  /// Drops the line from the import — reversible right up to Save.
  final VoidCallback onDrop;

  int get _index => resolution.lineIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read at CALL time through the app-lifetime container, never through
    // this card's `ref` and never as a captured notifier: `Resolver` hands its
    // pick back after an awaited sheet, and by then the card can be UNMOUNTED
    // — on a phone the sheet's keyboard shrinks the review list under it and
    // the card scrolls out — and a `WidgetRef` used after unmount throws
    // (Riverpod 3), which lost the pick. A notifier captured before the await
    // can be a disposed one instead. The container outlives both; the review
    // still watching the provider keeps the notifier alive.
    final container = ProviderScope.containerOf(context, listen: false);
    void update(LineResolution Function(LineResolution) f) => container
        .read(importControllerProvider.notifier)
        .updateResolution(_index, f);
    final issues = validation.issues;
    final linked = resolution.isComponent;
    final label = attentionLabel(
      issues,
      hasRecipeOffer: line.recipeCandidates.isNotEmpty,
    );
    final reference = rawLineText(line.raw);
    // Offer inline unit chips when the current unit needs a fix — an
    // ambiguous/unmapped unit (round-3 #2), parallel to the ingredient "did
    // you mean" pills — AND on a line the default answered (seam D2): the
    // choice made for you belongs on screen beside the ones you could make
    // instead. Hiding them would make the tap-to-change invisible and turn a
    // stated fact into a silent one. Any other valid unit needs no prompting.
    final showUnitChips =
        matched &&
        (issues.contains(LineIssue.unitNotAllowed) ||
            resolution.unitFromDefault) &&
        validation.unitChoices.isNotEmpty;
    // The whole honesty argument for D2, in one line of mono: the default is
    // shown at the moment it is applied, on the card, next to the raw source
    // line. Nothing is inferred behind the user's back because nothing is
    // behind their back.
    final defaulted = resolution.unitFromDefault
        ? validation.unitMeasure
        : null;
    final countsAs = defaulted == null
        ? null
        : 'counts as  ${defaulted.label} · '
              '${formatQuantity(defaulted.amount)} '
              '${defaulted.basis.baseUnit.label}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                line.raw.ingredientText,
                style: ansiSans(size: 15, weight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            // Drop the line: the recipe prints it, this cook doesn't want it.
            // It greys out in place and only Save makes the removal real.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDrop,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  FLucideIcons.trash2,
                  size: 16,
                  color: AnsiColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onCollapse,
              child: const Icon(
                FLucideIcons.chevronUp,
                size: 18,
                color: AnsiColors.muted,
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
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        _Flags(raw: line.raw),
        if (label != null) ...[
          const SizedBox(height: 8),
          _AttentionTag(label: label),
        ],
        const SizedBox(height: 10),
        // The ingredient match — tap the ingredient itself to re-match. A
        // recipe offer rides the same chip row, and a LINKED line renders its
        // recipe chip here with the unlink beside it (reversible until Save).
        Resolver(
          candidates: line.candidates,
          recipeCandidates: line.recipeCandidates,
          resolution: resolution,
          onResolveExisting: (id, name, {required correction}) => update(
            (r) => r.resolveToIngredient(id, name, correction: correction),
          ),
          onLinkRecipe: (c) =>
              update((r) => r.linkToRecipe(c.recipeId, c.title)),
          onUnlink: () => update((r) => r.unlink()),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            SizedBox(width: 64, child: Text('AMOUNT', style: ansiLabel())),
            const SizedBox(width: 8),
            if (matched)
              AmountEditor(lineIndex: _index)
            else
              _DisabledChip(label: amountLabel(resolution, line.raw)),
          ],
        ),
        if (countsAs != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 72),
            child: Text(
              '$countsAs  ·  tap a chip to change',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        if (showUnitChips) ...[
          const SizedBox(height: 8),
          _UnitSuggestions(
            choices: validation.unitChoices,
            selected: resolution.unit,
            onPick: (token) => update((r) => r.pickUnit(token)),
          ),
        ],
        const SizedBox(height: 12),
        _NotesEditor(lineIndex: _index, enabled: matched),
        if (!matched)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Match an ingredient first — then the amount and notes unlock.',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        // The two rules a linked line lives by, said on the card (board frame
        // e) rather than left for the user to infer from what is missing.
        if (linked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'linked — no ingredient match needed, no allowed-units gate. '
              'Valid for Save the moment its amount is set.',
              style: ansiMono(size: 10, color: AnsiColors.muted),
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
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label.isEmpty ? '—' : label,
          style: ansiMono(size: 12, color: AnsiColors.line),
        ),
      ),
    );
  }
}

/// Inline unit "did you mean" chips (round-3 #2) — the matched ingredient's
/// valid units, offered when the current unit is unsupported so the user can
/// pick a good one in a tap, parallel to the ingredient candidate pills.
///
/// The admission set for a common ingredient runs past a dozen units, which
/// reads as a wall rather than a choice. Owner's call: [kVisibleUnitChips] of
/// them — [rankedUnitChips]' likeliest — and the rest behind a "more" chip that
/// expands IN PLACE. Nothing is unreachable, and the fold never hides the
/// current selection: it opens on one.
class _UnitSuggestions extends StatefulWidget {
  const _UnitSuggestions({
    required this.choices,
    required this.selected,
    required this.onPick,
  });

  final List<UnitSuggestion> choices;

  /// The line's current unit token — both the selection to mark and the parsed
  /// unit the ranking fronts.
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  State<_UnitSuggestions> createState() => _UnitSuggestionsState();
}

class _UnitSuggestionsState extends State<_UnitSuggestions> {
  /// Sticky across the parent's rebuilds (every keystroke rebuilds the card),
  /// so an opened fold stays open — and so does the selection inside it.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ranked = rankedUnitChips(widget.choices, parsedUnit: widget.selected);
    final hiddenCount = ranked.length - kVisibleUnitChips;
    final selectedIsFolded = ranked
        .skip(kVisibleUnitChips)
        .any((c) => c.token == widget.selected);
    final open = _expanded || selectedIsFolded;
    final visible = hiddenCount > 0 && !open
        ? ranked.take(kVisibleUnitChips).toList()
        : ranked;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text('UNIT', style: ansiLabel())),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in visible)
                _Pill(
                  label: c.label,
                  selected: c.token == widget.selected,
                  onTap: () => widget.onPick(c.token),
                ),
              if (hiddenCount > 0 && !selectedIsFolded)
                _Pill(
                  label: _expanded ? 'fewer' : '+$hiddenCount more',
                  quiet: true,
                  onTap: () => setState(() => _expanded = !_expanded),
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
          color: AnsiColors.aging,
        ),
        const SizedBox(width: 5),
        Text(label, style: ansiMono(size: 11, color: AnsiColors.aging)),
      ],
    );
  }
}

/// The inline notes field — the missing "edit the notes" affordance. Blank
/// clears the note; a value is trimmed and stored.
class _NotesEditor extends ConsumerWidget {
  const _NotesEditor({required this.lineIndex, required this.enabled});

  final int lineIndex;
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
        SizedBox(width: 64, child: Text('NOTES', style: ansiLabel())),
        const SizedBox(width: 8),
        Expanded(
          child: FTextField(
            enabled: enabled,
            hint: 'e.g. finely chopped, to serve',
            control: FTextFieldControl.managed(
              initial: TextEditingValue(text: resolution.notes ?? ''),
              onChange: (v) => ref
                  .read(importControllerProvider.notifier)
                  .updateResolution(lineIndex, (r) => r.setNotes(v.text)),
            ),
          ),
        ),
      ],
    );
  }
}

/// The amount label. With a picked number: the quantity + unit (count shows
/// just its number). With NO picked number: the original printed amount is
/// preferred while it still reads as an amount (so a range reads "2–3 cloves",
/// never a bare "clove" — round-2 #3), else the imprecise/measure unit word
/// ("to taste"), else empty (the caller renders "—" or a "set amount" prompt —
/// never an invented unit).
///
/// The AMOUNT slot never carries prose. A raw amount with no number in it is
/// not an amount — "(to serve (optional))" — so it shows the qualifier the
/// source named ("to serve") and nothing else; the prose itself rides the NOTES
/// slot instead (see [noteFromRawAmount]).
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
  // Unmapped/absent unit: the printed original still wins WHILE IT IS ONE — an
  // unpicked range ("2–3 cloves"), a "2 sprigs" the vocab couldn't map.
  final printed = raw.rawAmount.trim();
  if (printed.isNotEmpty && !isProseAmount(printed)) return printed;
  return amountQualifier(printed) ??
      (r.unit?.isNotEmpty ?? false ? r.unit! : '');
}

bool _isImprecise(LineResolution r) {
  if (r.unit == null) return false;
  return unitById(r.unit!)?.family == UnitFamily.imprecise;
}

/// The card chrome — an aging border while the line needs the user, a quiet
/// line once it is done (the amber clears on resolution, round-2 #4), and the
/// flat paper fill of a [dropped] line, which is on its way out and should read
/// that way.
class _Card extends StatelessWidget {
  const _Card({
    required this.attention,
    required this.child,
    this.dropped = false,
  });

  final bool attention;
  final bool dropped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dropped ? AnsiColors.paper : AnsiColors.surface,
          border: Border.all(
            color: attention ? AnsiColors.aging : AnsiColors.line,
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
///
/// Owner call (count-measure pre-selection): when the line's parsed unit is one
/// this ingredient cannot carry — the "pick a supported unit" flag — and the
/// ingredient names a measure, the sheet opens with that measure already
/// selected ([preselectedMeasure]), and Done adopts it even if no chip was
/// tapped. Resolving becomes one confirm tap; the flag stands until that tap.
Future<void> editLineAmount(
  BuildContext context,
  WidgetRef ref,
  int lineIndex,
) async {
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return;
  // Captured BEFORE the sheet: the app-lifetime container is what the write
  // after the await goes through (the chip's own element may be gone by then).
  final container = ProviderScope.containerOf(context, listen: false);
  final raw = state.payload.flatLines[lineIndex].raw;
  final resolution = state.resolutions.firstWhere(
    (r) => r.lineIndex == lineIndex,
  );
  // A LINKED line is quantified against a RECIPE, not an ingredient: lane U's
  // component sheet, whose chips are `batch` ∪ the target's yield families.
  if (resolution.isComponent) {
    await editComponentAmount(context, ref, lineIndex);
    return;
  }
  if (resolution.chosenIngredientId == null) {
    return; // units need an ingredient to derive an allowed set
  }

  Ingredient? loaded;
  var measures = const <Measure>[];
  final chosenId = resolution.chosenIngredientId;
  if (chosenId != null) {
    try {
      loaded = await ref.read(ingredientRepositoryProvider).byId(chosenId);
    } on Object {
      loaded = null; // never leave the tap inert — fall back to a stand-in
    }
    try {
      // Straight off the repository, NOT through the measures stream provider.
      // That read only ever worked because `importValidation` happened to be
      // holding the same watch open: on its own it mints an autoDispose element
      // with nothing listening, and a PowerSync watch does not emit before the
      // element is collected — so the future completed with a `StateError`, the
      // catch below turned it into "no measures", and the one-tap measure
      // repair silently did nothing.
      measures =
          (await ref.read(measureRepositoryProvider).measuresByIngredients({
            chosenId,
          }))[chosenId] ??
          const [];
    } on Object {
      measures = const []; // no measures reachable → simply no pre-selection
    }
  }
  if (!context.mounted) return;

  final unit = resolution.unit == null ? null : unitById(resolution.unit!);
  final base =
      loaded ??
      Ingredient(
        id: resolution.chosenIngredientId ?? 'import-$lineIndex',
        canonicalName: resolution.chosenName ?? resolution.ingredientText,
        defaultUnit: unit ?? (resolution.quantity == null ? toTaste : g),
        status: IngredientStatus.stub,
      );
  // A range with no picked number opens on its printed low endpoint (a real
  // printed value, not an invented one) so confirming the sheet resolves it.
  final initialQuantity =
      resolution.quantity ??
      (resolution.isRange ? (raw.qtyLow ?? raw.qtyHigh) : null);
  // An inadmissible unit on an ingredient that names measures opens on the
  // likeliest measure — "2 clove" for a garlic line that arrived as "2 ml".
  // …and a line the default already answered opens ON that measure, so "tap
  // to change" lands on the choice it is changing rather than on nothing
  // (seam D2).
  final preselect = loaded == null
      ? null
      : preselectedMeasure(loaded, measures, unit: resolution.unit) ??
            (resolution.unitFromDefault
                ? measures.where((m) => m.label == resolution.unit).firstOrNull
                : null);
  final result = await showQuantityUnitSheet(
    context,
    ingredient: amountSheetIngredient(base, parsedUnit: resolution.unit),
    initialQuantity: initialQuantity,
    initialChoice: preselect != null
        ? MeasureOption(preselect)
        : (unit != null ? UnitOption(unit) : null),
    // The same sheet the editor uses, so the review gets the Optional switch
    // for free (D6a) — seeded from the extractor's flag, and the raw tag on
    // the card keeps saying what the source said.
    initialOptional: resolution.optional,
  );
  if (result is! QuantitySaved) return;
  // The notifier is read HERE, after the awaited sheet, through the container
  // captured before it — never through `ref` (the chip's element can be
  // unmounted by now, and Riverpod 3 throws on that) and never as an instance
  // captured before the await (which can be a disposed one).
  container.read(importControllerProvider.notifier).updateResolution(
    lineIndex,
    (r) {
      // A pre-selected measure counts as picked on confirm: the sheet opened ON
      // it, so Done means "yes, that one" — otherwise the one-tap resolve would
      // silently keep the unit the line was flagged for.
      final picked = sheetChoiceUnit(
        choice: result.choice,
        unitPicked: result.unitPicked || preselect != null,
        currentUnit: r.unit,
      );
      return r
          .setAmount(quantity: result.quantity, unit: picked)
          .setOptional(optional: result.optional);
    },
  );
}

/// Opens lane U's COMPONENT quantity sheet for a linked line (8.6 / D2 · D6)
/// and writes the picked amount back onto its resolution.
///
/// The target's yields come off the local repository — the link points at a
/// household recipe, which is a row this device already has — read STRAIGHT
/// from the keepAlive repository provider rather than through a stream
/// provider (plan 0020 **J2**: an autoDispose element with nothing listening
/// completes into an empty default, and "no yields" would silently become "no
/// yield set" on the sheet). A read that cannot answer degrades the same
/// honest way the sheet's own no-yield state does: `batch` only, said out
/// loud, never a guessed conversion.
Future<void> editComponentAmount(
  BuildContext context,
  WidgetRef ref,
  int lineIndex,
) async {
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final resolution = state.resolutions.firstWhere(
    (r) => r.lineIndex == lineIndex,
  );
  final recipeId = resolution.linkedRecipeId;
  if (recipeId == null) return;
  final title = resolution.linkedRecipeTitle ?? resolution.ingredientText;

  var target = SubRecipeTarget(id: recipeId, title: title);
  try {
    final recipes = await ref
        .read(recipeRepositoryProvider)
        .watchRecipes()
        .first
        .timeout(const Duration(seconds: 5));
    for (final r in recipes) {
      if (r.id != recipeId) continue;
      target = SubRecipeTarget(
        id: r.id,
        title: r.title,
        yieldQty: r.yieldQty,
        yieldUnit: r.yieldUnit,
        yieldQty2: r.yieldQty2,
        yieldUnit2: r.yieldUnit2,
      );
      break;
    }
  } on Object {
    // Never leave the tap inert — the sheet opens on the batch denomination,
    // which needs no yield at all.
  }
  if (!context.mounted) return;

  final stored = resolution.unit == null ? null : unitById(resolution.unit!);
  final result = await showComponentQuantitySheet(
    context,
    target: target,
    initialQuantity: resolution.quantity,
    // The 7.7 stored-selection rule: the line's printed unit is admissible on
    // this line whatever the sheet would otherwise offer.
    initialUnit: stored,
  );
  if (result == null) return;
  // Read AFTER the awaited sheet through the container, never captured before
  // it and never through a possibly-unmounted `ref` (see `editLineAmount`).
  container
      .read(importControllerProvider.notifier)
      .updateResolution(
        lineIndex,
        (r) => r.setAmount(quantity: result.quantity, unit: result.unit.id),
      );
}

/// The tap-to-edit amount chip (decision 6). Shows the resolved amount, else
/// the printed raw amount, else a prompt; tapping opens the amount sheet.
class AmountEditor extends ConsumerWidget {
  const AmountEditor({required this.lineIndex, super.key});

  final int lineIndex;

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
      onTap: () => editLineAmount(context, ref, lineIndex),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.line),
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
                      style: ansiMono(size: 12, color: AnsiColors.muted),
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
              const SizedBox(width: 5),
              const Icon(FLucideIcons.pencil, size: 11, color: AnsiColors.herb),
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
    final crossReference = crossReferenceFlag(raw.ingredientText);
    final flags = <String>[
      if (crossReference != null) 'cross-reference “$crossReference”',
      if (raw.optional) 'optional',
      if (raw.confidence < kLowConfidenceFloor)
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
      child: Text(text, style: ansiMono(size: 10, color: AnsiColors.aging)),
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
    this.recipeCandidates = const [],
    this.onLinkRecipe,
    this.onUnlink,
    super.key,
  });

  final List<MatchCandidate> candidates;

  /// The household recipes the server thinks this line names (8.6 / D6).
  /// Rendered as chips in the SAME did-you-mean row, never instead of the
  /// ingredient ones — a line can be either, and the human says which.
  final List<RecipeCandidate> recipeCandidates;

  final LineResolution resolution;

  /// Resolves the line to a vocabulary row — a candidate, a search hit, or the
  /// row the create-new chain just made: the New-ingredient sheet, the
  /// flesh-out form pushed over it, back, and the line lands on that row as the
  /// ordinary matched state.
  final void Function(String id, String name, {required bool correction})
  onResolveExisting;

  /// Links the line to the tapped recipe. Null where linking is not offered.
  final ValueChanged<RecipeCandidate>? onLinkRecipe;

  /// Un-links a linked line, back to the plain text it arrived as.
  final VoidCallback? onUnlink;

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
    }
  }

  @override
  Widget build(BuildContext context) {
    // LINKED: the identity cell is the recipe chip, with the same
    // tap-the-row-to-re-match affordance a chosen ingredient has (picking an
    // ingredient un-links it, D1's XOR) and an explicit unlink beside it, so
    // the decision is reversible right up to Save.
    if (resolution.isComponent) {
      return _LinkedRecipe(
        title: resolution.linkedRecipeTitle ?? resolution.ingredientText,
        onTap: () => _openSearch(context),
        onUnlink: onUnlink,
      );
    }
    if (resolution.chosenIngredientId != null) {
      return _Chosen(
        label: resolution.chosenName ?? 'Matched',
        onTap: () => _openSearch(context),
      );
    }

    final offers = onLinkRecipe == null
        ? const <RecipeCandidate>[]
        : recipeCandidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (candidates.isNotEmpty || offers.isNotEmpty) ...[
          Text('Did you mean', style: ansiLabel()),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // The recipe offers lead the row — a line that names one of your
              // own recipes usually means it — but they never replace the
              // ingredient candidates beside them.
              for (final c in offers)
                _Pill(
                  icon: kSubRecipeIcon,
                  label: 'your recipe · ${c.title}',
                  onTap: () => onLinkRecipe!(c),
                ),
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
            candidates.isEmpty && offers.isEmpty
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
  const _Chosen({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AnsiColors.paper,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              const Icon(FLucideIcons.check, size: 15, color: AnsiColors.herb),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: ansiSans(size: 14, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // A quiet hint that the row itself re-matches — the affordance is
              // the whole tap target, not a separate control.
              Text(
                'tap to change',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
              const SizedBox(width: 4),
              const Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: AnsiColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A LINKED line's identity cell: lane U's recipe chip, the whole row a
/// re-match target (picking an ingredient un-links it — one identity, D1), and
/// an explicit unlink so the offer can be taken back without hunting for the
/// ingredient the line never had.
class _LinkedRecipe extends StatelessWidget {
  const _LinkedRecipe({
    required this.title,
    required this.onTap,
    this.onUnlink,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: Row(
                  children: [
                    Flexible(child: RecipeChip(title: title, size: 14)),
                    const SizedBox(width: 8),
                    Text(
                      'tap to change',
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            if (onUnlink != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUnlink,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        FLucideIcons.undo2,
                        size: 13,
                        color: AnsiColors.herb,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'unlink',
                        style: ansiMono(size: 11, color: AnsiColors.herb),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    this.icon,
    this.selected = false,
    this.quiet = false,
  });

  final String label;

  /// A leading glyph — the sub-recipe mark on a recipe offer, so the chip
  /// reads as a different KIND of answer, not another ingredient.
  final IconData? icon;

  /// The chip carries the line's current value — filled, so a selection stays
  /// visible when the fold reorders the row around it.
  final bool selected;

  /// A chrome chip (the fold's "more") rather than a choice — it reads mono and
  /// muted so it never looks like one of the units.
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: AnsiColors.herb),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: quiet
                      ? ansiMono(size: 11, color: AnsiColors.muted)
                      : ansiSans(
                          size: 13,
                          color: selected
                              ? AnsiColors.herbDeep
                              : AnsiColors.ink,
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

// --- The seeded search / create-new sheet ------------------------------------

/// A reconciliation pick: a server candidate, or an existing vocab ingredient —
/// which is also what the create-new footer hands back, once the row exists and
/// the flesh-out form has been walked.
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

/// Opens the vocab search sheet PRE-SEEDED with this line's [candidates] +
/// recents + create-new — never blank (decision 5). Resolves to a
/// [ReconcilePick] or null if dismissed.
///
/// Create-new is the picker's own add-new chain (frame d): the
/// New-ingredient sheet with the line's text prefilled, the flesh-out form
/// pushed over THIS sheet and awaited, then the re-read row — resolved as a
/// [PickExisting], the ordinary matched state, no special case. Nothing is
/// deferred to commit: a line can no longer carry a name instead of an id, so
/// there is nothing to coalesce there.
Future<ReconcilePick?> showReconcileIngredientSheet(
  BuildContext context, {
  required String seedName,
  List<MatchCandidate> candidates = const [],
}) {
  return showAnsiSheet<ReconcilePick>(
    context: context,
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
      // The picker footer's own row, in its `.addnew` voice — it no longer
      // creates a stub-by-default, so it no longer reads like one. Seeded
      // with the query, else the raw line text, so "curry leaves" becomes the
      // row without retyping.
      footer: AddNewIngredientRow(
        query: search.query.trim().isEmpty ? seedName : search.query,
        label: (name) => 'create "$name" as a new ingredient',
        onCreated: (ing) => Navigator.of(context).pop(PickExisting(ing)),
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
          Text('SUGGESTED FOR THIS LINE', style: ansiLabel()),
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
                        style: ansiSans(size: 15, weight: FontWeight.w600),
                      ),
                    ),
                    const Icon(
                      FLucideIcons.plus,
                      size: 18,
                      color: AnsiColors.herb,
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
