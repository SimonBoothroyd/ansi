/// Batch math for a sub-recipe component line — PURE DART (invariant 2), and
/// the answer to the question step 8's gold `_review` parked: **what does the
/// `1` in "1 Italian Sausage (page 45)" count?**
///
/// It counts pieces of the sausage recipe's *yield*. A recipe states what one
/// batch makes ("makes 1 cup", "makes 8 piece") in up to two denominations of
/// DIFFERENT unit families ("makes 250 g · 16 tbsp"), and a component line's
/// printed amount is resolved against whichever denomination shares its family:
///
/// - `3 blob` against a recipe whose own measure says *a batch makes 20 blob*
///   is 0.15 batches. A [RecipeMeasure] is a count per batch, so it bypasses
///   the yield path entirely — that is the whole point of it, and it is why a
///   sauce nobody ever measured is still sayable in the words the household
///   uses for it.
/// - `1 batch` always resolves — the batch denomination needs no yield, and
///   `qty` *is* the batch count.
/// - `¼ cup` against `makes 1 cup` is 0.25 batches; `1 piece` against
///   `makes 8 piece` is 0.125 (the sausage answer).
/// - `2 tbsp` against a recipe whose only yield reads `250 g` is **unresolved**
///   — there is no density for a recipe, and the two stated denominations are
///   the ONLY bridge one has. It stays unresolved until somebody states the
///   tbsp side.
/// - an imprecise line ("a pinch of aioli") never resolves: [convert] refuses
///   imprecise units, and inventing a number for one is exactly what
///   invariant 3 forbids.
///
/// Nothing here ever falls back to "assume one batch". An unresolved component
/// is a first-class value the cook plan renders as a named gap, the shopping
/// list contributes nothing for, and the macro summary counts as a reason.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';

/// One stated denomination of what a batch makes: `1 cup`, `8 piece`, `250 g`.
/// A recipe states at most two, in different families.
typedef YieldDenomination = ({double qty, Unit unit});

/// The stated yields of a recipe, from its four persisted columns, with every
/// half-stated or non-positive pair dropped.
///
/// The database pins both invariants (`recipe_yield_pair`, `yield_qty > 0`),
/// so the filtering here is only what keeps the function total against foreign
/// or in-flight rows — "makes 1" without a unit is half a fact, and half a
/// fact is what the never-invent rule forbids downstream from completing.
List<YieldDenomination> yieldDenominations(
  double? qty,
  Unit? unit,
  double? qty2,
  Unit? unit2,
) => [
  if (qty != null && unit != null && qty > 0) (qty: qty, unit: unit),
  if (qty2 != null && unit2 != null && qty2 > 0) (qty: qty2, unit: unit2),
];

/// How many batches of the target recipe a component line asks for — or why
/// that cannot honestly be said.
///
/// Sealed so every surface switches exhaustively: a new unresolved reason
/// cannot be silently rendered as "no scale" by a stale `else`.
@immutable
sealed class ComponentAmount {
  const ComponentAmount();
}

/// The line resolves: [batches] whole runs of the target recipe.
///
/// [against] names the yield denomination the conversion went through, so a
/// card can say *"makes 1 cup, you need ¼"*; it is null for a line already
/// denominated in `batch`, which needed no yield at all.
///
/// [viaMeasure] names the recipe measure the line was said in, so a card can
/// say *"a batch makes 20 blob"* without a second lookup. At most one of the
/// two is ever set: a measure is a count per batch and goes nowhere near a
/// yield.
final class ResolvedComponentAmount extends ComponentAmount {
  const ResolvedComponentAmount(this.batches, {this.against, this.viaMeasure});

  final double batches;
  final YieldDenomination? against;
  final RecipeMeasure? viaMeasure;

  @override
  bool operator ==(Object other) =>
      other is ResolvedComponentAmount &&
      other.batches == batches &&
      other.against == against &&
      other.viaMeasure == viaMeasure;

  @override
  int get hashCode => Object.hash(batches, against, viaMeasure);

