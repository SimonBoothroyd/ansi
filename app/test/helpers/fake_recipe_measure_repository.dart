/// A [RecipeMeasureRepository] for widget tests: a little live store, with
/// canned usage counts and every write recorded.
///
/// The delete gate asks this repository *at the tap* — never a list the form is
/// holding — so a test that wants the refusal states the count here, and a test
/// that wants the delete to go through says nothing at all.
///
/// `watchRecipeMeasures` emits the store and re-emits it after every write,
/// which is what the direct door (the ＋ on a component's quantity dock) is
/// built on: a word coined there reaches the chip row because the row is
/// watching, not because anybody invalidated anything.
library;

import 'dart:async';

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeRecipeMeasureRepo implements RecipeMeasureRepository {
  FakeRecipeMeasureRepo({
    this.usage = const {},
    List<RecipeMeasure> measures = const [],
    this.refuseWith,
    this.failWith,
  }) : measures = [...measures] {
    addTearDown(_writes.close);
  }

  /// What [countLinesUsing] answers, by measure id. An id that is not here is
  /// used by nothing — which is what a word no Save has written yet is.
  final Map<String, RecipeMeasureUsage> usage;

  /// The store [watchRecipeMeasures] emits, whichever recipe is asked for, and
  /// that every write below changes.
  final List<RecipeMeasure> measures;

  /// A sentence the authoring writes refuse with — the repository's own
  /// [RecipeMeasureRefused], which a form prints under its field.
  final String? refuseWith;

  /// Anything else an authoring write can throw: the failure a door must
  /// report through the write door rather than swallow.
  final Object? failWith;

  /// Every id [countLinesUsing] was asked about, in order — so a test can see
  /// that the gate really asked rather than trusting a list.
  final counted = <String>[];

  /// Every id handed to [softDeleteRecipeMeasure].
  final deleted = <String>[];

  /// Every word coined here, and every re-statement, in order.
  final added = <RecipeMeasure>[];
  final restated = <RecipeMeasure>[];

  final _writes = StreamController<List<RecipeMeasure>>.broadcast();

  void _emit() {
    if (!_writes.isClosed) _writes.add([...measures]);
  }

  void _refuseOrFail() {
    // A fake's whole job is to throw what the real one throws.
    // ignore: only_throw_errors
    if (failWith case final e?) throw e;
    if (refuseWith case final reason?) {
      throw RecipeMeasureRefused('recipe_measure/refused', reason);
    }
  }

  @override
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId) async* {
    yield [...measures];
    yield* _writes.stream;
  }

  @override
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double amount,
    required Unit unit,
  }) async {
    _refuseOrFail();
    final coined = RecipeMeasure(
      id: 'coined-${added.length + 1}',
      recipeId: recipeId,
      label: label,
      amount: amount,
      unit: unit,
      sortOrder: measures.length,
    );
    measures.add(coined);
    added.add(coined);
    _emit();
    return coined;
  }

  @override
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double amount,
    required Unit unit,
  }) async {
    _refuseOrFail();
    final at = measures.indexWhere((m) => m.id == measureId);
    if (at < 0) {
      throw const RecipeMeasureRefused('recipe_measure/gone', 'no such word');
    }
    // The id is kept, which is the whole point of a re-statement.
    final word = measures[at].copyWith(
      label: label,
      amount: amount,
      unit: unit,
    );
    measures[at] = word;
    restated.add(word);
    _emit();
  }

  @override
  Future<void> reorderRecipeMeasures(String recipeId, List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<RecipeMeasureUsage> countLinesUsing(String measureId) async {
    counted.add(measureId);
    return usage[measureId] ?? RecipeMeasureUsage.none;
  }

  @override
  Future<void> softDeleteRecipeMeasure(String measureId) async {
    deleted.add(measureId);
    measures.removeWhere((m) => m.id == measureId);
    _emit();
  }
}
