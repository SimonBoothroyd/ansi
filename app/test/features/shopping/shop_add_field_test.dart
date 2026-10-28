/// The Shop's add field: one search at the top that adds an ingredient
/// (through the quantity sheet, on its usual amount) or the words as a
/// non-food item, and ends every search with the same two rows.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/default_amount.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/shopping/data/shopping_providers.dart';
import 'package:ansi/features/shopping/domain/shopping.dart';
import 'package:ansi/features/shopping/domain/shopping_repository.dart';
import 'package:ansi/features/shopping/presentation/shop_add_field.dart';
import 'package:ansi/features/shopping/presentation/shopping_format.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';

const _lime = Ingredient(
  id: 'i-lime',
  canonicalName: 'Lime',
  defaultUnit: pieces,
  pieceBasisAmount: 67,
  category: 'Produce',
  status: IngredientStatus.complete,
);

const _limeLeaves = Ingredient(
  id: 'i-lime-leaves',
  canonicalName: 'Lime Leaves, makrut',
  defaultUnit: pieces,
  category: 'Produce',
  status: IngredientStatus.complete,
);

const _pepper = Ingredient(
  id: 'i-pepper',
  canonicalName: 'Pepper, black',
  defaultUnit: g,
  category: 'Spices',
  status: IngredientStatus.complete,
);

/// Lime is already on this week's list.
final _listedLime = ShoppingItem(
  name: 'Lime',
  ingredientId: 'i-lime',
  entryId: 'e-lime',
  totals: [Quantity(3, pieces)],
);

ShoppingList _list() => ShoppingList(
  groups: [
    ShoppingGroup(label: 'Produce', items: [_listedLime]),
  ],
);

/// The vocabulary as the repository's tiers answer it: a substring match is
/// spelled right; with none, the [guesses] (if any) come back as guesses.
class _Vocab extends FakeIngredientRepo {
  _Vocab(super.initial, {this.guesses = const []});

  final List<Ingredient> guesses;

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    final hits = [
      for (final r in rows)
        if (r.canonicalName.toLowerCase().contains(q)) r,
    ];
    return hits.isNotEmpty
        ? (rows: hits, guessed: false)
        : (rows: guesses, guessed: guesses.isNotEmpty);
  }
}

/// Records the two writes the field makes; the list it serves never moves.
class _Shopping implements ShoppingRepository {
  _Shopping({this.last});

  final LastAmount? last;

  final topUps =
      <
        ({String ingredientId, double quantity, Unit unit, String? measureId})
      >[];
  final freeText = <String>[];

  @override
  Stream<ShoppingList> watchShoppingList(DateTime weekStart) =>
      Stream.value(_list());

