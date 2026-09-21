/// The import's outstanding work, grouped by what each line wants. Pure Dart.
///
/// The wide review panel's idle state. It is a view over the one
/// `importValidation` map that the header count, the rows' tags and the Save
/// gate read, so the numbers always agree. The groups are the rows' own `⚠`
/// labels, in the order the gate checks them.
///
/// Rows created during this review are listed apart and are out of the count: a
/// stub commits fine, so it is not an obligation.
library;

import 'line_resolution.dart';
import 'line_validation.dart';
import 'reconciliation_payload.dart';

/// What an outstanding line wants, in the order [lineIssues] is checked. A line
/// belongs to exactly one group, by `attentionLabel`'s priority.
enum ImportWork {
  /// No ingredient chosen yet ([LineIssue.unmatched]).
  match('Match an ingredient'),

  /// A printed range with no number picked, or a linked line with no amount
  /// ([LineIssue.rangeUnpicked], [LineIssue.amountMissing]).
  amount('Set the amount'),

  /// The line's unit is not one the matched row can carry
  /// ([LineIssue.unitNotAllowed]), the missing piece weight case included.
  unit('Pick a supported unit');

  const ImportWork(this.label);

  /// The heading, which is the row's own `⚠` label verbatim.
  final String label;
}

/// Which group [issues] puts a line in, or null when the line is done.
/// Unmatched first, then the unit, then the amount; a line with two flags is
/// listed once.
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

  /// The ingredient whose own form holds the fix: a count on a row with no
  /// piece weight (ADR-0015). Null otherwise.
  final String? openIngredientId;
}

/// One heading and its lines.
class ImportWorkGroup {
  const ImportWorkGroup({required this.work, required this.items});

  final ImportWork work;
  final List<ImportWorkItem> items;
}

/// The queue for [resolutions] against [byLine], the validation map. Groups
/// come back in [ImportWork] order with empty ones omitted; items keep line
/// order. A dropped line never appears.
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
    // The unit group prints the word the row refuses; every other group prints
    // the page's printed amount.
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

/// The rows this review created, listed apart and out of the count.
/// [LineResolution.createdHere] is set by the picker's create-new door. The
/// word beside each is the row's status, usually `stub`.
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
