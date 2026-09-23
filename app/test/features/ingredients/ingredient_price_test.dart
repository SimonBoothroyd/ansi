/// The **Price** group on the ingredient page, and the sheet its door opens.
///
/// Three things are pinned here and none is decoration. The group **never
/// shows a zero** — an unpriced row says so beside its heading and offers one
/// door. The sheet's dock **states the derivation itself** rather than a
/// preview of one, so the refusal a pack this row cannot weigh produces is the
/// same refusal that keeps Done off. And what the sheet writes is the row's
/// **base price**, never a receipt: a price paid is opened on its receipt, and
/// the base price is its own entry beside it.
///
/// The last group asks the same questions of the **editing** posture, which
/// draws the same widget: the prices are there, each one is the same tap, and
/// what the sheet writes neither rides the form's Save nor is doubled by it.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/core/words.dart';
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

/// A price paid on a receipt. The sheet never writes one.
PriceObservation price({
  String lineId = 'l1',
  int cents = 349,
  int count = 1,
  int discountCents = 0,
  double pack = 454,
  String store = "TJ's",
  String? packLabel = 'bag',
  double? packAmount = 1,
  Unit? packUnit,
  String? measureId = 'm-bag',
  DateTime? on,
}) => PriceObservation(
  lineId: lineId,
  receiptId: 'r-$lineId',
  cents: cents,
  count: count,
  discountCents: discountCents,
  packBasisAmount: pack,
  basis: MacrosBasis.perG,
  store: store,
  purchasedAt: on ?? DateTime.utc(2026, 9, 13),
  packAmount: packAmount,
  packUnit: packUnit,
  packLabel: packLabel,
  measureId: measureId,
);

/// The row's own base price: a bag for $3.49, set on 13 Sep.
BasePrice basePrice({
  int cents = 349,
  double pack = 454,
  double? packAmount = 1,
  Unit? packUnit,
  String? measureId = 'm-bag',
  String? packLabel = 'bag',
  String? store,
}) => BasePrice(
  ingredientId: 'banana',
  cents: cents,
  packBasisAmount: pack,
  basis: MacrosBasis.perG,
  setAt: DateTime.utc(2026, 9, 13),
  store: store,
  packAmount: packAmount,
  packUnit: packUnit,
  measureId: measureId,
  packLabel: packLabel,
);

Finder get paidField => find.descendant(
  of: find.byType(PriceEditor),
  matching: find.byType(EditableText),
);

String derivedText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(kPriceDerivedKey)).data!;

