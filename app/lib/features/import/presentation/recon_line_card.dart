/// The import review's line card.
///
/// Each line renders as one [ReviewLineCard]: compact `amount · ingredient ·
/// notes`, expanding in place into the editable card (re-match, [AmountEditor],
/// notes). A line can be dropped, which greys it until Save
/// ([LineResolution.isDropped]), or linked to a household recipe offered on the
/// did-you-mean chip row, which makes it a component line. Matching lives in
/// `recon_resolver.dart` ([Resolver]) and the amount in `recon_amount.dart`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/guarded_navigation.dart';
import '../../ingredients/presentation/ingredient_detail_view.dart'
    show ingredientDetailRoute;
import '../../recipes/domain/line_display.dart';
import '../../recipes/presentation/ingredient_line.dart';
import '../../recipes/presentation/line_card.dart';
import '../../recipes/presentation/recipe_chip.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/reconciliation_payload.dart';
import 'import_view_models.dart';
import 'recon_amount.dart';
import 'recon_resolver.dart';

/// One expandable review row: a [LineCard] with the review's contents in its
/// slots.
class ReviewLineCard extends ConsumerWidget {
  const ReviewLineCard({
    required this.line,
    required this.resolution,
    this.validation,
    this.dragIndex,
    this.collapseEpoch = 0,
    super.key,
  });

  final ReconLine line;
  final LineResolution resolution;

  /// The line's validity and unit chips (from [importValidation]). Null while
  /// validation loads; the card then falls back to the structural check.
  final LineValidation? validation;

  /// This card's position in the review's flat row list, which the grip drags
  /// by. Null when the card renders alone. Only a collapsed row shows the grip.
  final int? dragIndex;

  /// Bumped by the list when a drag starts elsewhere — an open card closes,
  /// so the drag crosses rows rather than cards of wildly different heights.
  final int collapseEpoch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dropped = resolution.isDropped;
    // A dropped line has no issues by construction; the map handed in can still
    // be one recompute behind, so don't let a stale flag survive the drop.
    final effective = dropped
        ? const LineValidation(issues: [])
        : (validation ?? LineValidation(issues: lineIssues(resolution)));
    final attention = effective.issues.isNotEmpty;
    // A linked line counts as resolved. "Matched" is the validation's verdict,
    // not the id the resolution holds: a line matched to a retired row comes
    // back `unmatched`, so the card asks for a pick and locks the amount.
    final unmatched = effective.issues.contains(LineIssue.unmatched);
    final matched =
        !unmatched &&
        (resolution.chosenIngredientId != null || resolution.isComponent);
    // Read the notifier at CALL time, never captured (the file's rule).
    void setDropped({required bool value}) => ref
        .read(importControllerProvider.notifier)
        .updateResolution(
          resolution.lineIndex,
          (r) => value ? r.drop() : r.undrop(),
        );

    if (dropped) {
      return LineCardSurface(
        dropped: true,
        child: _DroppedLine(
          line: line,
          resolution: resolution,
          onRestore: () => setDropped(value: false),
        ),
      );
    }
    return LineCard(
      attention: attention,
      dragIndex: dragIndex,
      collapseEpoch: collapseEpoch,
      collapsed: (onExpand) => ReviewLineRow(
        line: line,
        resolution: resolution,
        issues: effective.issues,
        onTap: onExpand,
      ),
      expanded: (onCollapse) => ReviewLineForm(
        line: line,
        resolution: resolution,
        validation: effective,
        matched: matched,
        onCollapse: onCollapse,
        onDrop: () => setDropped(value: true),
      ),
    );
  }
}

/// The dropped card: greyed and labelled, with undo beside it. Nothing is
/// written until Save.
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
    final name = resolution.displayName;
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

/// The line's count is waiting on the ingredient's piece weight — one line
/// of mono under the amount, and a door to the form that holds the number.
class _PieceWeightDoor extends StatelessWidget {
  const _PieceWeightDoor({required this.name, required this.ingredientId});

  final String name;
  final String ingredientId;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 72),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        Text(
          '$name has no piece weight yet — set it on the ingredient, or '
          'pick a unit below.',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
        GestureDetector(
          key: ValueKey('piece-weight-door-$ingredientId'),
          behavior: HitTestBehavior.opaque,
          // Opens the ingredient page in its editing posture, since the piece
          // weight is what needs setting.
          onTap: () =>
              context.pushOnce(ingredientDetailRoute(ingredientId, edit: true)),
          child: Text(
            'open $name ›',
            style: ansiMono(size: 10, color: AnsiColors.herb),
          ),
        ),
      ],
    ),
  );
}

