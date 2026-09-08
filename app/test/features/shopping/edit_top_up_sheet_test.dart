import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/measure_repository.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/edit_top_up_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/forui_semantics.dart';

/// Records the edit call so the test can assert what the sheet saved.
class _RecordingShoppingRepo implements ShoppingRepository {
  ({double quantity, Unit unit, String? measureId})? edited;

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  }) async {
    edited = (quantity: quantity, unit: unit, measureId: measureId);
  }

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) =>
      Stream.value(const ShoppingList());

  @override
  Future<void> setIngredientChecked({
    required String ingredientId,
    required bool checked,
    required DateTime weekStart,
  }) async {}

  @override
  Future<void> setEntryChecked({
    required String entryId,
    required bool checked,
  }) async {}

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {}

  @override
  Future<void> removeContribution({required String contributionId}) async {}

  @override
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  }) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}
}

/// The sheet watches the ingredient's measures; with no override that stream
/// errors, which the sheet now (correctly) reports instead of rendering as
/// "no measures". This one has none, and says so by having none.
class _EmptyMeasureRepo implements MeasureRepository {
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) =>
      Stream.value(const []);

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async => const {};

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
    String source = 'manual',
  }) async => throw UnimplementedError();

  @override
  Future<void> softDeleteMeasure(String measureId) async {}
}

void main() {
  testWidgets('saving an unresolved-measure top-up keeps its '
      'measure_id', (tester) async {
    // The measure row hasn't synced: the contribution arrives with
    // `measure` null but `measureId` set. An unrelated Save (say, a quantity
    // tweak) must NOT wipe the FK — that would destroy the reference for
    // every device once the row does sync.
    filterForuiSemanticsAssertions();

    final repo = _RecordingShoppingRepo();
    const contribution = ShoppingContribution(
      source: ContributionSource.manual,
      label: 'manual top-up',
      quantity: 2,
      unit: pieces,
      measureId: 'm-ghost',
      contributionId: 'c1',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          shoppingRepositoryProvider.overrideWithValue(repo),
          measureRepositoryProvider.overrideWithValue(_EmptyMeasureRepo()),
        ],
        child: MaterialApp(
          home: FTheme(
            data: ansiThemeData(),
            child: Builder(
              builder: (context) => Center(
                child: GestureDetector(
                  onTap: () => showEditTopUpSheet(
                    context,
                    itemName: 'Onion',
                    ingredientId: null,
                    contribution: contribution,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The degraded state is visible, not silent.
    expect(find.textContaining('measure pending sync'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(repo.edited, isNotNull);
    expect(repo.edited!.quantity, 3);
    expect(repo.edited!.measureId, 'm-ghost'); // preserved verbatim
  });
}
