/// The recipe editor at `AnsiLayout.expanded`: one header across the top, the
/// lines left and the method right — and the step being written lighting the
/// lines its chips point at.
///
/// Every assertion here is about PLACEMENT and about the one relationship the
/// width buys. What a row, a card, a step card or a door *says* is pinned by
/// the phone's own suites, and this layout shares those widgets rather than
/// restating them, so a test that re-asserted their words would only prove the
/// sharing twice.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/method_draft.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:ansi/features/recipes/presentation/line_card.dart';
import 'package:ansi/features/recipes/presentation/method_editor.dart';
import 'package:ansi/features/recipes/presentation/method_span_controller.dart';
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart';
import 'package:ansi/shared/amount_and_unit.dart';
import 'package:ansi/shared/ansi_layout.dart';
import 'package:ansi/shared/ansi_stepper_row.dart';
import 'package:ansi/shared/inline_amount_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';

/// The editor under a real router — Save navigates, and the card's doors open
/// on the shell navigator — inside the pane the router really gives it.
Widget _host(Widget child, List<Override> overrides) {
  final router = GoRouter(
    initialLocation: '/edit',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SizedBox(),
        routes: [GoRoute(path: 'edit', builder: (_, _) => child)],
      ),
      GoRoute(path: '/recipes/:id', builder: (_, _) => const SizedBox()),
    ],
  );
  addTearDown(router.dispose);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => FTheme(
        data: ansiThemeData(),
        child: FToaster(child: child ?? const SizedBox()),
      ),
    ),
  );
}

