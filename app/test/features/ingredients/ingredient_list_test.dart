/// The vocabulary list (design board "Ingredients manager · v1", frame a):
/// what a row says about itself, how the stub band reads, and the doors out
/// of the list.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

void main() {
  group('the vocabulary list — frame (a)', () {
    testWidgets('the stub band sits on top of the whole vocabulary, and its '
        'hint reads NEEDS MACROS (D5 overruled "needs density · macros")', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('1 stub'), findsOneWidget);
      expect(find.text('needs macros · usda prefilled'), findsOneWidget);
      // …and the full vocabulary is below it, not replaced by it.
      expect(find.text('All ingredients · 3'), findsOneWidget);
      expect(find.text('Mango'), findsWidgets);
      expect(find.text('Nutritional yeast'), findsWidgets);
    });

    testWidgets('J4: the list comes back from the detail route still showing '
        'the band and the header — a round-trip is not a search', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango, curryLeaves, yeast]);
      await tester.pumpWidget(host(repo));
      await tester.pumpAndSettle();

      // Initial render is fine — this is the state we must get back to.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);

      // Push the detail, rename + save, pop back.
      await tester.tap(find.text('Mango').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Mango, ripe');
      await tester.pump();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      expect((await repo.byId('mango'))!.canonicalName, 'Mango, ripe');

      // Save is the way back now — it ends the page, which is what the
      // picker that pushes this form has always awaited.
      await tester.pumpAndSettle();

      // The user typed nothing into search, so the list must not be in its
      // search-results branch.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);
      expect(find.text('Mango, ripe'), findsWidgets);
    });

    testWidgets('J4: typing still collapses the list into results, and '
        'clearing the field brings the band and the header straight back', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();
      expect(find.text('All ingredients · 3'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'mang');
      await tester.pumpAndSettle();
      // A search is a search: the band and the header collapse into results.
      expect(find.text('Needs fleshing out'), findsNothing);
      expect(find.text('All ingredients · 3'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      // An empty field is the whole vocabulary — the branch follows the text
      // the user can actually see, never a query that outlived it.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('All ingredients · 3'), findsOneWidget);
    });

    testWidgets('rows are the 7.7 picker rows: honest hints, no zeros for a '
        'stub, and a missing density named as an advisory', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      expect(find.text('produce · has density · 3 measures'), findsOneWidget);
      expect(
        find.text('pantry · no density — volume units locked'),
        findsOneWidget,
      );
      // The stub carries both: the advisory (no density) and the blocker
      // (needs macros). D5 keeps them distinct.
      expect(
        find.text(
          'produce · no density — volume units locked · needs macros — '
          'no zeros shown',
        ),
        findsOneWidget,
      );
      // A stub shows no macro line at all — never a row of zeros. Only the
      // two complete rows carry one.
      expect(find.textContaining('kcal ·'), findsNWidgets(2));
      expect(find.textContaining('60 kcal · 1P 0F 15C'), findsOneWidget);
    });

    testWidgets('G4: a prefilled-but-unconfirmed stub hints NEEDS COMPLETING — '
        'the hint stops asking for what the row already has', (tester) async {
      filterForuiSemanticsAssertions();
      // Same row, one difference: the prefill has landed its panel.
      final prefilled = curryLeaves.copyWith(macros: usdaAnswer.macros);
      await tester.pumpWidget(
        host(FakeIngredientRepo([mango, prefilled, blackRice])),
      );
      await tester.pumpAndSettle();

      // D5's language: the numbers are there, a human standing behind them
      // is what is missing.
      expect(find.text('needs completing · usda prefilled'), findsOneWidget);
      // …while a truly bare stub still says the literal truth.
      expect(find.text('needs macros'), findsOneWidget);
      expect(find.text('2 stubs'), findsOneWidget);
    });

    testWidgets('no band at all when nothing is a stub', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(host(FakeIngredientRepo(const [mango])));
      await tester.pumpAndSettle();
      expect(find.text('Needs fleshing out'), findsNothing);
      expect(find.text('All ingredients · 1'), findsOneWidget);
    });

    testWidgets('tapping a row opens its flesh-out form', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mango').last);
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);
    });
  });
}
