/// The editor opened by a link that names its fix: `?focus=makes` lands on the
/// MAKES field with the caret in it, and `?line={id}` on that line's open card.
/// The Cook tab's gap buttons are the links (plan 0057, F5).
///
/// A target the recipe no longer has opens the editor as a bare link does.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_landing.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/pump_app.dart';

/// Thirty lines, so the last of them is screens below the header on a phone.
final _recipe = Recipe(
  id: '1',
  title: 'Long Stew',
  servingsBase: 4,
  yieldQty: 1.5,
  yieldUnit: l,
  groups: [
    IngredientGroup(
      id: 'g1',
      items: [
        for (var i = 1; i <= 30; i++)
          LineItem(
            id: 'l$i',
            ingredientId: 'ing-$i',
            ingredientName: 'Thing $i',
            unit: g,
            quantity: i * 10,
          ),
      ],
    ),
  ],
);

/// The editor at [location], built as the app's router builds it.
Future<void> _open(
  WidgetTester tester,
  String location, {
  // A phone's one column (below the wide band), wide enough for the test
  // font's squares in the foot doors.
  Size surface = const Size(800, 800),
}) async {
  filterForuiSemanticsAssertions();
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    routedHost(
      initial: location,
      overrides: [
        recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(_recipe)),
        ingredientRepositoryProvider.overrideWithValue(
          const FakeIngredientRepo(),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ],
      routes: {
        '/recipes/:id/edit': (_, state) => RecipeEditorView(
          recipeId: state.pathParameters['id'],
          landing: EditorLanding.fromQuery(state.uri.queryParameters),
        ),
      },
    ),
  );
  await tester.pumpAndSettle();
}

/// Whether [finder]'s widget is wholly on screen.
bool _onScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 && rect.bottom <= screen.height;
}

/// The editor's own scroll offset.
double _offset(WidgetTester tester) => tester
    .state<ScrollableState>(find.byType(Scrollable).first)
    .position
    .pixels;

/// The open card's chevron: one per open line.
Finder _openCards() => find.bySemanticsLabel('Close the line');

EditableText _makesAmount(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(const ValueKey('yield-1')),
    matching: find.byType(EditableText),
  ),
);

void main() {
  group('the link', () {
    test('names MAKES, a line, or nothing', () {
      expect(EditorLanding.fromQuery(const {}), isNull);
      expect(
        EditorLanding.fromQuery(const {'focus': 'makes'}),
        const LandOnMakes(),
      );
      // A field the editor does not know lands nowhere.
      expect(EditorLanding.fromQuery(const {'focus': 'serves'}), isNull);
      expect(
        EditorLanding.fromQuery(const {'line': 'l7'}),
        const LandOnLine('l7'),
      );
      expect(EditorLanding.fromQuery(const {'line': ' '}), isNull);
      // The narrower ask wins.
      expect(
        EditorLanding.fromQuery(const {'line': 'l7', 'focus': 'makes'}),
        const LandOnLine('l7'),
      );
    });

    test('the location reads back as the landing it was built from', () {
      expect(recipeEditorLocation('r1'), '/recipes/r1/edit');
      expect(
        recipeEditorLocation('r1', landing: const LandOnMakes()),
        '/recipes/r1/edit?focus=makes',
      );
      for (final landing in const [
        LandOnMakes(),
        LandOnLine('l7'),
        LandOnLine('a b&c'),
      ]) {
        final uri = Uri.parse(recipeEditorLocation('r1', landing: landing));
        expect(uri.path, '/recipes/r1/edit');
        expect(EditorLanding.fromQuery(uri.queryParameters), landing);
      }
    });

    test("structural: the router's editor route reads the landing off the "
        'query', () {
      final source = File('lib/core/router/app_router.dart').readAsStringSync();
      final start = source.indexOf("path: '/recipes/:id/edit',");
      expect(start, isNot(-1), reason: 'the editor route should exist');
      // The editor route is the last; its builder ends within a screenful.
      final route = source.substring(
        start,
        math.min(start + 1200, source.length),
      );
      expect(
        route,
        contains('landing: EditorLanding.fromQuery('),
        reason: 'the route must hand ?focus= and ?line= to the editor',
      );
      expect(route, contains('state.uri.queryParameters'));
    });
  });

  testWidgets('focus=makes lands on MAKES with the caret in its first amount', (
    tester,
  ) async {
    await _open(tester, '/recipes/1/edit?focus=makes');

    expect(tester.takeException(), isNull);
    expect(_onScreen(tester, find.text('MAKES')), isTrue);
    expect(_makesAmount(tester).focusNode.hasFocus, isTrue);
    expect(_openCards(), findsNothing);
  });

  testWidgets('a bare link opens at the top with nothing focused', (
    tester,
  ) async {
    await _open(tester, '/recipes/1/edit');

    expect(_offset(tester), 0);
    expect(_makesAmount(tester).focusNode.hasFocus, isFalse);
    expect(_openCards(), findsNothing);
  });

  testWidgets('line= opens that line’s card, scrolled into view', (
    tester,
  ) async {
    await _open(tester, '/recipes/1/edit?line=l28');

    expect(tester.takeException(), isNull);
    // One card open, and it is the line asked for.
    expect(_openCards(), findsOneWidget);
    expect(find.text('Thing 28'), findsOneWidget);
    expect(_onScreen(tester, _openCards()), isTrue);
    expect(_onScreen(tester, find.text('Thing 28')), isTrue);
    expect(_offset(tester), greaterThan(0));
  });

  testWidgets('the landed card is an ordinary card: it closes, and stays '
      'closed', (tester) async {
    await _open(tester, '/recipes/1/edit?line=l28');
    await tester.tap(_openCards());
    await tester.pumpAndSettle();
    expect(_openCards(), findsNothing);

    // Scrolled away and back, the row is rebuilt closed.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Thing 28'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(_openCards(), findsNothing);
  });

  testWidgets('a line the recipe no longer has opens the editor as today', (
    tester,
  ) async {
    await _open(tester, '/recipes/1/edit?line=deleted-since');

    expect(tester.takeException(), isNull);
    expect(_offset(tester), 0);
    expect(_openCards(), findsNothing);
    expect(find.text('Edit recipe'), findsOneWidget);
  });

  testWidgets('at a desk the line lands the same, in the lines column', (
    tester,
  ) async {
    await _open(
      tester,
      '/recipes/1/edit?line=l28',
      surface: const Size(1440, 900),
    );

    expect(tester.takeException(), isNull);
    expect(_openCards(), findsOneWidget);
    expect(_onScreen(tester, _openCards()), isTrue);
    expect(_onScreen(tester, find.text('Thing 28')), isTrue);
  });

  testWidgets('at a desk focus=makes puts the caret in the MAKES cell', (
    tester,
  ) async {
    await _open(
      tester,
      '/recipes/1/edit?focus=makes',
      surface: const Size(1440, 900),
    );

    expect(tester.takeException(), isNull);
    expect(_onScreen(tester, find.text('MAKES')), isTrue);
    expect(_makesAmount(tester).focusNode.hasFocus, isTrue);
  });
}