  @override
  String toString() => 'ResolvedComponentAmount($batches batches)';
}

/// The line does not resolve, and says why. Every subtype is a state a surface
/// renders as a named gap — never as `1×` (D3).
@immutable
sealed class UnresolvedComponentAmount extends ComponentAmount {
  const UnresolvedComponentAmount();
}

/// The line carries no number at all ("Romesco Aioli", no amount). Legal to
/// store and to render; nothing can be derived from it.
final class ComponentAmountMissing extends UnresolvedComponentAmount {
  const ComponentAmountMissing();

  @override
  bool operator ==(Object other) => other is ComponentAmountMissing;

  @override
  int get hashCode => (ComponentAmountMissing).hashCode;

  @override
  String toString() => 'ComponentAmountMissing()';
}

/// The target recipe does not say how much it makes — the D2 gap the cook
/// card names ("Romesco Aioli doesn't say how much it makes").
final class ComponentYieldMissing extends UnresolvedComponentAmount {
  const ComponentYieldMissing();

  @override
  bool operator ==(Object other) => other is ComponentYieldMissing;

  @override
  int get hashCode => (ComponentYieldMissing).hashCode;

  @override
  String toString() => 'ComponentYieldMissing()';
}

/// The target states a yield, but in no family this line can be converted
/// into: `2 tbsp` of a butter that only says `250 g`, or any imprecise line.
/// [lineFamily] and [yieldFamilies] carry what the two sides actually are, so
/// the fix-it surface can say which second denomination would close the gap.
final class ComponentFamilyMismatch extends UnresolvedComponentAmount {
  const ComponentFamilyMismatch({
    required this.lineFamily,
    required this.yieldFamilies,
  });

  final UnitFamily lineFamily;
  final List<UnitFamily> yieldFamilies;

  @override
  bool operator ==(Object other) =>
      other is ComponentFamilyMismatch &&
      other.lineFamily == lineFamily &&
      other.yieldFamilies.length == yieldFamilies.length &&
      other.yieldFamilies.every(yieldFamilies.contains);

  @override
  int get hashCode =>
      Object.hash(lineFamily, Object.hashAllUnordered(yieldFamilies));

  @override
  String toString() =>
      'ComponentFamilyMismatch(${lineFamily.name} vs '
      '${yieldFamilies.map((f) => f.name).join('/')})';
}

/// The line is said in one of the target's own words, and the target has not
/// got that word any more: retired on the other recipe, or not synced to this
/// device yet. [measureId] is the pointer the line still stores verbatim, so
/// the line is repairable rather than blanked.
///
/// **It never degrades to a count.** A measured line stores a count-family
/// unit, so re-reading `3 blob` as `3 piece` against a target that *makes 8
/// piece* would hand every total downstream 0.375 of a batch — a number
/// nobody stated, off by whatever the household meant. Three of a thing that
/// cannot be measured is not three pieces of the yield, and a wrong batch
/// count is worse here than a missing one (invariant 3).
final class ComponentMeasureMissing extends UnresolvedComponentAmount {
  const ComponentMeasureMissing(this.measureId);

  final String measureId;

  @override
  bool operator ==(Object other) =>
      other is ComponentMeasureMissing && other.measureId == measureId;

  @override
  int get hashCode => Object.hash(ComponentMeasureMissing, measureId);

  @override
  String toString() => 'ComponentMeasureMissing($measureId)';
}

/// The component graph loops back on itself — B is a component of A and A of
/// B. The server refuses such a link (migration 0017) and so does
/// [closesComponentCycle], but two devices racing can still land one, and
/// every derivation walk must stop and flag rather than recurse forever (D3).
///
/// Never returned by [resolveComponentAmount]; only the walkers produce it.
final class ComponentCycle extends UnresolvedComponentAmount {
  const ComponentCycle();

  @override
  bool operator ==(Object other) => other is ComponentCycle;

  @override
  int get hashCode => (ComponentCycle).hashCode;

  @override
  String toString() => 'ComponentCycle()';
}

