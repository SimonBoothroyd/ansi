/// The import's outstanding work, grouped by what each line WANTS — PURE DART
/// (invariant 2).
///
/// This is the wide review panel's idle state, and it is a **view, not a
/// feature**: every item here is a flag already drawn on its own row, read from
/// the one `importValidation` map the header's "N to review", the rows' own
/// amber tags and the Save gate all read. No new number, no new state, nothing
/// that can disagree with a row — the queue cannot say four while the bar says
/// five, because both count the same map.
///
/// What the grouping buys is the one thing a twenty-line import hides: that
/// four of the five outstanding lines are the same job done four times. The
/// groups are the rows' own `⚠` labels, in the order the phone's gate checks
/// them.
///
/// **Rows created here are listed apart and are OUT of the count.** A stub
/// commits perfectly well — it is a real, plannable, shoppable line that
/// reports `incomplete` instead of a fabricated number — so putting it in the
/// work list would be inventing an obligation. Saying so on screen is the whole
/// point of drawing it.
library;

import 'line_resolution.dart';
import 'line_validation.dart';
import 'reconciliation_payload.dart';

/// What an outstanding line wants, in the order [lineIssues] is checked.
///
/// One line belongs to exactly one group — the same priority
/// `attentionLabel` uses, so the queue's heading is the words already on the
/// row rather than a second vocabulary.
enum ImportWork {
  /// No ingredient chosen yet ([LineIssue.unmatched]).
  match('Match an ingredient'),

  /// A printed range with no number picked, or a linked line with no amount
  /// ([LineIssue.rangeUnpicked], [LineIssue.amountMissing]).
  amount('Set the amount'),

  /// The line's unit is not one the matched row can carry
  /// ([LineIssue.unitNotAllowed]) — the piece-weight case included, because it
  /// meets that same gate.
  unit('Pick a supported unit');

  const ImportWork(this.label);

  /// The heading, which is the row's own `⚠` label verbatim.
  final String label;
}

/// Which group [issues] puts a line in, or null when the line is done.
///
/// The priority is `attentionLabel`'s: unmatched first (nothing else can be
/// judged without an ingredient), then the unit, then the amount. A line with
/// two flags is listed once, under the one it is really waiting on.
ImportWork? workFor(List<LineIssue> issues) {
  if (issues.isEmpty) return null;
  if (issues.contains(LineIssue.unmatched)) return ImportWork.match;
  if (issues.contains(LineIssue.unitNotAllowed)) return ImportWork.unit;
  if (issues.contains(LineIssue.rangeUnpicked) ||
      issues.contains(LineIssue.amountMissing)) {
    return ImportWork.amount;
  }
  return null;
}

/// One row of the queue: which line, what it is called, and the source's own
/// words beside it.
class ImportWorkItem {
  const ImportWorkItem({
    required this.lineIndex,
    required this.name,
    required this.printed,
    this.openIngredientId,
  });

  /// The flat line index — what tapping the item selects.
  final int lineIndex;

  /// The line's current identity ([LineResolution.displayName]).
  final String name;

  /// What the page printed, verbatim, or the unit word in quotes where the
  /// unit is the thing being refused. Empty when the page printed neither.
  final String printed;

  /// The ingredient whose own form holds the fix, when the fix is not on this
  /// line at all — a count on a row with no piece weight (ADR-0015). Null
  /// everywhere else, and the panel then offers no row door.
  final String? openIngredientId;
}

/// One heading and its lines.
class ImportWorkGroup {
  const ImportWorkGroup({required this.work, required this.items});

  final ImportWork work;
  final List<ImportWorkItem> items;
}

/// The queue for [resolutions] against [byLine] — the validation map, exactly
/// as the count and the Save gate read it.
///
/// Groups come back in [ImportWork] order and empty groups are omitted; items
/// keep the list's own line order inside a group. A dropped line reports no
/// issues, so it never appears — it is leaving.
List<ImportWorkGroup> importWorkQueue({
  required List<LineResolution> resolutions,
  required Map<int, LineValidation> byLine,
  required ReconLine Function(int lineIndex) lineAt,
}) {
  final byWork = <ImportWork, List<ImportWorkItem>>{};
  for (final r in resolutions) {
    final validation = byLine[r.lineIndex];
    if (validation == null) continue;
    final work = workFor(validation.issues);
    if (work == null) continue;
    // The unit group is about a WORD the row refuses, so that word is what the
    // item prints; every other group is about the amount, where the page's own
    // printed phrase is the useful reminder.
    final printed = work == ImportWork.unit
        ? (r.unit?.isNotEmpty ?? false ? '“${r.unit}”' : '')
        : lineAt(r.lineIndex).raw.rawAmount.trim();
    (byWork[work] ??= []).add(
      ImportWorkItem(
        lineIndex: r.lineIndex,
        name: r.displayName,
        printed: printed,
        openIngredientId: validation.pieceWeightMissing
            ? r.chosenIngredientId
            : null,
      ),
    );
  }
  return [
    for (final work in ImportWork.values)
      if (byWork[work] case final items?)
        ImportWorkGroup(work: work, items: items),
  ];
}

/// The rows this review CREATED, listed apart and out of the count.
///
/// [LineResolution.createdHere] is set by the picker's create-new door, so
/// these are exactly the lines whose vocabulary row did not exist when the
/// import landed. The word beside each is what the row is — `stub` while its
/// numbers are outstanding, which is the ordinary case, since the form writes
/// one and confirming is a human act (§9).
List<ImportWorkItem> createdHereItems({
  required List<LineResolution> resolutions,
  required Map<int, LineValidation> byLine,
}) => [
  for (final r in resolutions)
    if (r.createdHere && !r.isDropped)
      ImportWorkItem(
        lineIndex: r.lineIndex,
        name: r.displayName,
        printed: (byLine[r.lineIndex]?.rowIsStub ?? true) ? 'stub' : 'complete',
      ),
];
