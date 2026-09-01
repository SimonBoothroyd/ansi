import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/edit_top_up_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    String? measureId,
  }) async {}

  @override
  Future<void> removeContribution({required String contributionId}) async {}

  @override
  Future<void> addFreeTextItem({
    required String text,
    String? category,
  }) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}
}

void main() {
  testWidgets('saving an unresolved-measure top-up keeps its measure_id '
      '(review A1)', (tester) async {
    // The measure row hasn't synced: the contribution arrives with
    // `measure` null but `measureId` set. An unrelated Save (say, a quantity
    // tweak) must NOT wipe the FK — that would destroy the reference for
    // every device once the row does sync.
    // Opening a Forui sheet with the semantics tree live trips a framework
    // assertion (tracker row `app/ui`); filter exactly that, as the
    // integration smoke does.
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

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
        overrides: [shoppingRepositoryProvider.overrideWithValue(repo)],
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