/// Resolves a component line's ([quantity], [unit]) against the target's own
/// [measures] and its stated [yields] — see the library doc for the rules.
///
/// [recipeMeasureId] is the line's stored pointer at one of the target's
/// words, and [unit] is null exactly then. When it is set, [measures] — the
/// target's LIVE measures — is the only thing consulted: the word answers in
/// batches by itself, and a word the list does not hold is
/// [ComponentMeasureMissing] rather than a fall-through to any other reading
/// of the number.
///
/// The conversion runs through `core/units`' [convert] with **no density**:
/// there is no density for a recipe, so the two stated denominations are the
/// only bridge between families that exists here. That is deliberate — a
/// recipe's mass↔volume relationship is a fact about that recipe, not about a
/// substance, and guessing one would poison every derived number downstream.
ComponentAmount resolveComponentAmount({
  required double? quantity,
  required Unit? unit,
  required List<YieldDenomination> yields,
  String? recipeMeasureId,
  List<RecipeMeasure> measures = const [],
}) {
  if (quantity == null) return const ComponentAmountMissing();

  // A measure is a count per batch, so it is asked FIRST and answers alone.
  // Asking it first is what keeps the missing-word case honest: the line's
  // stored unit is a count, and letting it reach the yield path below would
  // read `3 blob` as three pieces of whatever the batch makes.
  if (recipeMeasureId != null) {
    final measure = recipeMeasureById(recipeMeasureId, measures);
    final batches = measure?.batchesFor(quantity);
    if (measure == null || batches == null) {
      return ComponentMeasureMissing(recipeMeasureId);
    }
    return ResolvedComponentAmount(batches, viaMeasure: measure);
  }

  // A number with no denomination at all: no unit and no word. The database
  // cannot store one (`num_nonnulls(unit, recipe_measure_id) = 1`) and the
  // line model asserts against it, so this is totality rather than a case —
  // and the honest reading of a bare number is that nothing was said.
  if (unit == null) return const ComponentAmountMissing();

  // `batch` is the denomination that needs no yield: the number IS the batch
  // count. This is why a component line can always be made derivable, even
  // for a recipe nobody has measured.
  if (unit.family == UnitFamily.batch) {
    return ResolvedComponentAmount(quantity);
  }

  if (yields.isEmpty) return const ComponentYieldMissing();

  for (final denomination in yields) {
    if (denomination.unit.family != unit.family) continue;
    final converted = convert(Quantity(quantity, unit), to: denomination.unit);
    // Same-family and still refused: an imprecise pair ("a pinch" against a
    // yield of "a pinch"). Honestly unresolvable, not a silent 1×.
    if (converted case Ok(:final value)) {
      return ResolvedComponentAmount(
        value.amount / denomination.qty,
        against: denomination,
      );
    }
  }

  return ComponentFamilyMismatch(
    lineFamily: unit.family,
    yieldFamilies: [for (final y in yields) y.unit.family],
  );
}

/// Whether linking `from` → `to` as a component would close a cycle: whether
/// [to] already reaches [from] over live component links (D5, checked on
/// device at link time over synced rows — the client half of the guard
/// migration 0017's trigger enforces server-side).
///
/// [componentsOf] answers "which recipes is this one built from"; anything it
/// does not know contributes nothing. Linking a recipe to itself is a cycle of
/// length one and is refused here too.
///
/// The walk carries a visited set, so it terminates even when the rows it
/// reads ALREADY contain a cycle — a pre-existing loop (a two-device race that
/// beat both guards) must not hang the device that is trying to write past it.
bool closesComponentCycle({
  required String from,
  required String to,
  required Iterable<String> Function(String recipeId) componentsOf,
}) {
  if (from == to) return true;
  final seen = <String>{to};
  final queue = <String>[to];
  while (queue.isNotEmpty) {
    for (final next in componentsOf(queue.removeLast())) {
      if (next == from) return true;
      if (seen.add(next)) queue.add(next);
    }
  }
  return false;
}
