/// The review's sections, as the human holds them. Pure Dart.
///
/// The payload's `groups` stay as the server sent them. What the cook does to
/// the structure (rename, delete or add a heading, add a line) is this list,
/// which rides `ImportReconciling` beside the resolutions.
///
/// A section holds flat line indexes, the review's stable key: resolutions are
/// keyed by it, step chips point at it (`previewLineId`), and `buildCommit`
/// writes it. Nothing renumbers: a dropped line's index stays unused and a new
/// one is taken from past the payload's last.
library;

import 'package:meta/meta.dart';

import '../../recipes/domain/line_reorder.dart';
import 'reconciliation_payload.dart';

/// One section of the review's ingredient list.
@immutable
class ReviewGroup {
  const ReviewGroup({required this.id, this.name, this.lines = const []});

  /// A stable handle for the widget key and every edit: `g<i>` for the
  /// payload's own group at index `i`, `g-new-<n>` for one added here.
  final String id;

  /// The heading, or null for none: the ordinary shape of a recipe that never
  /// divided its ingredients.
  final String? name;

  /// The flat line indexes this section holds, in order. Every index lives in
  /// exactly one section.
  final List<int> lines;

  ReviewGroup copyWith({
    String? name,
    List<int>? lines,
    bool clearName = false,
  }) => ReviewGroup(
    id: id,
    name: clearName ? null : (name ?? this.name),
    lines: lines ?? this.lines,
  );

  @override
  bool operator ==(Object other) =>
      other is ReviewGroup &&
      other.id == id &&
      other.name == name &&
      other.lines.length == lines.length &&
      Iterable<int>.generate(
        lines.length,
      ).every((i) => other.lines[i] == lines[i]);

  @override
  int get hashCode => Object.hash(id, name, lines.length);

  @override
  String toString() => 'ReviewGroup($id, $name, $lines)';
}

/// The id the payload's group at [index] carries at review.
String payloadGroupId(int index) => 'g$index';

/// The review's starting sections: the payload's own, one for one, holding the
/// flat indexes in the order the flattening already gives them.
List<ReviewGroup> initialGroups(ReconciliationPayload payload) {
  final groups = <ReviewGroup>[];
  var flatIndex = 0;
  for (var i = 0; i < payload.groups.length; i++) {
    final lines = <int>[];
    for (final _ in payload.groups[i].lines) {
      lines.add(flatIndex++);
    }
    groups.add(
      ReviewGroup(
        id: payloadGroupId(i),
        name: payload.groups[i].name,
        lines: lines,
      ),
    );
  }
  // A payload with no groups at all still has to have somewhere to put a line
  // the review adds.
  if (groups.isEmpty) groups.add(ReviewGroup(id: payloadGroupId(0)));
  return groups;
}

/// Renames the section [id]. Blank or whitespace clears the heading rather
/// than storing an empty one — a section named "" is a section with no name.
List<ReviewGroup> renameGroup(
  List<ReviewGroup> groups,
  String id,
  String? name,
) {
  final trimmed = name?.trim();
  final blank = trimmed == null || trimmed.isEmpty;
  return [
    for (final g in groups)
      if (g.id == id) g.copyWith(name: trimmed, clearName: blank) else g,
  ];
}

/// Deletes the section [id]'s heading, never its lines. The lines move into the
/// section above, keeping their order and resolutions; the first section's
/// lines go into the one that becomes first. The last section standing only
/// loses its heading.
List<ReviewGroup> removeGroup(List<ReviewGroup> groups, String id) {
  final at = groups.indexWhere((g) => g.id == id);
  if (at < 0) return groups;
  if (groups.length == 1) return renameGroup(groups, id, null);
  final into = at == 0 ? 1 : at - 1;
  final moved = groups[at].lines;
  final out = <ReviewGroup>[];
  for (final (i, g) in groups.indexed) {
    if (i == at) continue;
    out.add(
      i != into
          ? g
          // Merging upward, the moved lines land after the ones already there.
          // Merging down into the new first section, they stay at the head.
          : g.copyWith(
              lines: at == 0 ? [...moved, ...g.lines] : [...g.lines, ...moved],
            ),
    );
  }
  return out;
}

/// Appends an empty section. It fills by adding a line to it.
List<ReviewGroup> addGroup(List<ReviewGroup> groups, {required String id}) => [
  ...groups,
  ReviewGroup(id: id),
];

/// Appends [lineIndex] to the section [id] — the last act of adding a line at
/// review. A no-op for an index some section already holds.
List<ReviewGroup> addLineToGroup(
  List<ReviewGroup> groups,
  String id,
  int lineIndex,
) {
  if (groups.any((g) => g.lines.contains(lineIndex))) return groups;
  return [
    for (final g in groups)
      if (g.id == id) g.copyWith(lines: [...g.lines, lineIndex]) else g,
  ];
}

/// Moves the line row at [from] to row [to] over the review's flat list of
/// heading and line rows, by the editor's rule ([moveLineRow]). A line keeps
/// its index, its identity, and changes only its position, which commits as
/// `sort_order`.
List<ReviewGroup> moveReviewLine(
  List<ReviewGroup> groups, {
  required int from,
  required int to,
}) {
  final lines = moveLineRow(
    [for (final g in groups) g.lines],
    from: from,
    to: to,
  );
  return [for (final (i, g) in groups.indexed) g.copyWith(lines: lines[i])];
}

/// The next flat line index a review-added line may take: one past the highest
/// any section holds, and never below the payload's own line count, so a
/// dropped line's index is never reused.
int nextLineIndex(ReconciliationPayload payload, List<ReviewGroup> groups) {
  var next = payload.flatLines.length;
  for (final group in groups) {
    for (final index in group.lines) {
      if (index >= next) next = index + 1;
    }
  }
  return next;
}
