/// Batch math for a component line: how many batches of the target its amount
/// asks for. Pure Dart.
///
/// A line resolves against the target's stated yield in its own unit family (`¼
/// cup` of `makes 1 cup` is 0.25); `1 batch` always resolves; a line in one of
/// the target's measures (ADR-0018) converts to that measure's amount first. A
/// recipe has no density, so an off-family, imprecise or yield-less line is
/// unresolved: a named gap, never an assumed batch.
library;

import 'package:meta/meta.dart';

import '../../../core/result/result.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';

/// One stated denomination of what a batch makes: `1 cup`, `8 piece`, `250 g`.
typedef YieldDenomination = ({double qty, Unit unit});

/// A recipe's stated yields from its four persisted columns, dropping any
/// half-stated or non-positive pair. The database forbids those; the filter
/// guards foreign or in-flight rows.
List<YieldDenomination> yieldDenominations(
  double? qty,
  Unit? unit,
  double? qty2,
  Unit? unit2,
) => [
  if (qty != null && unit != null && qty > 0) (qty: qty, unit: unit),
  if (qty2 != null && unit2 != null && qty2 > 0) (qty: qty2, unit: unit2),
];

/// How many batches of the target a component line asks for, or why that cannot
/// be said. Sealed so every surface switches exhaustively.
@immutable
sealed class ComponentAmount {
  const ComponentAmount();
}

/// The line resolves to [batches] runs of the target recipe.
///
/// [against] is the yield denomination the conversion went through; null for a
/// line in `batch`. [viaMeasure] is the recipe measure the line was said in. A
/// measured line sets both: `3 blob → 45 g → 0.15 of a batch`.
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

/// The line does not resolve, and says why. Rendered as a named gap, never as
/// `1×`.
@immutable
sealed class UnresolvedComponentAmount extends ComponentAmount {
  const UnresolvedComponentAmount();
}

/// The line carries no number ("Romesco Aioli", no amount).
final class ComponentAmountMissing extends UnresolvedComponentAmount {
  const ComponentAmountMissing();

  @override
  bool operator ==(Object other) => other is ComponentAmountMissing;

  @override
  int get hashCode => (ComponentAmountMissing).hashCode;

  @override
  String toString() => 'ComponentAmountMissing()';
}

/// The target recipe does not say how much it makes.
final class ComponentYieldMissing extends UnresolvedComponentAmount {
  const ComponentYieldMissing();

  @override
  bool operator ==(Object other) => other is ComponentYieldMissing;

  @override
  int get hashCode => (ComponentYieldMissing).hashCode;

  @override
  String toString() => 'ComponentYieldMissing()';
}

/// The target states a yield, but in no family this line converts into: `2
/// tbsp` of a butter that only says `250 g`, or any imprecise line.
/// [lineFamily] and [yieldFamilies] say which denomination would close the gap.
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

/// The line is said in one of the target's measures and the target lacks it
/// (retired or not yet synced). [measureId] is the stored pointer, so the line
/// is repairable. It never degrades to a count: reading `3 blob` as `3 piece`
/// would invent a batch share.
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

/// The component graph loops back on itself. The server and
/// [closesComponentCycle] both refuse such a link, but two racing devices can
/// still land one, so every walk must stop and flag it. Produced only by the
/// walkers, never by [resolveComponentAmount].
final class ComponentCycle extends UnresolvedComponentAmount {
  const ComponentCycle();

  @override
  bool operator ==(Object other) => other is ComponentCycle;

  @override
  int get hashCode => (ComponentCycle).hashCode;

  @override
  String toString() => 'ComponentCycle()';
}

/// Resolves a component line's ([quantity], [unit]) against the target's
/// [measures] and [yields]; see the library doc. [unit] is null exactly when
/// [recipeMeasureId] is set; the measure's amount then goes through the same
/// yield loop, and a measure [measures] lacks is [ComponentMeasureMissing].
/// [convert] runs with no density.
ComponentAmount resolveComponentAmount({
  required double? quantity,
  required Unit? unit,
  required List<YieldDenomination> yields,
  String? recipeMeasureId,
  List<RecipeMeasure> measures = const [],
}) {
  if (quantity == null) return const ComponentAmountMissing();

  // The measure is asked first and its unit wins: a `unit` stored beside a
  // measure pointer is foreign or in-flight data (the database's XOR forbids
  // it).
  var said = quantity;
  var saidIn = unit;
  RecipeMeasure? measure;

  if (recipeMeasureId != null) {
    measure = recipeMeasureById(recipeMeasureId, measures);
    final total = measure?.totalFor(quantity);
    if (measure == null || total == null) {
      return ComponentMeasureMissing(recipeMeasureId);
    }
    said = total.amount;
    saidIn = total.unit;
  }

  // No unit and no word. The database cannot store this; handled for totality.
  if (saidIn == null) return const ComponentAmountMissing();

  // `batch` needs no yield: the number is the batch count. A measure never
  // arrives here (`kRecipeMeasureFamilies` refuses one said in batches).
  if (saidIn.family == UnitFamily.batch) {
    return ResolvedComponentAmount(said);
  }

  if (yields.isEmpty) return const ComponentYieldMissing();

  for (final denomination in yields) {
    if (denomination.unit.family != saidIn.family) continue;
    final converted = convert(Quantity(said, saidIn), to: denomination.unit);
    // Same family and still refused: an imprecise pair. Unresolved, not 1×.
    if (converted case Ok(:final value)) {
      return ResolvedComponentAmount(
        value.amount / denomination.qty,
        against: denomination,
        viaMeasure: measure,
      );
    }
  }

  return ComponentFamilyMismatch(
    lineFamily: saidIn.family,
    yieldFamilies: [for (final y in yields) y.unit.family],
  );
}

/// Whether [measure] resolves to a share of a batch against [yields]. Calls the
/// real resolution, so the chip offer, the editor's orphan warning and line
/// resolution agree.
bool recipeMeasureResolvesAgainst(
  RecipeMeasure measure,
  List<YieldDenomination> yields,
) =>
    resolveComponentAmount(
          quantity: 1,
          unit: null,
          yields: yields,
          recipeMeasureId: measure.id,
          measures: [measure],
        )
        is ResolvedComponentAmount;

/// Whether linking `from` → `to` as a component would close a cycle, i.e. [to]
/// already reaches [from] over live component links. The client half of the
/// server's trigger guard.
///
/// [componentsOf] returns the recipes one is built from. A self-link is
/// refused. The walk carries a visited set, so it terminates even over rows
/// that already contain a cycle.
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
