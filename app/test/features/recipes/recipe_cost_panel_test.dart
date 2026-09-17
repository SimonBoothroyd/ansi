import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/recipes/domain/recipe_cost.dart';
import 'package:ansi/features/recipes/presentation/recipe_cost_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Widget _host(Widget child) => ProviderlessHost(child: child);

/// A bare theme host — the cost panel is a pure widget and reads no provider.
class ProviderlessHost extends StatelessWidget {
  const ProviderlessHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

PriceObservation _price({String store = "TJ's", DateTime? on}) =>
    PriceObservation(
      lineId: 'rl-1',
      receiptId: 'r-1',
      cents: 110,
      packBasisAmount: 100,
      basis: MacrosBasis.perG,
      store: store,
      purchasedAt: on ?? DateTime.utc(2026, 9, 3),
    );

final _priced = RecipeCostSummary(
  totalCents: 1017,
  perServingCents: 254.25,
  newestPrice: DateTime.utc(2026, 9, 3),
  lineCosts: {'li-1': CostLine(cents: 1017, price: _price())},
);

void main() {
  testWidgets('a priced recipe reads three cells', (tester) async {
    await tester.pumpWidget(_host(RecipeCostPanel(summary: _priced)));

    expect(find.text(r'$2.54'), findsOneWidget);
    expect(find.text('A SERVING'), findsOneWidget);
    expect(find.text(r'$10.17'), findsOneWidget);
    expect(find.text('THE RECIPE'), findsOneWidget);
    expect(find.text('Sep'), findsOneWidget);
    expect(find.text('PRICES FROM'), findsOneWidget);
  });

  testWidgets('an unpriced line takes the cells and names itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RecipeCostPanel(
          summary: RecipeCostSummary(
            unpriced: [
              (
                lineId: 'li-2',
                name: 'Chopped tomatoes',
                reason: CostLineReason.noPrice,
                unit: null,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('A SERVING'), findsNothing);
    expect(find.text('UNPRICED'), findsOneWidget);
    expect(find.text('Chopped tomatoes · no price yet'), findsOneWidget);
    expect(find.text('1 line unpriced'), findsOneWidget);
  });

  testWidgets('the oldest line is named when its month differs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        RecipeCostPanel(
          summary: RecipeCostSummary(
            totalCents: 1017,
            perServingCents: 254.25,
            newestPrice: DateTime.utc(2026, 9, 3),
            oldest: (
              name: 'Smoked paprika',
              price: _price(
                store: 'Whole Foods',
                on: DateTime.utc(2026, 7, 11),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('OLDEST'), findsOneWidget);
    expect(find.text('Smoked paprika · Whole Foods, Jul'), findsOneWidget);
  });

  testWidgets('a real total still says what it left out by rule', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RecipeCostPanel(
          summary: RecipeCostSummary(
            totalCents: 1017,
            perServingCents: 254.25,
            notCounted: [
              (
                lineId: 'li-3',
                name: 'Parsley',
                reason: CostLineReason.imprecise,
                unit: 'handful',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('NOT COUNTED'), findsOneWidget);
    expect(find.text('Parsley · handful'), findsOneWidget);
  });

  testWidgets('no lines refuses rather than costing nothing', (tester) async {
    await tester.pumpWidget(
      _host(const RecipeCostPanel(summary: RecipeCostSummary(noLines: true))),
    );
    expect(find.text('no ingredients yet'), findsOneWidget);
    expect(find.text(r'$0.00'), findsNothing);
  });

  testWidgets('a summary that has not loaded draws nothing', (tester) async {
    await tester.pumpWidget(_host(const RecipeCostPanel(summary: null)));
    expect(find.byType(DecoratedBox), findsNothing);
  });

  group('the chip pair', () {
    testWidgets('states the reading and offers the other', (tester) async {
      var asked = <bool>[];
      await tester.pumpWidget(
        _host(
          FiguresToggle(cost: true, onChanged: (v) => asked = [...asked, v]),
        ),
      );

      expect(find.text('Macros'), findsOneWidget);
      expect(find.text('Cost'), findsOneWidget);
      expect(find.text('per serving'), findsOneWidget);

      await tester.tap(find.text('Macros'));
      await tester.pump();
      expect(asked, [false]);

      await tester.tap(find.text('Cost'));
      await tester.pump();
      expect(asked, [false, true]);
    });
  });
}
