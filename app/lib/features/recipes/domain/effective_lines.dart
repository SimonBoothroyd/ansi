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
/// **The only rule today: drop the lines marked `optional`.** The owner ruled
/// "exclude optional lines, for now" and asked that the app be *designed for*
/// a per-week override later — tick an optional line back in for one planned
/// week, substitute an ingredient — without building it this wave. That is
/// what `planEntryId` is for: it is accepted and unused, so the override join
/// (a `plan_entry_line_override` row per touched line, keyed by plan entry and
/// line) slots in here, once, instead of into three derivations. Nothing
/// reads it yet; a caller that has an entry may pass it, one that does not
/// passes nothing, and both get the same answer today.
library;

import 'recipe.dart';

/// Why [effectiveLines] left a line out. One reason today; the per-week
/// override will add its own ("left out for this week") beside it, and the
/// surfaces that name a dropped line switch on this rather than on a flag.
enum LineDropReason {
  /// The recipe marks the line optional ([LineItem.optional]) and nothing has
  /// asked for it back.
  optional,
}

/// One line [effectiveLines] dropped, and why — so the derivation that asked
/// can name it: "not counted · 2 optional lines: Lime, Coriander".
typedef DroppedLine = ({LineItem line, LineDropReason reason});

/// What a derivation runs over: the `kept` lines in their stored order, and
/// the `dropped` ones with a reason, also in stored order.
typedef EffectiveLines = ({List<LineItem> kept, List<DroppedLine> dropped});

/// Splits [lines] into the ones a derivation should sum and the ones it must
/// name instead. Order is preserved on both sides.
///
/// [planEntryId] is the seam for the per-week override (see the library doc):
/// accepted, documented, and deliberately unread today.
EffectiveLines effectiveLines(
  Iterable<LineItem> lines, {
  // Unread on purpose — the override seam (library doc).
  String? planEntryId,
}) {
  final kept = <LineItem>[];
  final dropped = <DroppedLine>[];
  for (final line in lines) {
    if (line.optional) {
      dropped.add((line: line, reason: LineDropReason.optional));
    } else {
      kept.add(line);
    }
  }
  return (kept: kept, dropped: dropped);
}

/// The names of the lines dropped for [reason], in stored order — the list a
/// surface prints after its count ("Lime, Coriander").
List<String> droppedNames(EffectiveLines lines, LineDropReason reason) => [
  for (final d in lines.dropped)
    if (d.reason == reason) d.line.subRecipe?.title ?? d.line.ingredientName,
];