  @override
  Future<void> addTopUp({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async => topUps.add((
    ingredientId: ingredientId,
    quantity: quantity,
    unit: unit,
    measureId: measureId,
  ));

  @override
  Future<void> addFreeTextItem({
    required String text,
    required DateTime weekStart,
    String? category,
  }) async => freeText.add(text);

  @override
  Future<LastAmount?> lastTopUp(String ingredientId) async => last;

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
  Future<void> setAtHome({
    required String ingredientId,
    required double quantity,
    required Unit unit,
    required DateTime weekStart,
    String? measureId,
  }) async {}

  @override
  Future<void> clearAtHome({
    required String ingredientId,
    required DateTime weekStart,
  }) async {}

  @override
  Future<void> editContribution({
    required String contributionId,
    required double quantity,
    required Unit unit,
    String? measureId,
  }) async {}

  @override
  Future<void> removeContribution({required String contributionId}) async {}

  @override
  Future<void> removeEntry({required String entryId}) async {}
}

/// The Shop under a router, so the new-ingredient chain has a form to push.
Widget _host({
  required FakeIngredientRepo vocab,
  required _Shopping shopping,
  List<Measure> measures = const [],
}) {
  // Every test here opens a sheet or types into a live semantics tree.
  filterForuiSemanticsAssertions();
  final router = GoRouter(
    initialLocation: '/shop',
    routes: [
      GoRoute(path: '/shop', builder: (_, _) => const ShoppingView()),
      GoRoute(
        path: '/ingredients/new',
        builder: (context, state) => FScaffold(
          child: FButton(
            onPress: () async {
              // What the form's one Save does: the row and everything the
              // form set, then pop with it.
              final saved = await vocab.saveForm(
                null,
                IngredientFormEdit(
                  row: IngredientEdit(
                    canonicalName: state.uri.queryParameters['name'] ?? '',
                    defaultUnit: g,
                    macrosBasis: MacrosBasis.perG,
                    allowedUnits: {g, kg},
                  ),
                ),
              );
              if (context.mounted) context.pop(saved.valueOrNull);
            },
            child: const Text('create'),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: [
      shoppingRepositoryProvider.overrideWithValue(shopping),
      ingredientRepositoryProvider.overrideWithValue(vocab),
      measureRepositoryProvider.overrideWithValue(FakeMeasureRepo(measures)),
      usdaProbeProvider.overrideWithValue(const SilentUsdaProbe()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(
        data: ansiThemeData(),
        child: FToaster(child: child!),
      ),
    ),
  );
}

Finder get _field => find.descendant(
  of: find.byKey(kShopAddFieldKey),
  matching: find.byType(EditableText),
);

String _fieldText(WidgetTester tester) =>
    tester.widget<EditableText>(_field).controller.text;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pumpAndSettle();
}

/// What the quantity sheet's amount field says.
String _sheetAmount(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText).last).controller.text;

Finder _inResults(Finder f) =>
    find.descendant(of: find.byKey(kShopAddResultsKey), matching: f);

/// The labels of the result list, top to bottom.
List<String> _order(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(_inResults(find.byType(Text))))
    ?t.data,
];

void main() {
  testWidgets('typing finds ingredients in place of the walk, and a listed '
      'one says it is on the list', (tester) async {
    await tester.pumpWidget(
      _host(vocab: _Vocab(const [_lime, _limeLeaves]), shopping: _Shopping()),
    );
    await tester.pumpAndSettle();
    // The walk, under an empty field.
    expect(find.byKey(kShopAddResultsKey), findsNothing);
    expect(find.text('PRODUCE'), findsOneWidget);

    await _type(tester, 'lim');
    expect(find.byKey(kShopAddResultsKey), findsOneWidget);
    expect(find.text('PRODUCE'), findsNothing, reason: 'the walk stood down');
    expect(
      _inResults(
        find.text('Produce · on the list · ${itemTotal(_listedLime)}'),
      ),
      findsOneWidget,
    );
    expect(_inResults(find.text('Lime Leaves, makrut')), findsOneWidget);
    expect(_inResults(find.text('Produce')), findsOneWidget);

    // Clearing brings the walk back.
    await _type(tester, '');
    expect(find.byKey(kShopAddResultsKey), findsNothing);
    expect(find.text('PRODUCE'), findsOneWidget);
  });

  testWidgets('leaving the field brings the walk back', (tester) async {
    await tester.pumpWidget(
      _host(vocab: _Vocab(const [_lime]), shopping: _Shopping()),
    );
    await tester.pumpAndSettle();
    await _type(tester, 'lim');
    expect(find.byKey(kShopAddResultsKey), findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(find.byKey(kShopAddResultsKey), findsNothing);
    expect(find.text('PRODUCE'), findsOneWidget);
  });

  group('every search ends with the same two rows', () {
    testWidgets('under spelled-right results', (tester) async {
      await tester.pumpWidget(
        _host(vocab: _Vocab(const [_lime]), shopping: _Shopping()),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'lim');

      final order = _order(tester);
      expect(
        order.indexOf('Lime'),
        lessThan(order.indexOf('"lim" as a non-food item')),
      );
      expect(
        order.indexOf('"lim" as a non-food item'),
        lessThan(order.indexOf('"lim" as a new ingredient')),
      );
      // Each row is its title alone.
      expect(find.text('no amount · it just gets ticked'), findsNothing);
      expect(
        find.text('opens the ingredient form, then its amount'),
        findsNothing,
      );
      expect(find.textContaining('can’t find it'), findsNothing);
      expect(find.text('INGREDIENTS'), findsNothing);
    });

    testWidgets('under the did-you-mean band', (tester) async {
      await tester.pumpWidget(
        _host(
          vocab: _Vocab(const [_lime], guesses: const [_pepper]),
          shopping: _Shopping(),
        ),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'paper towels');

      final order = _order(tester);
      expect(order.indexOf('Pepper, black'), greaterThanOrEqualTo(0));
      expect(
        order.indexOf('Pepper, black'),
        lessThan(order.indexOf('"paper towels" as a non-food item')),
      );
      expect(
        order.indexOf('"paper towels" as a non-food item'),
        lessThan(order.indexOf('"paper towels" as a new ingredient')),
      );
    });

    testWidgets('with no match at all', (tester) async {
      await tester.pumpWidget(
        _host(vocab: _Vocab(const [_lime]), shopping: _Shopping()),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'paper towels');

      expect(find.byKey(kShopAddFreeTextKey), findsOneWidget);
      expect(find.byKey(kShopAddNewIngredientKey), findsOneWidget);
      expect(find.text('"paper towels" as a non-food item'), findsOneWidget);
      expect(find.text('"paper towels" as a new ingredient'), findsOneWidget);
    });
  });

  testWidgets('the non-food row adds the words with no sheet, and the field '
      'clears', (tester) async {
    final shopping = _Shopping();
    await tester.pumpWidget(
      _host(vocab: _Vocab(const [_lime]), shopping: shopping),
    );
    await tester.pumpAndSettle();
    await _type(tester, 'paper towels');

    await tester.tap(find.byKey(kShopAddFreeTextKey));
    await tester.pumpAndSettle();

    expect(shopping.freeText, ['paper towels']);
    expect(shopping.topUps, isEmpty);
    expect(find.text('Add to list'), findsNothing, reason: 'no second sheet');
    expect(_fieldText(tester), isEmpty);
    expect(find.byKey(kShopAddResultsKey), findsNothing);
    expect(find.text('PRODUCE'), findsOneWidget);
  });

  testWidgets('a pick opens the sheet on its usual amount, and Add to list '
      'writes the top-up in its unit', (tester) async {
    final shopping = _Shopping();
    await tester.pumpWidget(
      _host(vocab: _Vocab(const [_lime]), shopping: shopping),
    );
    await tester.pumpAndSettle();
    await _type(tester, 'lim');

    await tester.tap(_inResults(find.text('Lime')));
    await tester.pumpAndSettle();
    // One piece is its usual amount: nothing was topped up before, and it has
    // no measure.
    expect(find.text('Add to list'), findsOneWidget);
    expect(_sheetAmount(tester), '1');
    expect(shopping.topUps, isEmpty, reason: 'nothing until the sheet says');

    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    expect(shopping.topUps, [
      (ingredientId: 'i-lime', quantity: 1.0, unit: pieces, measureId: null),
    ]);
    expect(_fieldText(tester), isEmpty);
    expect(find.byKey(kShopAddResultsKey), findsNothing);
  });

  testWidgets('a top-up in a measure writes its count in pieces beside the '
      'measure', (tester) async {
    const whole = Measure(id: 'm-lime', label: 'lime, whole', amount: 67);
    final shopping = _Shopping(
      last: (quantity: 2, unit: pieces, measureId: 'm-lime'),
    );
    await tester.pumpWidget(
      _host(
        vocab: _Vocab(const [_lime]),
        shopping: shopping,
        measures: const [whole],
      ),
    );
    await tester.pumpAndSettle();
    await _type(tester, 'lim');
    await tester.tap(_inResults(find.text('Lime')));
    await tester.pumpAndSettle();

    // Opened on the last top-up of it: two of its measure.
    expect(_sheetAmount(tester), '2');
    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    expect(shopping.topUps, [
      (
        ingredientId: 'i-lime',
        quantity: 2.0,
        unit: pieces,
        measureId: 'm-lime',
      ),
    ]);
  });

  testWidgets(
    'backing out of the sheet writes nothing and leaves the results',
    (tester) async {
      final shopping = _Shopping();
      await tester.pumpWidget(
        _host(vocab: _Vocab(const [_lime]), shopping: shopping),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'lim');
      await tester.tap(_inResults(find.text('Lime')));
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.text('Add to list'))).pop();
      await tester.pumpAndSettle();

      expect(shopping.topUps, isEmpty);
      expect(shopping.freeText, isEmpty);
      expect(_fieldText(tester), 'lim');
      expect(find.byKey(kShopAddResultsKey), findsOneWidget);
    },
  );

  testWidgets('the new-ingredient row opens the form, and the row it makes '
      'lands on the quantity sheet', (tester) async {
    final shopping = _Shopping();
    final vocab = _Vocab(const [_lime]);
    await tester.pumpWidget(_host(vocab: vocab, shopping: shopping));
    await tester.pumpAndSettle();
    await _type(tester, 'Curry leaves');

    await tester.tap(find.byKey(kShopAddNewIngredientKey));
    await tester.pumpAndSettle();
    expect(find.text('create'), findsOneWidget);
    expect(find.text('Add to list'), findsNothing);

    await tester.tap(find.text('create'));
    await tester.pumpAndSettle();
    // The quantity sheet, on the row that Save made, offering the units the
    // form admitted.
    expect(find.text('Add to list'), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, '200');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    final made = vocab.rows.singleWhere(
      (r) => r.canonicalName == 'Curry leaves',
    );
    expect(shopping.topUps.single.ingredientId, made.id);
    expect(shopping.topUps.single.quantity, 200);
    expect(_fieldText(tester), isEmpty);
  });

  testWidgets('the field is not drawn while At home? is on', (tester) async {
    await tester.pumpWidget(
      _host(vocab: _Vocab(const [_lime]), shopping: _Shopping()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kShopAddFieldKey), findsOneWidget);

    await tester.tap(find.text('At home?'));
    await tester.pumpAndSettle();
    expect(find.byKey(kShopAddFieldKey), findsNothing);

    await tester.tap(find.text('To buy'));
    await tester.pumpAndSettle();
    expect(find.byKey(kShopAddFieldKey), findsOneWidget);
  });
}
