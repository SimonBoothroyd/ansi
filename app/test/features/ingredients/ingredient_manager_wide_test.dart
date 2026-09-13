/// The manager on a desk (design board "Ingredients manager", the `Wide ·
/// ≥ 1024` frames): the vocabulary and the row it is reading as two panes of
/// one page, the fact sheet shared with the phone rather than copied, and the
/// phone's pushed flow untouched below the band.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// A desk-width window — the band the two panes belong to. Tall, because the
/// fact sheet is a long read and a short viewport builds only its top.
void deskWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _completeStrip = 'Complete — counts in conversions and macro totals.';

void main() {
  group('the manager at a desk', () {
    testWidgets('a deep link to a row opens the two panes with that row lit, '
        'and the sheet is the one the phone pushes', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, curryLeaves, yeast]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      // The list pane keeps everything the phone's list has: the field and the
      // work queue above the vocabulary, in its shop-walk sections.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('1 stub'), findsOneWidget);
      expect(find.text('Produce · 2'), findsOneWidget);
      expect(find.text('Pantry · 1'), findsOneWidget);
      expect(
        find.textContaining('add an ingredient'),
        findsOneWidget,
        reason: 'the add door stays at the pane’s foot',
      );

      // The row the sheet is on is lit, in the list, where it was tapped.
      expect(find.byKey(kVocabularyReadingRowKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kVocabularyReadingRowKey),
          matching: find.text('Mango'),
        ),
        findsOneWidget,
      );

      // …and the sheet is the shared fact sheet, beside the list rather than
      // over it. One of them: the manager does not draw a second copy.
      expect(find.byType(IngredientDetailView), findsOneWidget);
      expect(find.text(_completeStrip), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(IngredientDetailView)).dx,
        greaterThan(tester.getTopLeft(find.byKey(kVocabularyReadingRowKey)).dx),
      );
      // The sheet caps at a page's measure rather than running to the window's
      // edge — a row reads at a measure, not at a desk's width.
      expect(
        tester.getSize(find.byType(IngredientDetailView)).width,
        lessThanOrEqualTo(kFactSheetPaneWidth),
      );
    });

    testWidgets('a row opens IN PLACE: picking one moves the sheet and leaves '
        'the vocabulary where it was', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      // `/ingredients` opens on no row, and says so where the sheet will be.
      expect(find.text('Pick a row to read what it says.'), findsOneWidget);
      expect(find.byKey(kVocabularyReadingRowKey), findsNothing);

      await tester.tap(find.text('Nutritional yeast').first);
      await tester.pumpAndSettle();

      expect(find.text(_completeStrip), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(kVocabularyReadingRowKey),
          matching: find.text('Nutritional yeast'),
        ),
        findsOneWidget,
      );
      // Nothing was pushed over the list — it is still there, still itself.
      expect(find.text('Needs fleshing out'), findsOneWidget);
      expect(find.text('Produce · 2'), findsOneWidget);
    });

    testWidgets('the work queue still opens the fields, in the pane', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      // The band is a work queue: its door is the fields, not a fact sheet
      // that repeats what the row is short of.
      await tester.tap(find.text('Curry leaves, fresh').first);
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(find.text('Needs fleshing out'), findsOneWidget);
    });

    testWidgets('below expanded a row is still a page pushed over the list', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, curryLeaves, yeast]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_completeStrip), findsOneWidget);
      expect(
        find.text('Needs fleshing out'),
        findsNothing,
        reason: 'the phone flow is the page, not a pane beside a list',
      );
    });
  });
}
