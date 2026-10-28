/// Where a recipe editor opened by a link lands: the MAKES field
/// (`?focus=makes`) or one ingredient line, open (`?line={lineItemId}`).
///
/// Pure Dart, so a screen that only builds the link (the Cook tab's gap card)
/// does not pull in the editor.
library;

import 'package:meta/meta.dart';

/// The query parameter naming a field to land on. `makes` is the only one.
const kEditorFocusQueryParam = 'focus';

/// The query parameter naming the line item whose card opens on arrival.
const kEditorLineQueryParam = 'line';

/// What an editor scrolls to on arrival. Null everywhere means the top.
@immutable
sealed class EditorLanding {
  const EditorLanding();

  /// The landing a link's [query] names, or null. A `focus` the editor does
  /// not know names none. A line is the narrower ask, so it wins over `focus`.
  static EditorLanding? fromQuery(Map<String, String> query) {
    final line = query[kEditorLineQueryParam]?.trim();
    if (line != null && line.isNotEmpty) return LandOnLine(line);
    if (query[kEditorFocusQueryParam] == 'makes') return const LandOnMakes();
    return null;
  }
}

/// The MAKES field: scrolled into view, its first amount focused.
final class LandOnMakes extends EditorLanding {
  const LandOnMakes();

  @override
  bool operator ==(Object other) => other is LandOnMakes;

  @override
  int get hashCode => (LandOnMakes).hashCode;
}

/// One ingredient line: its card open and scrolled into view. A line the
/// recipe no longer has lands nowhere.
final class LandOnLine extends EditorLanding {
  const LandOnLine(this.lineId);

  final String lineId;

  @override
  bool operator ==(Object other) =>
      other is LandOnLine && other.lineId == lineId;

  @override
  int get hashCode => Object.hash(LandOnLine, lineId);
}

/// The editor's location for [recipeId], landing on [landing] when given.
String recipeEditorLocation(String recipeId, {EditorLanding? landing}) {
  final base = '/recipes/$recipeId/edit';
  return switch (landing) {
    null => base,
    LandOnMakes() => '$base?$kEditorFocusQueryParam=makes',
    LandOnLine(:final lineId) =>
      '$base?$kEditorLineQueryParam=${Uri.encodeQueryComponent(lineId)}',
  };
}
