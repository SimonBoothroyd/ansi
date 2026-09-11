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

  /// What [countLinesUsing] answers, by measure id — the delete guard's own
  /// seam. Empty means nothing says any of them, which is the ordinary case.
  final Map<String, MeasureUsage> usage = {};

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
  Future<void> renameMeasure(String measureId, String label) async {
    _replace(measureId, (m) => _copy(m, label: label));
  }

  @override
  Future<void> setMeasureAmount(String measureId, double amount) async {
    _replace(measureId, (m) => _copy(m, amount: amount));
  }

  void _replace(String id, Measure Function(Measure) edit) {
    final i = rows.indexWhere((m) => m.id == id);
    if (i < 0) return;
    rows[i] = edit(rows[i]);
    _changes.add(null);
  }

  static Measure _copy(Measure m, {String? label, double? amount}) => Measure(
    id: m.id,
    label: label ?? m.label,
    amount: amount ?? m.amount,
    basis: m.basis,
    sortOrder: m.sortOrder,
    source: m.source,
  );

  @override
  Future<void> reorderMeasures(String ingredientId, List<String> ids) async {
    final byId = {for (final m in rows) m.id: m};
    final moved = [
      for (final id in ids)
        if (byId[id] case final m?) m,
    ];
    rows
      ..clear()
      ..addAll(moved);
    _changes.add(null);
  }

  @override
  Future<MeasureUsage> countLinesUsing(String measureId) async =>
      usage[measureId] ?? MeasureUsage.none;

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    rows.removeWhere((m) => m.id == measureId);
    _changes.add(null);
  }
}