Future<void> openTheSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(kAddPriceKey));
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
      expect(find.text('set a base price'), findsOneWidget);
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
      // The door to the base price stays while the row has none: receipts are
      // not the only way a row is priced.
      expect(find.byKey(kAddPriceKey), findsOneWidget);
      expect(find.text('BASE'), findsNothing);
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

    testWidgets('a counted receipt line says how many it bought', (
      tester,
    ) async {
      // The owner's tofu: eight blocks for $23.92. The pack is what ONE
      // block is, so the restated purchase has to say how many or the
      // figure in front of it reads back wrong.
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [
              price(
                cents: 2392,
                count: 8,
                packLabel: null,
                measureId: null,
                packAmount: 454,
                packUnit: g,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"66¢ / 100 g · $23.92 for 8 × 454 g · TJ's · 13 Sep"),
        findsOneWidget,
      );
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
          prices: FakePriceRepo(
            prices: [
              price(
                packLabel: null,
                measureId: null,
                packAmount: 454,
                packUnit: g,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"77¢ / 100 g · $3.49 for 454 g · TJ's · 13 Sep"),
        findsOneWidget,
      );
    });

    testWidgets('a pound reads back as a pound, and still prices per 100 g', (
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
              price(
                pack: 453.59237,
                packLabel: null,
                measureId: null,
                packUnit: lb,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // What was bought was a pound. What it is worth is per 100 g, because
      // that is the row's own dimension.
      expect(
        find.text(r"77¢ / 100 g · $3.49 for 1 lb · TJ's · 13 Sep"),
        findsOneWidget,
      );
    });

    testWidgets('two of a named pack count, and one does not', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [price(cents: 698, pack: 908, packAmount: 2)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"77¢ / 100 g · $6.98 for 2 bag (908 g) · TJ's · 13 Sep"),
        findsOneWidget,
      );
    });

    testWidgets('a pack whose word already says its size says it once '
        '(owner)', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [price(cents: 129, pack: 411, packLabel: 'can (14.5 oz)')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Not `can (14.5 oz) (411 g)`: the word IS the size, in the unit the
      // shelf prints it in.
      expect(
        find.text(r"31¢ / 100 g · $1.29 for can (14.5 oz) · TJ's · 13 Sep"),
        findsOneWidget,
      );
    });

    testWidgets('a row written before the ledger kept the words reads as the '
        'weight it stored', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(
            prices: [price(packLabel: null, measureId: null, packAmount: null)],
          ),
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
      final prices = FakePriceRepo();
      // No measure on the row, so the chip row opens on its basis unit and
      // the pack below is read in grams.
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
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

      // One base price on the row — never a receipt.
      expect(prices.setCalls, hasLength(1));
      expect(prices.setCalls.single.ingredientId, 'banana');
      expect(prices.setCalls.single.cents, 349);
      expect(prices.setCalls.single.packBasisAmount, 454);
      expect(prices.setCalls.single.packAmount, 454);
      expect(prices.setCalls.single.packUnitId, 'g');
      // The sheet closed onto the page, which now states the base price as
      // what a recipe reads.
      expect(find.byType(PriceEditor), findsNothing);
      expect(find.text('BASE'), findsOneWidget);
      expect(find.text('what a recipe reads'), findsOneWidget);
      expect(find.text('Price — none yet'), findsNothing);
    });

    testWidgets('a new price opens on the chip the row leads with, not on its '
        'default unit (owner)', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo();
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

      // No chip tapped: the pack is read as ONE bag because that is the chip
      // the sheet opened on.
      await enterPrice(tester, paid: '3.49', pack: '1');
      expect(derivedText(tester), '= 77¢ / 100 g');

      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();
      expect(prices.setCalls.single.packBasisAmount, 454);
      expect(prices.setCalls.single.measureId, 'm-bag');
    });

    testWidgets('a pack named as a measure is stored as its weight, and the '
        'word rides with it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo();
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

      expect(prices.setCalls.single.packBasisAmount, 454);
      expect(prices.setCalls.single.measureId, 'm-bag');
    });

    testWidgets('a pack that converts to nothing is refused, with the reason '
        'and the way out', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo();
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
      expect(prices.setCalls, isEmpty);
    });

    testWidgets('a sum of nothing is not a price', (tester) async {
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
      await enterPrice(tester, paid: '0', pack: '454');

      expect(derivedText(tester), 'say what you paid');
      expect(
        tester.widget<FButton>(find.widgetWithText(FButton, 'Done')).onPress,
        isNull,
      );
    });

    testWidgets('the store is optional — Done opens without one', (
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
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);
      await enterPrice(tester, paid: '3.49', pack: '454');

      // The receipts' own store words, and nothing picked for you.
      expect(find.text('AT'), findsOneWidget);
      expect(find.widgetWithText(UnitChip, "TJ's"), findsOneWidget);
      expect(find.widgetWithText(UnitChip, 'Whole Foods'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();
      expect(prices.setCalls.single.store, isNull);
    });

    testWidgets('a picked store is written with the base price, and a second '
        'tap takes it off', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(stores: const ["TJ's", 'Whole Foods']);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
        ),
      );
      await tester.pumpAndSettle();
      await openTheSheet(tester);
      await enterPrice(tester, paid: '3.49', pack: '454');

      await tester.tap(find.widgetWithText(UnitChip, "TJ's"));
      await tester.pump();
      await tester.tap(find.widgetWithText(UnitChip, 'Whole Foods'));
      await tester.pump();
      await tester.tap(find.widgetWithText(UnitChip, 'Whole Foods'));
      await tester.pump();
      await tester.tap(find.widgetWithText(UnitChip, "TJ's"));
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();

      expect(prices.setCalls.single.store, "TJ's");
      // The page names the shop, as a receipt price does.
      expect(
        find.text(
          r"77¢ / 100 g · $3.49 for 454 g · TJ's · set "
          '${formatDayMonth(prices.base!.setAt)}',
        ),
        findsOneWidget,
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

  group('a price already stored', () {
    testWidgets('the Base line opens the sheet on the base price, as entered', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(base: basePrice()),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r'77¢ / 100 g · $3.49 for bag (454 g) · set 13 Sep'),
        findsOneWidget,
      );
      // Its own door is the line itself, so the add door is gone.
      expect(find.byKey(kAddPriceKey), findsNothing);

      await tester.tap(find.byKey(kBasePriceKey));
      await tester.pumpAndSettle();

      expect(find.text(r'editing $3.49 · set 13 Sep'), findsOneWidget);
      // The answers are filled in as they were given: the sum, the count, and
      // the chip the pack was tapped on.
      expect(
        tester.widget<EditableText>(paidField.at(0)).controller.text,
        '3.49',
      );
      expect(tester.widget<EditableText>(paidField.at(1)).controller.text, '1');
      expect(derivedText(tester), '= 77¢ / 100 g');
      expect(find.byKey(kPriceDeleteKey), findsOneWidget);
    });

    testWidgets('a stored store is on the Base line, and the sheet reopens on '
        'it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(base: basePrice(store: "TJ's"));
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(r"77¢ / 100 g · $3.49 for bag (454 g) · TJ's · set 13 Sep"),
        findsOneWidget,
      );
      await tester.tap(find.byKey(kBasePriceKey));
      await tester.pumpAndSettle();
      expect(find.text(r"editing $3.49 · TJ's · set 13 Sep"), findsOneWidget);
      // Offered even though no receipt names it, so it can be seen and
      // cleared.
      expect(find.widgetWithText(UnitChip, "TJ's"), findsOneWidget);

      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();
      expect(prices.setCalls.single.store, "TJ's");
    });

    testWidgets('Done replaces the base price, and writes nothing else', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(
        base: basePrice(
          measureId: null,
          packLabel: null,
          packUnit: g,
          packAmount: 454,
        ),
      );
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kBasePriceKey));
      await tester.pumpAndSettle();

      await tester.enterText(paidField.at(0), '3.99');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();

      expect(prices.setCalls, hasLength(1));
      expect(prices.setCalls.single.cents, 399);
      expect(prices.setCalls.single.packAmount, 454);
      expect(prices.setCalls.single.packUnitId, 'g');
      expect(prices.rows, isEmpty, reason: 'no receipt');
      expect(find.byType(PriceEditor), findsNothing);
    });

    testWidgets('Delete asks first, and a no changes nothing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo(base: basePrice());
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: prices,
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(kBasePriceKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kPriceDeleteKey));
      await tester.pumpAndSettle();
      expect(find.text('Delete the base price?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(FDialog),
          matching: find.widgetWithText(FButton, 'Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(prices.cleared, isEmpty, reason: 'silence is not consent');
      expect(find.byType(PriceEditor), findsOneWidget);
    });

    testWidgets(
      'a confirmed Delete takes the base price and closes the sheet',
      (tester) async {
        filterForuiSemanticsAssertions();
        tallScreen(tester);
        final prices = FakePriceRepo(base: basePrice());
        await tester.pumpWidget(
          host(
            FakeIngredientRepo(const [bananas]),
            at: ingredientDetailRoute('banana'),
            prices: prices,
            measures: FakeMeasureRepo(const [bagMeasure]),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(kBasePriceKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(kPriceDeleteKey));
        await tester.pumpAndSettle();

        // The sheet's own Delete is keyed; the dialog's is the other one.
        await tester.tap(find.widgetWithText(FButton, 'Delete').last);
        await tester.pumpAndSettle();

        expect(prices.cleared, ['banana']);
        expect(find.byType(PriceEditor), findsNothing);
        // The group is back to the state a row nobody has priced wears — never
        // a zero standing where the price was.
        expect(find.text('Price — none yet'), findsOneWidget);
      },
    );

    testWidgets('a price paid opens its receipt, never the sheet', (
      tester,
    ) async {
      // One line, one editor. A line is corrected on its own receipt — where
      // the paper still has to add up — and the sheet holds the base price
      // only.
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(prices: [price()]),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(kLatestPriceKey));
      await tester.pumpAndSettle();

      expect(find.text('receipt r-l1'), findsOneWidget);
      expect(find.byType(PriceEditor), findsNothing);
    });

    testWidgets('a row under Before opens its own receipt', (tester) async {
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
            ],
          ),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(r'72¢ / 100 g · $3.29 · bag (454 g)'));
      await tester.pumpAndSettle();

      expect(find.text('receipt r-l2'), findsOneWidget);
    });

    testWidgets('beside a price paid, the base price says it stands in', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(prices: [price(cents: 329)], base: basePrice()),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      // The receipt is what a recipe reads; the base price is its own entry,
      // named as what is read when no receipt prices the row.
      expect(find.text('LATEST'), findsOneWidget);
      expect(find.text('what a recipe reads'), findsOneWidget);
      expect(find.text('BASE'), findsOneWidget);
      expect(find.text('read when no receipt prices it'), findsOneWidget);
    });

    testWidgets('a new base price beside a receipt offers no Delete, and says '
        'what was last paid', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: ingredientDetailRoute('banana'),
          prices: FakePriceRepo(prices: [price()]),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      await openTheSheet(tester);
      expect(find.byKey(kPriceDeleteKey), findsNothing);
      expect(find.textContaining('editing'), findsNothing);
      expect(find.text("latest 77¢ / 100 g · TJ's · Sep"), findsOneWidget);
    });
  });

  group('the Price group, editing', () {
    testWidgets('the editor draws the same group, and says the sheet does '
        'not wait for Save', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [bananas]), at: editRoute('banana')),
      );
      await tester.pumpAndSettle();

      // The state is said where the group is named here too, and never as a
      // zero the form could then be read as holding.
      expect(find.text('Price — none yet'), findsOneWidget);
      expect(find.byKey(kAddPriceKey), findsOneWidget);
      expect(
        find.textContaining('a price is written as you enter it'),
        findsOneWidget,
        reason:
            'the dock must not be read as covering a section it does not '
            'own',
      );
      expect(find.byKey(kFormSaveKey), findsOneWidget);
    });

    testWidgets('every stored price is on the editor, and the base price '
        'opens the sheet on itself', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: editRoute('banana'),
          prices: FakePriceRepo(
            prices: [
              price(),
              price(lineId: 'l2', cents: 329, on: DateTime.utc(2026, 8, 23)),
            ],
            base: basePrice(cents: 299),
          ),
          measures: FakeMeasureRepo(const [bagMeasure]),
        ),
      );
      await tester.pumpAndSettle();

      // The fact sheet's own lines, word for word — one widget, two hosts.
      expect(
        find.text(r"77¢ / 100 g · $3.49 for bag (454 g) · TJ's · 13 Sep"),
        findsOneWidget,
      );
      expect(find.text('BEFORE'), findsOneWidget);

      await tester.tap(find.byKey(kBasePriceKey));
      await tester.pumpAndSettle();
      expect(find.text(r'editing $2.99 · set 13 Sep'), findsOneWidget);
    });

    testWidgets('a price entered here is written at once, and the form’s Save '
        'neither loses nor doubles it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final prices = FakePriceRepo();
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [bananas]),
          at: editRoute('banana'),
          prices: prices,
        ),
      );
      await tester.pumpAndSettle();

      await openTheSheet(tester);
      // The door opens on nothing: there is no base price to take back yet.
      expect(find.byKey(kPriceDeleteKey), findsNothing);
      await enterPrice(tester, paid: '3.49', pack: '454');
      await tester.tap(find.widgetWithText(FButton, 'Done'));
      await tester.pumpAndSettle();
      expect(prices.setCalls, hasLength(1));

      // Save lands the FIELDS and puts the form down. The base price is not
      // the draft's to hold, so nothing about the price moves.
      await saveForm(tester);
      expect(prices.setCalls, hasLength(1));
      expect(find.text('BASE'), findsOneWidget);
    });

    testWidgets('a row that does not exist yet has nothing to hang a price '
        'on, and is not asked for one', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const []), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Price — after the first save'), findsOneWidget);
      expect(
        find.textContaining('this one does not exist yet'),
        findsOneWidget,
      );
      // No door onto a sheet that would have no row to write against.
      expect(find.byKey(kAddPriceKey), findsNothing);
      // And the gate is the one it always was: the dock is waiting on the
      // fields a row is made of, never on a price.
      expect(saveButton(tester).onPress, isNull);
      expect(
        find.text('A name is the one field an ingredient can’t go without.'),
        findsOneWidget,
      );
    });
  });
}
