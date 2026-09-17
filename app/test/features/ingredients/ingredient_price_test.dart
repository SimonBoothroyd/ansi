/// The **Price** group on the ingredient page, and the sheet its door opens.
///
/// Two things are pinned here and neither is decoration. The group **never
/// shows a zero** — an unpriced row says so beside its heading and offers one
/// door — and the sheet's dock **states the derivation itself** rather than a
/// preview of one, so the refusal a pack this row cannot weigh produces is the
/// same refusal that keeps Done off.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/price_sheet.dart';
import 'package:ansi/shared/unit_chip.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_price_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// A gram-basis row with a named pack — the board's own example.
const bananas = Ingredient(
  id: 'banana',
  canonicalName: 'Bananas, organic',
  defaultUnit: g,
  status: IngredientStatus.complete,
  category: 'produce',
  macros: Macros(kcal: 89, protein: 1.1, carb: 23, fat: 0.3),
  source: 'seed',
);

const bagMeasure = Measure(id: 'm-bag', label: 'bag', amount: 454);

PriceObservation price({
  String lineId = 'l1',
  int cents = 349,
  int discountCents = 0,
  double pack = 454,
  String store = "TJ's",
  String? packLabel = 'bag',
  DateTime? on,
}) => PriceObservation(
  lineId: lineId,
  receiptId: 'r-$lineId',
  cents: cents,
  discountCents: discountCents,
  packBasisAmount: pack,
  basis: MacrosBasis.perG,
  store: store,
  purchasedAt: on ?? DateTime.utc(2026, 9, 13),
  packLabel: packLabel,
);

Finder get paidField => find.descendant(
  of: find.byType(PriceEditor),
  matching: find.byType(EditableText),
);

String derivedText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(kPriceDerivedKey)).data!;

Future<void> openTheSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(kReadAddPriceKey));
  await tester.pumpAndSettle();
}

/// Types a sum into **Paid** and a pack into **for**, in that order — the two
/// fields the sheet draws, found positionally inside it.
Future<void> enterPrice(
  WidgetTester tester, {
  required String paid,
  required String pack,
}) async {
  await tester.enterText(paidField.at(0), paid);
  await tester.pump();
  await tester.enterText(paidField.at(1), pack);
  await tester.pumpAndSettle();
}

