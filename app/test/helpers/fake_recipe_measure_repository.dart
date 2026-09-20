/// A [RecipeMeasureRepository] for widget tests: the usage counts are canned
/// and every write is recorded.
///
/// The delete gate asks this repository *at the tap* — never a list the form is
/// holding — so a test that wants the refusal states the count here, and a test
/// that wants the delete to go through says nothing at all.
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';

class FakeRecipeMeasureRepo implements RecipeMeasureRepository {
  FakeRecipeMeasureRepo({this.usage = const {}, this.measures = const []});

  /// What [countLinesUsing] answers, by measure id. An id that is not here is
  /// used by nothing — which is what a word no Save has written yet is.
  final Map<String, RecipeMeasureUsage> usage;

  /// What [watchRecipeMeasures] emits, whichever recipe is asked for.
  final List<RecipeMeasure> measures;

  /// Every id [countLinesUsing] was asked about, in order — so a test can see
  /// that the gate really asked rather than trusting a list.
  final counted = <String>[];

  /// Every id handed to [softDeleteRecipeMeasure].
  final deleted = <String>[];

  @override
  Stream<List<RecipeMeasure>> watchRecipeMeasures(String recipeId) =>
      Stream.value(measures);

  @override
  Future<RecipeMeasure> addRecipeMeasure({
    required String recipeId,
    required String label,
    required double amount,
    required Unit unit,
  }) async => throw UnimplementedError();

  @override
  Future<void> restateRecipeMeasure({
    required String measureId,
    required String label,
    required double amount,
    required Unit unit,
  }) async => throw UnimplementedError();

  @override
  Future<void> reorderRecipeMeasures(String recipeId, List<String> ids) async =>
      throw UnimplementedError();

  @override
  Future<RecipeMeasureUsage> countLinesUsing(String measureId) async {
    counted.add(measureId);
    return usage[measureId] ?? RecipeMeasureUsage.none;
  }

  @override
  Future<void> softDeleteRecipeMeasure(String measureId) async =>
      deleted.add(measureId);
}
