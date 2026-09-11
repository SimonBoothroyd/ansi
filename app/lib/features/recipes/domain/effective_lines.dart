/// The ONE seam between a recipe's stored lines and the lines a derivation
/// actually runs over — PURE DART (invariant 2). (D6b).
///
/// Three derivations read a recipe's lines: the macro summation
/// (`recipe_macros.dart`), the shopping list (`shopping_repository_impl.dart`
/// expanding sessions into contributions) and the cook plan (which reads only
/// the component lines, through `loadComponentGraph`). Each of them calls
/// [effectiveLines] rather than filtering for itself, so a rule about *which*
/// lines count lives in exactly one place — and so does every line it drops,
/// with a reason, because a dropped line is NAMED by whichever surface dropped
/// it (never a silent hole; invariant 3 read the stronger way).
///
/// **Two rules.** The recipe's own: drop the lines marked `optional`. And the
/// week's: apply this week's [LineOverride]s first — a line swapped, an amount
/// changed, a line added, one left out, an optional one ticked back in. A
/// caller that holds a week passes its overrides; one that does not (the
/// recipe page, the Library) passes none and gets the recipe as it stands.
///
/// The answer COMPOSES: an overridden line comes back with `optional` cleared,
/// because the week has already ruled on it. So running the seam again over
/// its own `kept` list changes nothing, and a caller may hand the result
/// straight to `summarizeRecipeMacros` without the recipe's rule firing twice.
library;

import '../../../core/units/units.dart';
import 'line_override.dart';
import 'recipe.dart';

/// Why [effectiveLines] left a line out — what the surface that dropped it
/// switches on, rather than on a flag.
enum LineDropReason {
  /// The recipe marks the line optional ([LineItem.optional]) and nothing has
  /// asked for it back.
  optional,

  /// This week's variant leaves the line out ([LineOverrideAction.exclude]).
  /// The recipe still has it; only this week does not.
  thisWeek,
}

/// One line [effectiveLines] dropped, and why — so the derivation that asked
/// can name it: "not counted · 2 optional lines: Lime, Coriander".
typedef DroppedLine = ({LineItem line, LineDropReason reason});

/// What a derivation runs over: the `kept` lines in their stored order, and
/// the `dropped` ones with a reason, also in stored order.
typedef EffectiveLines = ({List<LineItem> kept, List<DroppedLine> dropped});

/// Splits [lines] into the ones a derivation should sum and the ones it must
/// name instead, after applying this week's [overrides]. Order is preserved on
/// both sides; added lines land at the end, in their stored order.
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
        kept.add(_applied(line, override!));
      case LineOverrideAction.include:
        // The week ruled on it, so the recipe's own rule has nothing left to
        // say — clearing the flag is what makes a second pass a no-op.
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
      kept.add(_addedLine(override));
    }
  }
  return (kept: kept, dropped: dropped);
}

/// [line] as this week cooks it — absolute values, all of them, and `optional`
/// cleared because a line somebody edited this week is a line they want.
LineItem _applied(LineItem line, LineOverride override) => line.copyWith(
  ingredientId: override.ingredientId,
  ingredientName: override.ingredientName.isEmpty
      ? line.ingredientName
      : override.ingredientName,
  subRecipeId: override.subRecipeId,
  subRecipe: override.subRecipeId == null ? null : line.subRecipe,
  quantity: override.quantity,
  unit: override.unit ?? line.unit,
  measureId: override.measureId,
  measure: override.measure,
  note: override.note,
  optional: false,
);

/// An added line as a [LineItem], so every derivation downstream reads one
/// shape. Its id is the override row's, which is what lets the editor reopen
/// on it and the next save land on the same row.
LineItem _addedLine(LineOverride override) => LineItem(
  id: override.id,
  ingredientName: override.ingredientName,
  unit: override.unit ?? pieces,
  ingredientId: override.ingredientId,
  subRecipeId: override.subRecipeId,
  quantity: override.quantity,
  measureId: override.measureId,
  measure: override.measure,
  note: override.note,
);

/// The names of the lines dropped for [reason], in stored order — the list a
/// surface prints after its count ("Lime, Coriander").
List<String> droppedNames(EffectiveLines lines, LineDropReason reason) => [
  for (final d in lines.dropped)
    if (d.reason == reason) d.line.subRecipe?.title ?? d.line.ingredientName,
];
