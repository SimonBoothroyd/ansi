/// The manager on a desk (design board "Ingredients manager", the `Wide ·
/// ≥ 1024` frames): the vocabulary and the row it is reading as two panes of
/// one page, the fact sheet shared with the phone rather than copied, and the
/// phone's pushed flow untouched below the band.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_list_view.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart';
import 'package:ansi/shared/ansi_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

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

/// A vocabulary long enough that a row near its end is nowhere near the first
/// screen — which is the whole of what the reveal is for.
List<Ingredient> longVocabulary({int count = 200}) => [
  for (var i = 0; i < count; i++)
    Ingredient(
      id: 'i$i',
      canonicalName: 'Ingredient ${i.toString().padLeft(3, '0')}',
      defaultUnit: g,
      status: IngredientStatus.complete,
      category: 'pantry',
      macros: const Macros(kcal: 100, protein: 1, carb: 2, fat: 3),
      source: 'seed',
    ),
];

/// A vocabulary whose by-id watch never answers — the pane's pre-data frame,
/// held still so it can be read.
class StalledByIdRepo extends FakeIngredientRepo {
  StalledByIdRepo(super.initial);

  final _stalled = StreamController<Ingredient?>.broadcast();

  @override
  Stream<Ingredient?> watchIngredient(String id) => _stalled.stream;
}

/// Every header control the fact-sheet pane draws. Once the row is here that
/// is the `⋯` and nothing else: the page holding the two panes owns the one
/// way back, so a chevron in the pane is chrome that should not exist.
Iterable<FHeaderAction> paneHeaderActions(WidgetTester tester) =>
    tester.widgetList<FHeaderAction>(
      find.descendant(
        of: find.byType(IngredientDetailView),
        matching: find.byType(FHeaderAction),
      ),
    );

/// The `⋯` is the one control the pane is allowed. `FHeaderAction.back` builds
/// its icon from the theme through a `Builder`, so anything that is not this
/// plain ellipsis `Icon` is the chevron.
bool isEllipsis(FHeaderAction action) {
  final icon = action.icon;
  return icon is Icon && icon.icon == FLucideIcons.ellipsis;
}

/// The manager's search field. A pick restates the page it was made on, so
/// what was typed in here has to still be here afterwards.
final Finder searchField = find.descendant(
  of: find.byType(AnsiSearchField),
  matching: find.byType(TextField),
);

/// The vocabulary's own scroller, which the manager keys so its offset
/// survives the page being rebuilt under it.
final Finder vocabularyScroller = find.byKey(kVocabularyScrollKey);

double scrollOffset(WidgetTester tester) =>
    tester.widget<ListView>(vocabularyScroller).controller!.offset;

