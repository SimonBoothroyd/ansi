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
///
/// Two of the card's three jobs live beside it: saying what the line IS is
/// `recon_resolver.dart` ([Resolver] and the seeded search sheet), and saying
/// how much of it is `recon_amount.dart` ([AmountEditor] and the two sheets it
/// opens). Both have public entry points other surfaces already call.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/presentation/recipe_chip.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/reconciliation_payload.dart';
import 'import_view_models.dart';
import 'recon_amount.dart';
import 'recon_resolver.dart';

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

  /// The line's validity + unit chips (from [importValidation]). Null while
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
    final imprecise = isImpreciseAmount(resolution);
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
                ReconPill(
                  label: c.label,
                  selected: c.token == widget.selected,
                  onTap: () => widget.onPick(c.token),
                ),
              if (hiddenCount > 0 && !selectedIsFolded)
                ReconPill(
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

/// Whether the extractor's unit word is one this app cannot read.
///
/// `unit_mappable: false` is the extractor saying "this amount did not land on
/// a **measurable** unit" — which covers two different things. One is a phrase
/// nothing can resolve ("thumb-sized piece"): that genuinely needs the user.
/// The other is an imprecise word the catalog *does* carry — `pinch`, `dash`,
/// `handful`, `to taste` — which the extraction prompt is told to emit as a
/// catalog id, and which the import surface then admits on the line by name.
/// Saying that one "needs a look" flags two lines of every seasoned recipe for
/// a word the app understood perfectly and has already accepted.
bool unitNeedsALook(RawLineItem raw) {
  final unit = raw.unit;
  if (raw.unitMappable || unit == null || unit.isEmpty) return false;
  return unitById(unit) == null;
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
      if (unitNeedsALook(raw)) 'unit "${raw.unit}" needs a look',
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
