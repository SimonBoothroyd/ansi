/// [defaultMeasureOf] — the seed the Week's add-an-ingredient flow hands the
/// quantity sheet, and the reason it goes through [MeasureRepository].
///
/// The regression this pins: the lookup used to be a one-shot
/// `ref.read(ingredientMeasuresProvider(id).future)`. That provider is
/// autoDispose and its source is a PowerSync `watch`, which never emits
/// synchronously, so with nobody listening the element was disposed before the
/// first emission and the read threw `StateError` — a red screen on the first
/// ingredient anybody planned. The fake below is asynchronous for the same
/// reason PowerSync is, and refuses [MeasureRepository.watchMeasures]
/// outright, so a return to the stream shape fails here rather than on a
/// phone.
library;

import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/planning/presentation/week_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Measures keyed by ingredient, answered a microtask later — and no stream
/// at all: a caller that reaches for one has reintroduced the bug.
class _AsyncMeasureRepo implements MeasureRepository {
  _AsyncMeasureRepo(this.byIngredient);

  final Map<String, List<Measure>> byIngredient;
  final asked = <Set<String>>[];

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async {
    asked.add(ids);
    await Future<void>.delayed(Duration.zero);
    return {
      for (final id in ids)
        if (byIngredient[id] case final rows?) id: rows,
    };
  }

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      throw StateError('the seed lookup must not open a stream');

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) => throw UnimplementedError();

  @override
  Future<void> softDeleteMeasure(String measureId) =>
      throw UnimplementedError();
}

Ingredient ingredientWith(String? defaultMeasureId) => Ingredient(
  id: 'ing-1',
  canonicalName: 'edamame, frozen',
  defaultUnit: g,
  status: IngredientStatus.complete,
  defaultMeasureId: defaultMeasureId,
);

void main() {
  const bag = Measure(id: 'm-bag', label: 'bag (500 g)', amount: 500);
  const pod = Measure(id: 'm-pod', label: 'pod', amount: 2);
  final repo = _AsyncMeasureRepo({
    'ing-1': const [bag, pod],
  });

  test('resolves the stated default through the repository, not a stream', () {
    expect(defaultMeasureOf(repo, ingredientWith('m-pod')), completion(pod));
    expect(repo.asked, [
      {'ing-1'},
    ]);
  });

  test('"ask me each time" is null, and costs no query', () async {
    final quiet = _AsyncMeasureRepo({
      'ing-1': const [bag],
    });
    expect(await defaultMeasureOf(quiet, ingredientWith(null)), isNull);
    expect(quiet.asked, isEmpty);
  });

  test('an id nothing resolves reads as null rather than throwing', () {
    expect(defaultMeasureOf(repo, ingredientWith('m-gone')), completion(null));
  });

  test('an ingredient with no measures at all reads as null', () {
    final empty = _AsyncMeasureRepo(const {});
    expect(defaultMeasureOf(empty, ingredientWith('m-pod')), completion(null));
  });
}
