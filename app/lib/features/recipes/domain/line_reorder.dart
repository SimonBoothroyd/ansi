/// Moving an ingredient line over one flat list. Pure Dart.
///
/// The editor's groups and the import review's sections both drag as a flat
/// list of heading rows and line rows, so refiling a line and reordering it are
/// one gesture. Written over `List<List<T>>` (groups, then their items) because
/// the two screens hold lines as different types. A move returns the same item
/// values, so a line keeps its id and its method chips. A group emptied by a
/// drag stays in place.
library;

/// The flat row index of group [groupIndex]'s heading.
int headingRowOf(List<List<Object?>> groups, int groupIndex) {
  var row = 0;
  for (var g = 0; g < groupIndex && g < groups.length; g++) {
    row += 1 + groups[g].length;
  }
  return row;
}

/// The flat row index of item [itemIndex] within group [groupIndex].
int lineRowOf(List<List<Object?>> groups, int groupIndex, int itemIndex) =>
    headingRowOf(groups, groupIndex) + 1 + itemIndex;

/// How many flat rows [groups] draws — one heading each, plus every item.
int lineRowCount(List<List<Object?>> groups) {
  var rows = 0;
  for (final group in groups) {
    rows += 1 + group.length;
  }
  return rows;
}

/// Moves the line row at [from] to row [to], returning the regrouped items.
///
/// Both are flat row indexes as `onReorderItem` reports them: [to] is the
/// position in the list with the row already removed. A [from] naming a heading
/// (or nothing) returns the input unchanged. A line dropped above the first
/// heading lands at the top of the first group.
List<List<T>> moveLineRow<T>(
  List<List<T>> groups, {
  required int from,
  required int to,
}) {
  final rows = <(int group, T? item)>[];
  for (final (g, group) in groups.indexed) {
    rows.add((g, null));
    for (final item in group) {
      rows.add((g, item));
    }
  }
  if (from < 0 || from >= rows.length || rows[from].$2 == null) return groups;

  final moved = rows.removeAt(from);
  // Row 0 is the first heading, which cannot move, so a row never lands before
  // it.
  final at = to.clamp(1, rows.length);
  rows.insert(at, moved);

  final out = [for (final _ in groups) <T>[]];
  var current = 0;
  for (final (group, item) in rows) {
    if (item == null) {
      current = group;
    } else {
      out[current].add(item);
    }
  }
  return out;
}
