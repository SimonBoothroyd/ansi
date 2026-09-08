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
  group('the vocabulary list', () {
    testWidgets('the stub band sits on top of the whole vocabulary, and its '
        'hint reads NEEDS MACROS, not "needs density · '
        'macros"', (tester) async {
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

    testWidgets('the list comes back from the detail route still showing the '
        'band and the header — a round-trip is not a search', (tester) async {
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

    testWidgets('typing still collapses the list into results, and clearing '
        'the field brings the band and the header straight '
        'back', (tester) async {
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

    testWidgets('rows are the picker rows: honest hints, no zeros for a stub, '
        'and a missing density named as an advisory', (tester) async {
      filterForuiSemanticsAssertions();
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      // The join reaching the screen, once. Which clauses a row earns is a
      // table in ingredient_row_hints_test.dart — this is the stub, carrying
      // both the advisory (no density) and the blocker (needs macros), which
      // stay distinct sentences.
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

    testWidgets('a prefilled-but-unconfirmed stub hints NEEDS COMPLETING — the '
        'hint stops asking for what the row already has', (tester) async {
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

  // --- The source, on the row (plan 0040 front A) ----------------------------

  group('the USDA food behind a filled row', () {
    testWidgets('a filled row names it; an edited one leads with EDITED; a '
        'manual row and a stamp with no name say nothing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, chex, unnamedFill])),
      );
      await tester.pumpAndSettle();

      // A-D1: the food is named in the scan, not one opened row at a time.
      expect(find.text('usda · Curry leaves, raw'), findsOneWidget);
      // B-D4: `edited ·` leads, so the scan also shows which rows are no
      // longer the machine's.
      expect(
        find.text(
          'edited · usda · Cereals ready-to-eat, GENERAL MILLS, Corn CHEX',
        ),
        findsOneWidget,
      );
      // A manual/seed row shows exactly what it always showed.
      expect(find.textContaining('usda ·'), findsNWidgets(2));
      // A-D4: a pre-0027 stamp with no label invents nothing.
      expect(find.text('Tinned Tomatoes'), findsOneWidget);
      expect(find.textContaining('usda_fdc'), findsNothing);
    });

    testWidgets('a SCANNED row names its pack the same way, and the band tags '
        'it barcode — no code is printed anywhere', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, scannedSpread])),
      );
      await tester.pumpAndSettle();

      expect(find.text('barcode · Ferrero Nutella'), findsOneWidget);
      expect(find.text('needs macros · barcode prefilled'), findsOneWidget);
      expect(find.textContaining('3017620422003'), findsNothing);
    });

    testWidgets('search results carry it too — the manager’s rows are one '
        'row, whichever branch drew them', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, chex])),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'chex');
      await tester.pumpAndSettle();
      expect(find.text('All ingredients · 3'), findsNothing);
      expect(
        find.text(
          'edited · usda · Cereals ready-to-eat, GENERAL MILLS, Corn CHEX',
        ),
        findsOneWidget,
      );
    });
  });
}
