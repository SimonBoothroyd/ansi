/// The one seam between a recipe's stored lines and the lines a derivation runs
/// over. Pure Dart.
///
/// The macro summation, the shopping list and the cook plan all call
/// [effectiveLines] rather than filtering themselves, and every dropped line
/// comes back with a reason so the surface can name it. It applies this week's
/// [LineOverride]s first (none for the recipe page and Library), then drops
/// lines marked `optional`. An overridden line comes back with `optional`
/// cleared, so running the seam over its own `kept` list changes nothing.
library;

import 'line_override.dart';
import 'recipe.dart';

/// Why [effectiveLines] left a line out.
enum LineDropReason {
  /// The recipe marks the line optional ([LineItem.optional]) and nothing asked
  /// for it back.
  optional,

  /// This week's variant leaves the line out ([LineOverrideAction.exclude]).
  thisWeek,
}

/// One dropped line and why, so the caller can name it.
typedef DroppedLine = ({LineItem line, LineDropReason reason});

/// The `kept` lines and the `dropped` ones with reasons, both in stored order.
typedef EffectiveLines = ({List<LineItem> kept, List<DroppedLine> dropped});

/// Splits [lines] into kept and dropped after applying this week's [overrides].
/// Order is preserved; added lines land at the end.
EffectiveLines effectiveLines(
  Iterable<LineItem> lines, {
  List<LineOverride> overrides = const [],
}) {
  final byLine = <String, LineOverride>{
    for (final o in overrides)
      if (o.recipeLineItemId != null) o.recipeLineItemId!: o,
  };
  final kept = <LineItem>[];
  final dropped = <DroppedLine>[];
  for (final line in lines) {
    final override = byLine[line.id];
    switch (override?.action) {
      case LineOverrideAction.exclude:
        dropped.add((line: line, reason: LineDropReason.thisWeek));
      case LineOverrideAction.replace:
        kept.add(applyOverride(line, override!));
      case LineOverrideAction.include:
        // The week ruled on it; clearing the flag makes a second pass a no-op.
        kept.add(line.copyWith(optional: false));
      // An `add` names no recipe line, so it can never land here.
      case LineOverrideAction.add:
      case null:
        if (line.optional) {
          dropped.add((line: line, reason: LineDropReason.optional));
        } else {
          kept.add(line);
        }
    }
  }
  for (final override in overrides) {
    if (override.action == LineOverrideAction.add) {
      kept.add(addedLine(override));
    }
  }
  return (kept: kept, dropped: dropped);
}

/// The names of the lines dropped for [reason], in stored order.
List<String> droppedNames(EffectiveLines lines, LineDropReason reason) => [
  for (final d in lines.dropped)
    if (d.reason == reason) d.line.subRecipe?.title ?? d.line.ingredientName,
];

/// The ids of the lines dropped for [reason], parallel to [droppedNames].
List<String> droppedLineIds(EffectiveLines lines, LineDropReason reason) => [
  for (final d in lines.dropped)
    if (d.reason == reason) d.line.id,
];