void main() {
  group('the Price group, reading', () {
    testWidgets('a row nobody has priced offers one door and no zero', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
        ),
      );
      await tester.pumpAndSettle();

      // The state is said where the group is named, not as a zero under it.
      expect(find.text('Price — none yet'), findsOneWidget);
      expect(find.text('add a price'), findsOneWidget);
      // Never a fabricated figure for a row nothing was ever paid for.
      expect(find.textContaining(r'$0'), findsNothing);
      expect(find.textContaining('0¢'), findsNothing);
      expect(find.text('LATEST'), findsNothing);
    });

    testWidgets('the latest is one line, and what came before is kept', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [
              price(),
              price(lineId: 'l2', cents: 329, on: DateTime.utc(2026, 8, 23)),
              price(
                lineId: 'l3',
                cents: 399,
                store: 'Whole Foods',
                on: DateTime.utc(2026, 8, 2),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"77¢ / 100 g · $3.49 for bag (454 g) · TJ's · 13 Sep"),
        findsOneWidget,
      );
      expect(find.text('BEFORE'), findsOneWidget);
      expect(find.text(r'72¢ / 100 g · $3.29 · bag (454 g)'), findsOneWidget);
      expect(find.text("TJ's · 23 Aug"), findsOneWidget);
      expect(find.text(r'88¢ / 100 g · $3.99 · bag (454 g)'), findsOneWidget);
      expect(find.text('Whole Foods · 2 Aug'), findsOneWidget);
      // The door stays: a price is an event, and there is always another one.
      expect(find.byKey(kReadAddPriceKey), findsOneWidget);
    });

    testWidgets('one price is a Latest with nothing before it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(prices: [price()]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('LATEST'), findsOneWidget);
      expect(find.text('BEFORE'), findsNothing);
    });

    testWidgets('a pack typed as a plain amount reads as the amount', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(prices: [price(packLabel: null)]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"77¢ / 100 g · $3.49 for 454 g · TJ's · 13 Sep"),
        findsOneWidget,
      );
    });
  });

  group('the price sheet', () {
    testWidgets('the dock states the figure a recipe will read, before Done', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(stores: const ["TJ's", 'Whole Foods']);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      // Nothing said yet: a question nobody has answered is not a mistake.
      expect(derivedText(tester), '');

      await enterPrice(tester, paid: '3.49', pack: '454');
      expect(derivedText(tester), '= 77¢ / 100 g');

      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();

      expect(prices.recorded, hasLength(1));
      expect(prices.recorded.single.cents, 349);
      expect(prices.recorded.single.packBasisAmount, 454);
      expect(
        prices.recorded.single.store,
        "TJ's",
        reason: 'the most recent store word is the one already picked',
      );
      // The sheet closed onto the page, which now states the price.
      expect(find.byType(PriceEditor), findsNothing);
    });

    testWidgets('a pack named as a measure is stored as its weight, and the '
        'word rides with it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(stores: const ["TJ's"]);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      // The row's own measure leads the chip row, exactly as on a line.
      await tester.tap(find.widgetWithText(UnitChip, 'bag').first);
      await tester.pumpAndSettle();
      await enterPrice(tester, paid: '3.49', pack: '1');
      expect(derivedText(tester), '= 77¢ / 100 g');

      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();

      expect(prices.recorded.single.packBasisAmount, 454);
      expect(prices.recorded.single.measureId, 'm-bag');
    });

    testWidgets('a pack that converts to nothing is refused, with the reason '
        'and the way out', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(stores: const ["TJ's"]);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      // A produce row earns `handful`, and a handful weighs nothing anybody
      // can price. The units a row CANNOT convert are never offered at all —
      // the chip row is the admission set — so this is the refusal a person
      // can actually reach, and the dock still carries the rest.
      await tester.tap(find.widgetWithText(UnitChip, 'handful').first);
      await tester.pumpAndSettle();
      await enterPrice(tester, paid: '3.49', pack: '1');

      expect(
        derivedText(tester),
        'an imprecise word cannot be priced — say the pack in g',
      );
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Done')).onPress,
        isNull,
        reason: 'Done is refused while the derivation is',
      );
      expect(prices.recorded, isEmpty);
    });

    testWidgets('a sum of nothing is not a price', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(stores: const ["TJ's"]),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);
      await enterPrice(tester, paid: '0', pack: '454');

      expect(derivedText(tester), 'say what you paid');
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Done')).onPress,
        isNull,
      );
    });

    testWidgets('Done waits for a store — a price is paid somewhere', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);
      await enterPrice(tester, paid: '3.49', pack: '454');

      expect(derivedText(tester), '= 77¢ / 100 g');
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Done')).onPress,
        isNull,
      );
    });

    testWidgets('the sheet says what it is replacing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [price(cents: 329, on: DateTime.utc(2026, 8, 23))],
            stores: const ["TJ's"],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      expect(find.text("latest 72¢ / 100 g · TJ's · Aug"), findsOneWidget);
    });

    testWidgets('a row nobody has priced says nothing about a latest', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      expect(find.textContaining('latest'), findsNothing);
    });

    testWidgets('the pack’s chip row is the quantity sheet’s, and it offers '
        'no measures to manage', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);

      // The row's own measures lead, then the catalog units it admits.
      expect(find.widgetWithText(UnitChip, 'bag'), findsOneWidget);
      expect(find.widgetWithText(UnitChip, 'kg'), findsOneWidget);
      // One `+` inside the sheet — the store row's. The pack is a purchase,
      // not a vocabulary edit, so the chip row draws no manage chip.
      expect(
        find.descendant(
          of: find.byType(PriceEditor),
          matching: find.byIcon(FLucideIcons.plus),
        ),
        findsOneWidget,
      );
    });
  });
}