/// The short "why this line needs you" label, or null when the line is done.
/// [hasRecipeOffer] widens the unmatched label to name the recipe door too.
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

/// The imported line as written, amount and ingredient, shown as a muted
/// reference. [joinSourceLine] drops a measure word both halves print.
String rawLineText(RawLineItem raw) =>
    joinSourceLine(raw.rawAmount, raw.ingredientText);

/// What a review-minted line prints where every other line prints its source.
const kAddedHereNote = 'added here — not on the page';

/// The compact three-part row: amount · ingredient · notes, a pencil, and (when
/// still open) a clear "needs you" label. Tapping anywhere expands it.
class ReviewLineRow extends StatelessWidget {
  const ReviewLineRow({
    required this.line,
    required this.resolution,
    required this.issues,
    required this.onTap,
    this.pencil = true,
    this.sourceLine = true,
    super.key,
  });

  final ReconLine line;
  final LineResolution resolution;
  final List<LineIssue> issues;

  /// What the row does when it is pressed: opens the card on a phone, points
  /// the panel at this line on a desk.
  final VoidCallback onTap;

  /// Whether the row carries the pencil. False on the wide review, where the
  /// form already stands beside the list.
  final bool pencil;

  /// Whether a flagged row repeats what the page printed. False on a wide
  /// screen, where the page itself is a column away.
  final bool sourceLine;