/// The index, among every vocabulary row currently built, of one sitting
/// WHOLE inside the viewport. A lazy list builds a little beyond its own
/// edges, and a tap on a row that is half off screen is not the gesture the
/// scroll-keeping claim is about.
int rowInsideViewport(WidgetTester tester) {
  final list = tester.getRect(vocabularyScroller);
  final inside = <int>[];
  for (final (i, element) in find.byType(IngredientRow).evaluate().indexed) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    if (rect.top >= list.top && rect.bottom <= list.bottom) inside.add(i);
  }
  expect(inside, isNotEmpty, reason: 'the list should have drawn some rows');
  return inside[inside.length ~/ 2];
}

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

    testWidgets('a row opens IN PLACE, and the pick IS the location: picking '
        'one moves the sheet, restates the URL and leaves the vocabulary where '
        'it was', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      late final GoRouter router;
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, curryLeaves, yeast]),
          onRouter: (r) => router = r,
        ),
      );
      await tester.pumpAndSettle();

      // `/ingredients` opens on no row, and says so where the sheet will be.
      expect(find.text('Pick a row to read what it says.'), findsOneWidget);
      expect(find.byKey(kVocabularyReadingRowKey), findsNothing);
      final depth = router.routerDelegate.currentConfiguration.matches.length;

      await tester.tap(find.text('Nutritional yeast').first);
      await tester.pumpAndSettle();

      // The address bar names the row the pane is reading, so a refresh keeps
      // it and the link is worth sending.
      expect(router.state.uri.toString(), ingredientDetailRoute('yeast'));
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
      // And nothing was STACKED either: the restate replaces, so the browser's
      // Back leaves the manager rather than walking back up every row read.
      expect(
        router.routerDelegate.currentConfiguration.matches.length,
        depth,
        reason: 'a pick must replace the location, never push a second page',
      );
    });

    testWidgets('the work queue still opens the fields, in the pane — and the '
        'URL carries the row, not the posture', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      late final GoRouter router;
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango, curryLeaves, yeast]),
          onRouter: (r) => router = r,
        ),
      );
      await tester.pumpAndSettle();

      // The band is a work queue: its door is the fields, not a fact sheet
      // that repeats what the row is short of. It opens them BESIDE the queue
      // — a vocabulary you can only fill in by leaving it is a vocabulary you
      // fill in one row per visit.
      await tester.tap(find.text('Curry leaves, fresh').first);
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(find.text('Needs fleshing out'), findsOneWidget);
      // The location names the row and stops there: which posture its pane
      // opened in is a mode, and a link that silently put somebody in a form
      // is a link nobody meant to send.
      expect(router.state.uri.toString(), ingredientDetailRoute('curry'));
      expect(
        router.state.uri.queryParameters,
        isEmpty,
        reason: 'the posture is not a place',
      );
    });

    testWidgets('and a later pick leaves the fields behind: the posture '
        'belongs to the row it was asked for', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Curry leaves, fresh').first);
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);

      await tester.tap(find.text('Nutritional yeast').first);
      await tester.pumpAndSettle();
      expect(
        find.text('CANONICAL NAME'),
        findsNothing,
        reason: 'a row opened from the vocabulary opens as a row, to be read',
      );
      expect(find.text(_completeStrip), findsOneWidget);
    });

    testWidgets('a pick restates the page it was made on: the search field '
        'keeps what was typed into it', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      await tester.enterText(searchField, 'yeast');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nutritional yeast').first);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(searchField).controller!.text,
        'yeast',
        reason:
            'the two locations are one page: a pick that emptied the field '
            'would put the whole vocabulary back under a reader who had '
            'narrowed it',
      );
      expect(find.byKey(kVocabularyReadingRowKey), findsOneWidget);
    });

    testWidgets('the pane never flashes a titled header or a back chevron '
        'while the row it was handed is still on its way', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      // An empty vocabulary AND a by-id watch that never answers: the pane
      // has nothing to draw from either side, which is the frame the chrome
      // used to appear in.
      await tester.pumpWidget(
        host(StalledByIdRepo(const []), at: ingredientDetailRoute('mango')),
      );
      await tester.pump();

      expect(
        find.text('Ingredient'),
        findsNothing,
        reason: 'the pane is not a page and has no title of its own',
      );
      expect(
        paneHeaderActions(tester),
        isEmpty,
        reason:
            'the page holding the two panes owns the one way back; a chevron '
            'here is chrome that exists for a frame and then goes',
      );
      // The list beside it still draws the page's own one way back.
      expect(find.text('Ingredients'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
    });

    testWidgets('and it does not draw one on the way in from a pick either — '
        'the arrival the owner actually reported', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(StalledByIdRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nutritional yeast').first);
      // `pump`, not `pumpAndSettle`: the pane is keyed per row, so every pick
      // opens a fresh watch and pays a frame with no row in it. That frame is
      // the one the owner saw `Ingredient ‹` in.
      for (var i = 0; i < 4; i++) {
        await tester.pump();
        expect(find.text('Ingredient'), findsNothing);
        expect(paneHeaderActions(tester).where((a) => !isEllipsis(a)), isEmpty);
      }
      // The list is still beside it, still itself, with the row it was asked
      // for lit — the pane waiting is not the page reloading. `findsWidgets`,
      // not `findsOneWidget`: this harness stacks the manager as the only
      // page it has, so nothing underneath keeps the restate's page key and
      // the outgoing list is still on its way out mid-transition.
      expect(find.text('Needs fleshing out'), findsWidgets);
      expect(find.byKey(kVocabularyReadingRowKey), findsOneWidget);
    });

    testWidgets('and once the row is here the pane draws the ⋯ and nothing '
        'else', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nutritional yeast').first);
      await tester.pumpAndSettle();

      expect(find.text(_completeStrip), findsOneWidget);
      expect(paneHeaderActions(tester).where((a) => !isEllipsis(a)), isEmpty);
    });

    testWidgets('a deep link far down a long vocabulary scrolls the lit row '
        'into view', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(longVocabulary()),
          at: ingredientDetailRoute('i180'),
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.getRect(vocabularyScroller);
      final row = tester.getRect(find.byKey(kVocabularyReadingRowKey));
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));
      expect(
        find.descendant(
          of: find.byKey(kVocabularyReadingRowKey),
          matching: find.text('Ingredient 180'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the list keeps its scroll across the restate, and the row '
        'under the finger does not move', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(host(FakeIngredientRepo(longVocabulary())));
      await tester.pumpAndSettle();

      await tester.drag(vocabularyScroller, const Offset(0, -3000));
      await tester.pumpAndSettle();
      final before = scrollOffset(tester);
      expect(before, greaterThan(0));

      final middle = rowInsideViewport(tester);
      final tapped = tester.getRect(find.byType(IngredientRow).at(middle));
      await tester.tap(find.byType(IngredientRow).at(middle));
      await tester.pumpAndSettle();

      expect(find.byKey(kVocabularyReadingRowKey), findsOneWidget);
      expect(
        scrollOffset(tester),
        closeTo(before, 1),
        reason:
            '`/ingredients` and `/ingredients/:id` are two routes, so the '
            'restate rebuilds the page — the vocabulary must still be where '
            'the reader left it',
      );
      expect(
        tester.getRect(find.byKey(kVocabularyReadingRowKey)).top,
        closeTo(tapped.top, 1),
      );
    });

    testWidgets('a pick fills the pane on its FIRST frame, off the vocabulary '
        'the list beside it is already drawing', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(StalledByIdRepo(const [mango, curryLeaves, yeast])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nutritional yeast').first);
      // One `pump`, and the by-id watch of this repository never answers: what
      // is on screen can only have come from the vocabulary. The two queries
      // have the same projection, so that copy IS the row.
      await tester.pump();

      expect(find.text(_completeStrip), findsOneWidget);
      expect(
        find.text('…'),
        findsNothing,
        reason: 'the row was in memory; there was nothing to wait for',
      );
      expect(
        find.descendant(
          of: find.byType(IngredientDetailView),
          matching: find.text('Nutritional yeast'),
        ),
        findsWidgets,
      );
    });

    testWidgets('but a cold deep link, before the vocabulary is here, still '
        'says it is waiting', (tester) async {
      filterForuiSemanticsAssertions();
      deskWidth(tester);
      await tester.pumpWidget(
        host(StalledByIdRepo(const []), at: ingredientDetailRoute('mango')),
      );
      await tester.pump();

      expect(find.text('…'), findsOneWidget);
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
