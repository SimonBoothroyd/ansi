/// An in-memory [MeasureRepository] for widget tests that walk the add-new
/// chain (sheet → form → picker), where the sheet's pack-size tick and the
/// form's embedded editor both need somewhere to write.
library;

import 'dart:async';

import 'package:ansi/core/units/measure.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';

class FakeMeasureRepo implements MeasureRepository {
  FakeMeasureRepo([List<Measure> initial = const []]) : rows = [...initial];

  final List<Measure> rows;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) async* {
    yield [...rows];
    yield* _changes.stream.map((_) => [...rows]);
  }

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => {
    for (final id in ids) id: [...rows],
  };

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async {
    final m = Measure(id: 'm-${rows.length}', label: label, amount: amount);
    rows.add(m);
    _changes.add(null);
    return m;
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    rows.removeWhere((m) => m.id == measureId);
    _changes.add(null);
  }
}
