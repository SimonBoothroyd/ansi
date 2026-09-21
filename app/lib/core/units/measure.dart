/// Named ingredient measures: a word for one thing, pinned to an amount in the
/// ingredient's basis unit ("clove = 3 g"). See ADR-0008.
///
/// Pure Dart. A measure bridges to the basis family only; crossing mass↔volume
/// still needs the ingredient's density. A non-positive or NaN amount is a
/// typed [Failure], never a fabricated number.
library;

import 'package:meta/meta.dart';

import '../result/result.dart';
import 'macros.dart';
import 'number_format.dart';
import 'unit_words.dart';
import 'units.dart';

/// What an ingredient's measure and a recipe's share: the columns the
/// merge-on-read and the duplicate check read.
abstract interface class LabelledMeasure {
  String get id;
  String get label;
  int get sortOrder;
}

/// One stored measure with its raw `created_at` text, as [mergeByLabel] takes
/// it.
typedef StoredMeasure<T extends LabelledMeasure> = ({
  T measure,
  Object? createdAt,
});

/// [rows] with duplicate labels merged: the oldest row of each label kept,
/// ordered `sort_order`, then age, then id.
///
/// No unique index guards a label (two offline phones can coin the same word),
/// so the newer row is hidden on read. The key is the label exactly as stored.
List<T> mergeByLabel<T extends LabelledMeasure>(
  Iterable<StoredMeasure<T>> rows,
) {
  final ordered = [
    for (final r in rows)
      (measure: r.measure, created: _createdKey(r.createdAt)),
  ]..sort(_byAge);

  final byLabel = <String, ({T measure, String created})>{};
  for (final e in ordered) {
    byLabel.putIfAbsent(e.measure.label, () => e); // newer dupe hidden
  }
  final kept = byLabel.values.toList()
    ..sort((a, b) {
      final bySort = a.measure.sortOrder.compareTo(b.measure.sortOrder);
      return bySort != 0 ? bySort : _byAge(a, b);
    });
  return [for (final e in kept) e.measure];
}

int _byAge(
  ({LabelledMeasure measure, String created}) a,
  ({LabelledMeasure measure, String created}) b,
) {
  final byCreated = a.created.compareTo(b.created);
  return byCreated != 0 ? byCreated : a.measure.id.compareTo(b.measure.id);
}

/// `created_at` as a comparable key: canonical UTC ISO-8601, or the raw text
/// where it does not parse.
///
/// The column is TEXT and writers format it differently, so a bare string
/// compare picks the wrong oldest. A value with no zone is read as UTC.
String _createdKey(Object? raw) {
  final s = raw as String? ?? '';
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return s;
  final utc = parsed.isUtc
      ? parsed
      : DateTime.tryParse('${s.trim()}Z') ?? parsed.toUtc();
  return utc.toIso8601String();
}

/// The first of [measures] already carrying [label], ignoring case, or null.
/// Looser than [mergeByLabel]: it refuses what a person reads as the same word.
T? measureAlreadyNamed<T extends LabelledMeasure>(
  String label,
  Iterable<T> measures,
) {
  final word = measureLabelAsAuthored(label).toLowerCase();
  if (word.isEmpty) return null;
  for (final m in measures) {
    if (measureLabelAsAuthored(m.label).toLowerCase() == word) return m;
  }
  return null;
}

/// The provenance families a [Measure.source] can carry, for at-a-glance
/// display (7.7). [unknown] covers pre-0010 rows and unrecognized strings.
enum MeasureSourceKind { usdaPortion, borrowed, typical, manual, unknown }

/// One named measure of one ingredient: `n` of it are `n × amount` of the
/// ingredient's basis unit ([basis]).
///
/// [id] is the persisted `ingredient_measure.id`.
@immutable
class Measure implements LabelledMeasure {
  const Measure({
    required this.id,
    required this.label,
    required this.amount,
    this.basis = MacrosBasis.perG,
    this.sortOrder = 0,
    this.source,
  });

  @override
  final String id;

  /// Human label, e.g. `potato, large`, `can (400 ml)`, `clove`.
  @override
  final String label;

  /// Amount of one of this measure, in the ingredient's basis unit. A
  /// non-positive value is rejected at conversion time.
  final double amount;

  /// The unit [amount] is denominated in: the ingredient's `macros_basis`,
  /// joined in by the reader (the row stores none).
  final MacrosBasis basis;

  @override
  final int sortOrder;

  /// Where the amount comes from: `usda_fdc:<fdc_id> (<portion>)`, `manual`,
  /// `seed:typical`, or null.
  final String? source;