/// A desk-width window, with the editor in the cap the router gives it — so
/// the columns are measured at the width they are really drawn at.
///
/// [rail] puts the shell's 64 px icon rail beside the page, which is what the
/// app really draws from 1024: the band is read off the *window* and the cap
/// off the *pane*, so 1024 with the rail is the narrowest pane the wide header
/// is ever drawn in — 10 px narrower per cell than 1024 without it.
Future<FakeRecipeRepo> _pumpWide(
  WidgetTester tester, {
  Recipe recipe = importedRecipe,
  Size surface = const Size(1440, 2600),
  bool rail = false,
}) async {
  filterForuiSemanticsAssertions();
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeRecipeRepo(recipe);
  const page = AnsiMeasure(
    width: ansiWideMeasureWidth,
    child: RecipeEditorView(recipeId: '1'),
  );
  await tester.pumpWidget(
    _host(
      rail
          ? const Row(
              children: [
                SizedBox(width: 64),
                Expanded(child: page),
              ],
            )
          : page,
      [
        recipeRepositoryProvider.overrideWithValue(repo),
        ingredientRepositoryProvider.overrideWithValue(
          const FakeIngredientRepo(),
        ),
        measureRepositoryProvider.overrideWithValue(FakeMeasureRepo()),
        bookRepositoryProvider.overrideWithValue(FakeBookRepo()),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// The row for a line id, as the list keys it.
Finder _row(String lineId) => find.byKey(ValueKey('line-$lineId'));

/// Whether that row is wearing the lit wash.
bool _lit(WidgetTester tester, String lineId) => tester
    .widget<LineCardSurface>(
      find.descendant(of: _row(lineId), matching: find.byType(LineCardSurface)),
    )
    .lit;

/// The step cards' own editables, in the order they are drawn.
Finder get _stepFields => find.byWidgetPredicate(
  (w) => w is EditableText && w.controller is MethodSpanController,
);

double _left(WidgetTester tester, Finder of) => tester.getTopLeft(of).dx;
double _top(WidgetTester tester, Finder of) => tester.getTopLeft(of).dy;

/// The words the wide header's dense cells put beside their controls, as drawn.
const _denseWords = ['COOK', 'TOTAL', 'FRIDGE', 'FREEZES', 'FREEZER'];

/// A draft with every fact a dense cell can grow already stated, so all five
/// words and both conditional controls are on screen.
final _everyFact = importedRecipe.copyWith(
  yieldQty: 8,
  yieldUnit: pieces,
  freezable: true,
  keepsForDays: 3,
);

/// How many lines a label REALLY takes in the box it was given — off the
/// rendered paragraph's own text and its own width, not off what the widget
/// meant. A word the column is too narrow for reads as two lines here whether
/// it wrapped or was clipped into looking like one.
int _lines(WidgetTester tester, Finder of) {
  final paragraph = tester.renderObject<RenderParagraph>(of);
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout(maxWidth: paragraph.size.width);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines;
}

void main() {
  group('structural: the router caps the editor like the page it edits', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();

    test('a new recipe takes the two-column cap', () {
      final start = source.indexOf("path: '/recipes/new',");
      expect(start, isNot(-1));
      final route = source.substring(
        start,
        source.indexOf("path: '/recipes/:id',", start),
      );
      expect(
        route,
        contains('measure: ansiWideMeasureWidth'),
        reason: 'a new recipe is written in the form an old one is edited in',
      );
    });

    test('the editor takes it too — except in week mode, which is one '
        'column at the measure', () {
      final start = source.indexOf("path: '/recipes/:id/edit'");
      expect(start, isNot(-1));
      final route = source.substring(start, source.indexOf('builder:', start));
      expect(route, contains("queryParameters['week'] == null"));
      expect(route, contains('ansiWideMeasureWidth'));
      expect(
        route,
        contains('ansiMeasureWidth'),
        reason:
            'week mode draws no header form and no method, so it has no '
            'second column and its wide form is the measure',
      );
    });
  });

  testWidgets('two columns under one header — the lines left, the method '
      'right', (tester) async {
    await _pumpWide(tester);

    // The columns name themselves in the same row shape, side by side — the
    // same box, so what follows each head starts on one line.
    Rect head(String label) => tester.getRect(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(EditorSectionHead),
      ),
    );
    expect(head('METHOD').top, head('INGREDIENTS').top);
    expect(head('METHOD').height, head('INGREDIENTS').height);
    expect(
      _top(tester, find.text('METHOD')),
      _top(tester, find.text('INGREDIENTS')),
    );
    expect(
      _left(tester, find.text('METHOD')),
      greaterThan(_left(tester, find.text('INGREDIENTS'))),
    );
    // The ingredients column is the fixed one; the method takes the rest.
    expect(
      _left(tester, find.text('METHOD')) -
          _left(tester, find.text('INGREDIENTS')),
      kEditorLinesColumn + kEditorColumnGap,
    );
    // Both lines are in the left column, and the step cards are in the right.
    expect(_left(tester, _row('l1')), _left(tester, find.text('INGREDIENTS')));
    expect(
      _left(tester, _stepFields.first),
      greaterThan(_left(tester, find.text('METHOD'))),
    );

    // The header is across the top: the title over the lines, the filing over
    // the method, then the four facts on one row under them.
    expect(
      _top(tester, find.text('TITLE')),
      _top(tester, find.text('FILE UNDER')),
    );
    expect(
      _left(tester, find.text('FILE UNDER')),
      _left(tester, find.text('METHOD')),
    );
    for (final label in ['MAKES', 'TIMES', 'SHELF LIFE']) {
      expect(
        _top(tester, find.text(label)),
        _top(tester, find.text('SERVES')),
        reason: '$label is one of the four cells across the cap',
      );
      expect(
        _left(tester, find.text(label)),
        greaterThan(_left(tester, find.text('SERVES'))),
      );
    }
    // …and all of it above both columns.
    expect(
      _top(tester, find.text('SERVES')),
      lessThan(_top(tester, find.text('INGREDIENTS'))),
    );
  });

  testWidgets('the four cells are the shipped controls, not restated facts', (
    tester,
  ) async {
    await _pumpWide(tester);
    // The steppers that SET the numbers, at the width where a header drawn as
    // bare lines would have been the easy answer.
    expect(find.text('COOK'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('FRIDGE'), findsOneWidget);
    expect(find.text('FREEZES'), findsOneWidget);
    expect(find.byType(FSwitch), findsOneWidget);
  });

  testWidgets('a header cell holds every control that fact can grow — at the '
      'cap, where a quarter of it is 226 px', (tester) async {
    await _pumpWide(
      tester,
      recipe: _everyFact,
      // The narrowest window the two columns are drawn in.
      surface: const Size(1024, 2600),
    );
    // The second denomination's door and the freezer window both appear only
    // once the fact before them is stated — the cells that overflow if the
    // wide header restates the phone's one-column form.
    expect(find.text('Another'), findsOneWidget);
    expect(find.text('FREEZER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Every expanded width the header is drawn at — and 1024 again with the rail
  // beside it, which is the narrowest pane of the four. A word that does not
  // fit its column used to break inside itself (`TOTA/L`, `FRID/GE`,
  // `FREE/ZES`), which is a label that has stopped being a word.
  for (final (width, rail) in [
    (1512.0, false),
    (1280.0, false),
    (1024.0, false),
    (1024.0, true),
  ]) {
    final at = rail ? '$width beside the rail' : '$width';
    testWidgets('at $at every dense label is one whole word', (tester) async {
      await _pumpWide(
        tester,
        recipe: _everyFact,
        surface: Size(width, 2600),
        rail: rail,
      );

      for (final word in _denseWords) {
        final label = find.text(word);
        expect(
          label,
          findsOneWidget,
          reason: '$word is one of the cells’ words',
        );
        // The column it was given is wide enough for the whole word…
        expect(_lines(tester, label), 1, reason: '$word broke inside itself');
        // …and it could not break inside itself even if it were not.
        final text = tester.widget<Text>(label);
        expect(text.softWrap, isFalse, reason: '$word may not soft-wrap');
        expect(text.maxLines, 1, reason: '$word is one line');
      }

      // The four cells are still one row across the cap.
      for (final cell in ['MAKES', 'TIMES', 'SHELF LIFE']) {
        expect(
          _top(tester, find.text(cell)),
          _top(tester, find.text('SERVES')),
          reason: '$cell left the row of four at $at',
        );
      }

      // The word gave nothing back: every stepper keeps both buttons at their
      // touch size.
      for (final row in find.byType(AnsiStepperRow).evaluate()) {
        final buttons = find.descendant(
          of: find.byWidget(row.widget),
          matching: find.byType(FButton),
        );
        expect(buttons, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          final size = tester.getSize(buttons.at(i));
          expect(size.width, greaterThanOrEqualTo(40));
          expect(size.height, greaterThanOrEqualTo(40));
        }
      }

      // MAKES keeps its shape too: the qualifier beside the eyebrow on its
      // line, and the amount still one row with its unit chip.
      expect(_lines(tester, find.text('MAKES')), 1);
      expect(_lines(tester, find.text('· optional')), 1);
      expect(
        _top(tester, find.text('· optional')),
        _top(tester, find.text('MAKES')),
      );
      expect(
        _left(tester, find.text('· optional')),
        greaterThan(_left(tester, find.text('MAKES'))),
      );
      // Scoped to the yield row: the MEASURES band under these cells states an
      // amount with the same control, so the cap now draws two of them.
      final yieldAmount = find.descendant(
        of: find.byKey(const ValueKey('yield-1')),
        matching: find.byType(AmountAndUnitField),
      );
      expect(yieldAmount, findsOneWidget);
      expect(tester.getSize(yieldAmount).height, kInlineControlHeight);

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('below expanded the header is the phone’s — the cells’ short '
      'words are not drawn at all', (tester) async {
    await _pumpWide(
      tester,
      recipe: _everyFact,
      surface: const Size(1000, 3000),
    );
    for (final word in _denseWords) {
      expect(
        find.text(word),
        findsNothing,
        reason: '$word is a wide cell’s word, not the phone’s',
      );
    }
    // The phone's own rows, with the sentences the wide cells drop.
    for (final label in [
      'Cook',
      'Total',
      'Keeps in the fridge',
      'Keeps in the freezer',
      'Freezes',
      'Another denomination',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is the phone’s');
    }
  });

  testWidgets('a step with focus lights the lines its chips point at, and '
      'nothing else', (tester) async {
    await _pumpWide(tester);

    // A resting editor lights nothing.
    expect(_lit(tester, 'l1'), isFalse);
    expect(_lit(tester, 'l2'), isFalse);

    // Step one chips the fennel and nothing else.
    await tester.showKeyboard(_stepFields.first);
    await tester.pumpAndSettle();
    expect(_lit(tester, 'l1'), isTrue);
    expect(_lit(tester, 'l2'), isFalse);

    // Step two chips nothing, so taking the caret there clears the light
    // rather than leaving the last step's on.
    await tester.showKeyboard(_stepFields.at(1));
    await tester.pumpAndSettle();
    expect(_lit(tester, 'l1'), isFalse);
    expect(_lit(tester, 'l2'), isFalse);

    // And putting the form down clears it: it is view state, never stored.
    await tester.showKeyboard(_stepFields.first);
    await tester.pumpAndSettle();
    expect(_lit(tester, 'l1'), isTrue);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    expect(_lit(tester, 'l1'), isFalse);
  });

  testWidgets('below expanded nothing lights — the line it would point at is '
      'a scroll away', (tester) async {
    await _pumpWide(tester, surface: const Size(1000, 3000));
    await tester.showKeyboard(_stepFields.first);
    await tester.pumpAndSettle();
    expect(_lit(tester, 'l1'), isFalse);
  });

  testWidgets('the chip the caret is inside is ringed, and only in the wide '
      'editor', (tester) async {
    const step = MethodDraftStep(
      id: 's1',
      text: 'Halve the fennel bulb.',
      spans: [
        RefSpan(start: 10, end: 21, refs: ['l1']),
      ],
    );
    await tester.pumpWidget(const SizedBox());
    final context = tester.element(find.byType(SizedBox));

    TextStyle skinAt(int caret, {required bool wide}) {
      final controller = MethodSpanController(step, ringsCaretChip: wide)
        ..selection = TextSelection.collapsed(offset: caret);
      final painted = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      addTearDown(controller.dispose);
      return (painted.children![1] as TextSpan).style!;
    }

    // The caret inside the chip.
    expect(skinAt(14, wide: true).decoration, TextDecoration.underline);
    expect(skinAt(14, wide: true).decorationColor, AnsiColors.herb);
    // Out in the prose, nothing is ringed…
    expect(skinAt(2, wide: true).decoration, isNull);
    // …and the phone rings nothing at all.
    expect(skinAt(14, wide: false).decoration, isNull);
  });

  testWidgets('a line’s identity door opens the shipped picker as a dialog', (
    tester,
  ) async {
    await _pumpWide(tester);

    await tester.tap(find.textContaining('Fennel bulb', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('change ›'));
    await tester.pumpAndSettle();

    expect(find.byType(FDialog), findsOneWidget);
    // The picker itself, unchanged in content — the editor builds none of it.
    expect(find.text('Change Fennel bulb to'), findsOneWidget);
  });

  testWidgets('Save still writes, from where the phone puts it', (
    tester,
  ) async {
    final repo = await _pumpWide(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved.single.title, 'Sausage Sliders');
  });

  testWidgets('the left column is still one draggable list', (tester) async {
    await _pumpWide(tester);
    // Both rows carry the grip, and it is inside the ingredients column.
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2));
    expect(
      _left(tester, _row('l2')) + kEditorLinesColumn,
      lessThanOrEqualTo(_left(tester, find.text('METHOD'))),
    );
  });

  testWidgets('below expanded the editor is the phone’s one scroll', (
    tester,
  ) async {
    await _pumpWide(tester, surface: const Size(1000, 3000));
    // No second column and no column head over the lines: the method is under
    // the list, exactly where the phone has it.
    expect(find.text('INGREDIENTS'), findsNothing);
    expect(
      _top(tester, find.text('METHOD')),
      greaterThan(_top(tester, _row('l2'))),
    );
    expect(_left(tester, find.text('METHOD')), _left(tester, _row('l1')));
  });

  testWidgets('MEASURES takes the band under the four cells, at the cap’s full '
      'width — the one section a quarter of the cap cannot hold', (
    tester,
  ) async {
    await _pumpWide(
      tester,
      recipe: _everyFact,
      surface: const Size(1024, 2600),
    );

    // Under the cells, not beside them, and on the ingredients column's own
    // axis: it is still the header form, laid across the cap.
    expect(
      _top(tester, find.text('MEASURES')),
      greaterThan(_top(tester, find.text('MAKES'))),
    );
    expect(
      _left(tester, find.text('MEASURES')),
      _left(tester, find.text('TITLE')),
    );
    expect(
      _top(tester, find.text('MEASURES')),
      lessThan(_top(tester, find.text('INGREDIENTS'))),
    );
    // The shipped form, whole: a label, an amount with its chip, a button.
    expect(find.text('ADD MEASURE'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('add-word-measure-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('add-word-measure-amount')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('add-word-measure-unit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('…and it carries the gate at this width too', (tester) async {
    // `importedRecipe` says nothing about what a batch makes.
    await _pumpWide(tester);
    expect(find.text(kRecipeMeasureNoYieldRefusal), findsOneWidget);
    expect(find.text('ADD MEASURE'), findsNothing);
  });
}