  @override
  Widget build(BuildContext context) {
    final raw = line.raw;
    final imprecise = isImpreciseAmount(resolution);
    final name = resolution.displayName;
    final notes = resolution.notes?.trim();
    final amount = amountSlotLabel(resolution, raw, issues);
    final label = attentionLabel(
      issues,
      hasRecipeOffer: line.recipeCandidates.isNotEmpty,
    );
    // The amount slot is blank on a line whose unit the row refuses, so the
    // compact row prints what the page said.
    final reference = rawLineText(raw);
    final showSource =
        sourceLine &&
        issues.contains(LineIssue.unitNotAllowed) &&
        !resolution.addedAtReview &&
        reference.isNotEmpty;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: kLineAmountWidth,
                child: Text(
                  amount.isEmpty ? '—' : amount,
                  style: ansiMono(size: 14, color: AnsiColors.muted).copyWith(
                    fontStyle: imprecise ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Only the identity cell changes for a component; the amount and
              // the note stay as they are.
              if (resolution.isComponent)
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: RecipeChip(title: name, size: 14)),
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
                        ...noteSpans(notes),
                      ],
                    ),
                  ),
                ),
              if (pencil) ...[
                const SizedBox(width: 8),
                const Icon(
                  FLucideIcons.pencil,
                  size: 14,
                  color: AnsiColors.herb,
                ),
              ],
            ],
          ),
          // The board's `l3-note`: a line the page never printed says so on
          // the compact row too, not only once it is opened.
          if (resolution.addedAtReview)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 96),
              child: Text(
                kAddedHereNote,
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
          if (showSource)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 96),
              child: Text(
                'from source:  $reference',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
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

/// The editable card: the raw line for reference, the resolver, then the amount
/// editor and notes, which stay disabled until an ingredient is matched.
class ReviewLineForm extends ConsumerWidget {
  const ReviewLineForm({
    required this.line,
    required this.resolution,
    required this.validation,
    required this.matched,
    required this.onCollapse,
    required this.onDrop,
    super.key,
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
    // Read at call time through the app-lifetime container, never this card's
    // `ref` or a captured notifier: [Resolver] hands its pick back after an
    // awaited sheet, by when the card can be unmounted (the keyboard scrolls it
    // out), and a `WidgetRef` used after unmount throws.
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
    // Offer inline unit chips only when the current unit needs a fix.
    final showUnitChips =
        matched &&
        issues.contains(LineIssue.unitNotAllowed) &&
        validation.unitChoices.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The head is the line's current identity, as on the collapsed row; the
        // source text sits directly underneath. The bin drops the line.
        LineCardHead(
          identity: Text(
            resolution.displayName,
            style: ansiSans(size: 15, weight: FontWeight.w600),
          ),
          onRemove: onDrop,
          onCollapse: onCollapse,
        ),
        // Always show the source line as written. A line added at review has no
        // source and says so in the same slot.
        if (resolution.addedAtReview)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              kAddedHereNote,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          )
        else if (reference.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'from source:  $reference',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        _Flags(
          raw: line.raw,
          optional: resolution.optional,
          onToggleOptional: (on) => update((r) => r.setOptional(optional: on)),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          _AttentionTag(label: label),
        ],
        const SizedBox(height: 10),
        // The ingredient match. A recipe offer rides the same chip row, and a
        // linked line renders its recipe chip here with the unlink beside it.
        Resolver(
          candidates: line.candidates,
          recipeCandidates: line.recipeCandidates,
          resolution: resolution,
          // The line holds an id the vocabulary can no longer return (the row
          // was retired), so this is the pick cell, not a ✓.
          matchMissing: !matched && resolution.chosenIngredientId != null,
          // Which food the matched row's numbers came from,
          // already on the validation the card is holding.
          sourceLine: validation.sourceLine,
          // The controller's match also lands a counted line on the row's whole
          // measure once the measures are read.
          onResolveExisting:
              (id, name, {required correction, created = false}) => container
                  .read(importControllerProvider.notifier)
                  .resolveLine(
                    _index,
                    id,
                    name,
                    correction: correction,
                    created: created,
                  ),
          onLinkRecipe: (c) =>
              update((r) => r.linkToRecipe(c.recipeId, c.title)),
          onUnlink: () => update((r) => r.unlink()),
        ),
        const SizedBox(height: 14),
        LineCardRow(
          label: 'AMOUNT',
          child: Align(
            alignment: Alignment.centerLeft,
            child: matched
                ? AmountEditor(lineIndex: _index, issues: issues)
                : _DisabledChip(
                    label: amountSlotLabel(resolution, line.raw, issues),
                  ),
          ),
        ),
        // A count on a row with no piece weight (ADR-0015): the fix is the
        // ingredient's, so the card names it and opens the row.
        if (validation.pieceWeightMissing &&
            resolution.chosenIngredientId != null)
          _PieceWeightDoor(
            name: resolution.displayName,
            ingredientId: resolution.chosenIngredientId!,
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

/// Inline unit chips: the matched ingredient's valid units, offered when the
/// current unit is unsupported. Shows [kVisibleUnitChips] of [rankedUnitChips]'
/// likeliest and folds the rest behind a "more" chip that expands in place. The
/// fold never hides the current selection.
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

    return LineCardRow(
      label: 'UNIT',
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
    return LineCardNotesField(
      initial: resolution.notes,
      enabled: enabled,
      onChanged: (text) => ref
          .read(importControllerProvider.notifier)
          .updateResolution(lineIndex, (r) => r.setNotes(text)),
    );
  }
}

/// Whether the extractor's unit word is one this app cannot read.
///
/// `unit_mappable: false` covers both a phrase nothing can resolve
/// ("thumb-sized piece") and an imprecise word the catalog carries (`pinch`,
/// `to taste`). Only the first needs the user.
bool unitNeedsALook(RawLineItem raw) {
  final unit = raw.unit;
  if (raw.unitMappable || unit == null || unit.isEmpty) return false;
  return unitById(unit) == null;
}

/// The honest-import flags for a line, led by the "to serve" control. The
/// control shows on every expanded card, matched or not, since garnish lines
/// most often go unmatched.
class _Flags extends StatelessWidget {
  const _Flags({
    required this.raw,
    required this.optional,
    required this.onToggleOptional,
  });

  final RawLineItem raw;

  /// The line's flag as it stands: seeded from the extractor and editable here.
  final bool optional;
  final ValueChanged<bool> onToggleOptional;

  @override
  Widget build(BuildContext context) {
    final crossReference = crossReferenceFlag(raw.ingredientText);
    final flags = <String>[
      if (crossReference != null) 'cross-reference “$crossReference”',
      if (raw.confidence < kLowConfidenceFloor)
        'low confidence ${(raw.confidence * 100).round()}%',
      if (unitNeedsALook(raw)) 'unit “${raw.unit}” needs a look',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          OptionalFlagToggle(value: optional, onChanged: onToggleOptional),
          for (final f in flags) _MiniFlag(text: f),
        ],
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
