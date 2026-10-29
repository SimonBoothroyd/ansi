import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/unit_choice.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/default_amount.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/at_home_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';

/// Records what the sheet wrote.
class _Recording implements ShoppingRepository {
  ({double quantity, Unit unit, String? measureId})? set;
  String? cleared;

  @override
  Future<void> setAtHome({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {
    set = (quantity: quantity, unit: unit, measureId: measureId);
  }

  @override
  Future<void> clearAtHome({
    required String ingredientId,
    required DateTime weekStart,
  }) async {
    cleared = ingredientId;
  }

  @override
  Future<LastAmount?> lastTopUp(String ingredientId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _flour = ShoppingItem(
  name: 'Flour',
  ingredientId: 'flour',
  totals: [Quantity(500, g)],
);

ShoppingItem _flourWith200AtHome() => _flour.copyWith(
  totals: [Quantity(300, g)],
  atHome: (
    quantity: 200,
    unit: g,
    measure: null,
    measureId: null,
    need: (totals: [Quantity(500, g)], measureTotal: null, pieceTotal: null),
    all: false,
    refusal: null,
  ),
);

Future<_Recording> _open(WidgetTester tester, ShoppingItem item) async {
  filterForuiSemanticsAssertions();
  final repo = _Recording();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        shoppingRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(FakeIngredientRepo([])),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
      ],
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => showAtHomeSheet(context, item),
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
  return repo;
}

void main() {
  testWidgets('opens on the need, says what an amount leaves to buy as it is '
      'typed, and saves what you have', (tester) async {
    final repo = await _open(tester, _flour);

    expect(find.text('this week needs'), findsOneWidget);
    expect(find.text('nothing, it’s all at home'), findsOneWidget);
    // Nothing was said yet, so there is nothing to remove.
    expect(find.text('Remove'), findsNothing);

    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pump();
    expect(find.text('300 g'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.set, (quantity: 200.0, unit: g, measureId: null));
  });

  testWidgets('opened on a row with an amount, it offers Remove', (
    tester,
  ) async {
    final repo = await _open(tester, _flourWith200AtHome());
    expect(find.text('300 g'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repo.cleared, 'flour');
  });

  test('an amount with no bridge to the need is refused, never guessed', () {
    expect(
      AtHomeSummary.leftWords(
        item: _flour,
        ingredient: const Ingredient(
          id: 'flour',
          canonicalName: 'Flour',
          defaultUnit: g,
          status: IngredientStatus.complete,
        ),
        quantity: 1,
        choice: const UnitOption(cup),
      ),
      'not counted (no density)',
    );
  });
}
