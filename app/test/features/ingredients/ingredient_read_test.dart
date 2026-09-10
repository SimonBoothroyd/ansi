/// The ingredient page's READING posture — the fact sheet a row opens as, and
/// the `⋯ ▸ Edit` that turns it back into the form.
///
/// The load-bearing test here is the last one: **both postures state the same
/// facts** about one row, each in its own idiom. One route with two renderings
/// is exactly the shape that drifts, and the shared sentences
/// (`ingredient_facts.dart`) are what stop it — this is where that is pinned.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// Mango's facts as the reading posture states them — the strings the shared
/// sentences produce, spelled out so a change to any of them is a change a
/// reader has to agree to.
const mangoMacroLine = '60 kcal · 1P 0F 15C /100 g';
const mangoDensity = '1 cup weighs 156.15 g · 0.66 g/ml';
const mangoPieceWeight = '1 piece weighs 200 g';

void main() {
  group('the reading posture', () {
    testWidgets('an existing row opens as a fact sheet — every group, no '
        'fields and no dock', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(
            const [mango],
            aliasesById: const {
              'mango': [
                IngredientAlias(id: 'a1', text: 'mangoes', source: 'manual'),
              ],
            },
          ),
          at: ingredientDetailRoute('mango'),
          measures: FakeMeasureRepo(const [
            Measure(
              id: 'm1',
              label: 'mango, medium',
              amount: 200,
              source: 'usda_fdc:9176 (1 fruit)',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // The name leads, with the other words it answers to under it.
      expect(find.text('Mango'), findsOneWidget);
      expect(find.text('also known as mangoes'), findsOneWidget);
      expect(
        find.text('Complete — counts in conversions and macro totals.'),
        findsOneWidget,
      );

      // The three groups, in the form's own order and under its own labels.
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('Units & measures'), findsOneWidget);
      expect(find.text('produce'), findsOneWidget);
      expect(find.text(mangoMacroLine), findsOneWidget);
      expect(find.text('piece'), findsOneWidget);
      expect(find.text(mangoPieceWeight), findsOneWidget);
      expect(find.text(mangoDensity), findsOneWidget);
      expect(find.text('mango, medium · 200 g'), findsOneWidget);
      expect(find.text('USDA portion'), findsOneWidget);

      // Nothing to type into and nothing to commit: reading is the whole act.
      expect(find.byType(EditableText), findsNothing);
      expect(find.byKey(kFormSaveKey), findsNothing);
      expect(find.byKey(kFormCompleteKey), findsNothing);
      // And a complete row has no call to action at all.
      expect(find.byKey(kReadFillItInKey), findsNothing);
    });

    testWidgets('a row that states fibre says so on the same line — spelled '
        'out, because F is already fat', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo([
            mango.copyWith(
              macros: const Macros(
                kcal: 60,
                protein: 1,
                carb: 15,
                fat: 0,
                fiber: 2.6,
              ),
            ),
          ]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('60 kcal · 1P 0F 15C · 2.6 fibre /100 g'),
        findsOneWidget,
      );
    });

    testWidgets('a row with no measures says so rather than saying nothing', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No measures yet.'), findsOneWidget);
    });
  });

  group('which door opens which posture', () {
    test('the route says it, and reading is the default', () {
      expect(ingredientDetailRoute('mango'), '/ingredients/mango');
      expect(
        ingredientDetailRoute('mango', edit: true),
        '/ingredients/mango?edit=1',
      );
    });

    testWidgets('a fix door lands in the FORM — it named a field to change', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango', edit: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(find.byKey(kFormSaveKey), findsOneWidget);
      expect(find.text(mangoMacroLine), findsNothing);
    });

    testWidgets('/ingredients/new opens the form — there is nothing to read', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const []), at: '/ingredients/new'),
      );
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(
        find.text('New — nothing is saved until you tap Save.'),
        findsOneWidget,
      );
    });
  });

  group('switching posture', () {
    testWidgets('⋯ ▸ Edit opens the form, back returns to the fact sheet, and '
        'Save lands on it showing what was written', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: ingredientDetailRoute('mango')));
      await tester.pumpAndSettle();
      expect(find.text(mangoMacroLine), findsOneWidget);

      await openMoreMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);

      // Back out of the form with an edit in hand: the form discards it, as
      // it always has (nothing is written until Save), and the page stays.
      await tester.enterText(find.byType(EditableText).first, 'Mangosteen');
      await tester.pump();
      await tapBack(tester);
      expect(find.text('CANONICAL NAME'), findsNothing);
      expect(find.text('Mango'), findsOneWidget);
      expect((await repo.byId('mango'))!.canonicalName, 'Mango');

      // And Save puts the form down onto the same page, now saying the new
      // name — no pop, so the fact sheet is what the person is left holding.
      await openMoreMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).first, 'Mango, ripe');
      await tester.pump();
      await saveForm(tester);
      expect(find.text('CANONICAL NAME'), findsNothing);
      expect(find.text('Mango, ripe'), findsOneWidget);
      expect(find.text(mangoMacroLine), findsOneWidget);
    });

    testWidgets('the system back leaves the MODE, not the page — back means '
        'one thing here', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango', edit: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsNothing);
      expect(find.text(mangoMacroLine), findsOneWidget);
      // The fact sheet itself pops like any other pushed page — the mode is
      // what holds the gesture, and only while it is open.
    });
  });

  group('a stub reads as a stub', () {
    testWidgets('one call to action, and never a zero where a macro is '
        'missing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [curryLeaves]),
          at: ingredientDetailRoute('curry'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Still a stub — left out of macro totals until confirmed.'),
        findsOneWidget,
      );
      // The dock's own words, not four zeros (invariant 3).
      expect(find.text('needs macros'), findsOneWidget);
      expect(find.textContaining('0 kcal'), findsNothing);
      // The density says what it is short of in the entry's own words.
      expect(find.text('none yet — unlocks volume⇄weight'), findsOneWidget);
      // Which food the prefill came from, in the line the manager already
      // prints under the same row.
      expect(find.text('usda · Curry leaves, raw'), findsOneWidget);

      // The ONE button on the page, and it opens the fields.
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.byKey(kReadFillItInKey));
      await tester.pumpAndSettle();
      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(find.text('FILL IT IN FROM'), findsOneWidget);
    });
  });

  group('a row that states a serving reads the label first', () {
    /// The owner's peanut butter, as the form would have left it: the macros
    /// per 100 ml, the serving kept as a measure, and a density typed in the
    /// density section as the jar prints it.
    const peanutButter = Ingredient(
      id: 'pb',
      canonicalName: 'Peanut Butter',
      defaultUnit: ml,
      status: IngredientStatus.complete,
      category: 'pantry',
      densityGPerMl: 1.0820182,
      macros: Macros(kcal: 642.464, protein: 23.669, carb: 23.669, fat: 54.101),
      macrosBasis: MacrosBasis.perMl,
      measureCount: 1,
      source: 'manual',
    );

    testWidgets('the jar’s own line, with the per-100 under it — and the '
        'density in the unit it was typed in', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [peanutButter]),
          at: ingredientDetailRoute('pb'),
          measures: FakeMeasureRepo(const [
            Measure(
              id: 's1',
              label: 'serving · 2 tbsp',
              amount: 29.5735295625,
              basis: MacrosBasis.perMl,
              source: 'manual',
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      // A wrong number is checkable against the jar without a calculator: the
      // jar says 190 per 2 tbsp, and so does the page.
      expect(find.text('190 kcal · 7P 16F 7C per 2 tbsp'), findsOneWidget);
      expect(find.text('as the label reads'), findsOneWidget);
      // The derivation is under it, for the reader who wants what the totals
      // actually use.
      expect(
        find.text('per 100 ml · 642 kcal · 23.7P 54.1F 23.7C'),
        findsOneWidget,
      );
      // The density reads back as the sentence it was entered as, with the
      // ratio as the aside rather than as the sentence.
      expect(find.text('2 tbsp weighs 32 g'), findsOneWidget);
      expect(find.text('1.08 g/ml'), findsOneWidget);
      // And the serving is a measure like any other, listed as one.
      expect(find.text('serving · 2 tbsp · 29.57 ml'), findsOneWidget);
    });

    testWidgets('with no serving on the row, both lines are the ones they '
        'have always been', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [peanutButter]),
          at: ingredientDetailRoute('pb'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('642 kcal · 23.7P 54.1F 23.7C /100 ml'), findsOneWidget);
      expect(find.textContaining('per 100 ml · 642 kcal'), findsNothing);
      expect(find.text('1 cup weighs 255.99 g · 1.08 g/ml'), findsOneWidget);
    });
  });

  group('both postures state the same facts', () {
    testWidgets('one row, two renderings, one account of it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: ingredientDetailRoute('mango'),
        ),
      );
      await tester.pumpAndSettle();

      // Reading: the sentences.
      expect(find.text('Mango'), findsOneWidget);
      expect(find.text(mangoMacroLine), findsOneWidget);
      expect(find.textContaining('0.66 g/ml'), findsOneWidget);
      expect(find.text(mangoPieceWeight), findsOneWidget);
      expect(find.text('piece'), findsOneWidget);

      await openMoreMenu(tester);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // Editing: the same five facts, each in the control that holds it.
      expect(find.text('Mango'), findsWidgets);
      expect(macroFieldText(tester, 'kcal'), '60');
      expect(macroFieldText(tester, 'protein'), '1');
      expect(macroFieldText(tester, 'carb'), '15');
      expect(macroFieldText(tester, 'fat'), '0');
      expect(mangoMacros.kcal.round(), 60);
      expect(
        find.descendant(
          of: find.byType(DensityEntry),
          matching: find.text('0.66 g/ml'),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('200 g'),
        findsWidgets,
        reason: 'the piece-weight entry states the same weight',
      );
      expect(defaultUnitChip(tester, 'piece').selected, isTrue);
      // The basis the read line's `/100 g` names is the one the chip shows.
      expect(mango.macrosBasis, MacrosBasis.perG);
    });
  });
}
