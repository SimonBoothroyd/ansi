/// Moving an ingredient line, over ONE flat list — PURE DART (invariant 2).
///
/// Both ingredient lists — the editor's groups and the import review's
/// sections — drag as a single flat list whose rows are of two kinds: a
/// **heading** row starts a group, and every **line** row after it belongs to
/// that group. Filing a line under another heading and reordering it inside
/// its own are then the same gesture, which is the whole shape of the feature:
/// there is no second "move to a section" path to keep in sync.
///
/// The rule lives here rather than on either screen because the two surfaces
/// hold their lines as different things — `LineItem`s on the editor, flat line
/// indexes at review — and one of them must not learn a rule the other did
/// not. It is written over `List<List<T>>`: the outer list is the groups in
/// order, the inner ones their items.
///
/// **A move never touches an item.** The value that comes out is the value
/// that went in, so a line keeps its id (and every method chip pointing at it)
/// by construction rather than by care.
///
/// **A group is never removed.** A group emptied by dragging its last line
/// away stays exactly where it is: the heading is the human's, and a section
/// that empties while you rearrange is not a bug to fix behind them.
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

/// Moves the LINE row at [from] to row [to], returning the regrouped items.
///
/// [from] and [to] are flat row indexes as a reorderable list reports them to
/// `onReorderItem`: [to] is where the row lands in the list it has ALREADY
/// been taken out of, so a downward move needs no correction here or in a
/// caller.
///
/// A [from] that names a heading (or nothing) is returned unchanged: headings
/// do not move, and a caller that offers no drag handle on them cannot produce
/// one, but the rule refuses rather than trusting the caller.
///
/// A line dropped **above the first heading** lands at the top of the first
/// group. There is nowhere else for it to be — every line belongs to a group —
/// and dropping it at the very top of the list is an unambiguous request for
/// the first position.
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
  // A row is never dropped before the list's first heading, which is row 0 and
  // cannot have moved: headings do not drag.
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