  /// [source] classified for display.
  MeasureSourceKind get sourceKind {
    final s = source;
    if (s == null) return MeasureSourceKind.unknown;
    if (s.startsWith('usda_fdc:')) {
      return s.contains('borrowed')
          ? MeasureSourceKind.borrowed
          : MeasureSourceKind.usdaPortion;
    }
    if (s == 'seed:typical') return MeasureSourceKind.typical;
    if (s == 'manual') return MeasureSourceKind.manual;
    return MeasureSourceKind.unknown;
  }

  @override
  bool operator ==(Object other) =>
      other is Measure &&
      other.id == id &&
      other.label == label &&
      other.amount == amount &&
      other.basis == basis &&
      other.sortOrder == sortOrder &&
      other.source == source;

  @override
  int get hashCode => Object.hash(id, label, amount, basis, sortOrder, source);

  @override
  String toString() => 'Measure($label = $amount ${basis.baseUnit.id})';
}

/// How far two amounts may sit apart and still be the same fact: 1 % either
/// side. Shared by `wholeMeasureOf` (ADR-0016) and `wholeMeasureOfRecipe`
/// (ADR-0018).
const kWholeMeasureTolerance = 0.01;

/// [label] as the household wrote it: trimmed, inner whitespace runs collapsed
/// to one space. Case is never changed.
///
/// Every door that authors a measure label reads it through this, so ` Can `
/// and `Can` do not become two rows.
String measureLabelAsAuthored(String label) =>
    label.trim().replaceAll(RegExp(r'\s+'), ' ');

// --- A measure's word, printed with what one of it comes to ------------------

/// `jar (340 g)`: [word] with the basis amount behind it, or the word alone
/// where it already states its size (`can (14.5 oz)`).
String measureWordWithSize(String word, double basisAmount, Unit basisUnit) =>
    measureWordStatesSize(word)
    ? word
    : '$word (${formatAmountIn(basisAmount, basisUnit)} ${basisUnit.label})';

/// Whether [word] already states a size: a bracketed amount followed by a
/// catalog unit, e.g. `can (14.5 oz)`.
///
/// Deliberately narrow: `can (drained)` and `head, large` still take the weight
/// appended.
bool measureWordStatesSize(String word) {
  for (final bracketed in _bracketed.allMatches(word)) {
    final inside = _amountThenUnit.firstMatch(bracketed.group(1)!.trim());
    if (inside == null) continue;
    if (parseAmount(inside.group(1)!) == null) continue;
    if (unitFromLabel(inside.group(2)!) != null) return true;
  }
  return false;
}

final _bracketed = RegExp(r'\(([^()]*)\)');

/// The amount is everything before the first letter, the unit everything from
/// it — so `14.5 oz`, `14.5oz` and `½ lb` all split where a reader splits them.
final _amountThenUnit = RegExp(r'^([^A-Za-z]+)([A-Za-z][A-Za-z ]*)$');

/// Converts [amount] of [measure] into [to] via the measure's basis amount.
///
/// Within the basis family no density is needed; crossing mass↔volume needs
/// [densityGPerMl] (`unit/no_density` without). Count and imprecise targets are
/// `unit/incompatible`; a non-positive or NaN [Measure.amount] is
/// `measure/invalid_amount`.
Result<Quantity> convertMeasure(
  double amount,
  Measure measure, {
  required Unit to,
  double? densityGPerMl,
}) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(measure.amount > 0)) {
    return const Err(
      Failure(
        'measure/invalid_amount',
        'a measure needs a positive basis amount',
      ),
    );
  }
  return convert(
    Quantity(amount * measure.amount, measure.basis.baseUnit),
    to: to,
    densityGPerMl: densityGPerMl,
  );
}

/// Converts quantity [q] into a count of [measure] ("674 g ≈ 2.25 × potato,
/// large"). The inverse of [convertMeasure], with the same failures.
Result<double> amountInMeasure(
  Quantity q,
  Measure measure, {
  double? densityGPerMl,
}) {
  if (!(measure.amount > 0)) {
    return const Err(
      Failure(
        'measure/invalid_amount',
        'a measure needs a positive basis amount',
      ),
    );
  }
  final inBasis = convert(
    q,
    to: measure.basis.baseUnit,
    densityGPerMl: densityGPerMl,
  );
  return switch (inBasis) {
    Ok(:final value) => Ok(value.amount / measure.amount),
    Err(:final failure) => Err(failure),
  };
}
