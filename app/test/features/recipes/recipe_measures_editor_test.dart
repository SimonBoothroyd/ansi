/// The MEASURES editor — the household's own word for one of what a recipe
/// makes, stated as an amount in a unit (ADR-0018).
///
/// Two groups, because the widget has two jobs. The first hosts
/// [RecipeMeasuresEditor] on its own, the way the ＋ on a component's quantity
/// dock will: every state of the list and the form, including the refusals,
/// asserted in the words a person reads. The second hosts it where it ships
/// first — inside the recipe editor's header form, which has a Save — so what
/// is proved there is the DEFERRAL: a word rides the draft and lands with the
/// recipe, and nothing is written before that.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/presentation/recipe_measures_editor.dart';
import 'package:ansi/shared/unit_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_recipe_measure_repository.dart';
import '../../helpers/forui_semantics.dart';

/// What the aioli makes: a weight. Every word below is said in that family
/// unless the test is about the refusal for one that is not.
const _makesMass = [(qty: 300.0, unit: g)];

const _blob = RecipeMeasure(
  id: 'm-blob',
  recipeId: 'aioli',
  label: 'blob',
  amount: 15,
  unit: g,
);

/// The add form's three slots, keyed rather than found by position: the
/// amount's unit chip is itself a text field on some platforms, and the label
/// is not the only field on a hosting screen.
final _labelField = find.descendant(
  of: find.byKey(const ValueKey('add-word-measure-label')),
  matching: find.byType(TextField),
);
final _amountField = find.descendant(
  of: find.byKey(const ValueKey('add-word-measure-amount')),
  matching: find.byType(TextField),
);
final _unitChip = find.byKey(const ValueKey('add-word-measure-unit'));

final _editLabelField = find.descendant(
  of: find.byKey(const ValueKey('edit-word-measure-label')),
  matching: find.byType(TextField),
);
final _editAmountField = find.descendant(
  of: find.byKey(const ValueKey('edit-word-measure-amount')),
  matching: find.byType(TextField),
);

Future<void> _pickUnit(WidgetTester tester, Finder chip, String label) async {
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// The editor's own button, by the word the host gave it.
Future<void> _tapAdd(WidgetTester tester, [String word = 'Save']) async {
  await tester.tap(
    find.descendant(
      of: find.byType(RecipeMeasuresEditor),
      matching: find.widgetWithText(FButton, word),
    ),
  );
  await tester.pumpAndSettle();
}

bool _labelHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('add-word-measure-label')),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

/// A host that holds the list itself, like the direct door will: what the
/// editor hands back goes straight into [words], so a test reads the list the
/// editor produced rather than a draft two layers away.
class _Host extends StatefulWidget {
  const _Host({required this.yields, this.words = const [], this.refuseWith});

  final List<YieldDenomination> yields;
  final List<RecipeMeasure> words;

  /// A host layer that turns the authored word down anyway — the direct door's
  /// repository, which re-reads the world inside its own transaction.
  final String? refuseWith;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<RecipeMeasure> words = widget.words;
  List<YieldDenomination> get yields => _yields ?? widget.yields;
  List<YieldDenomination>? _yields;

  /// Restates what the recipe makes from inside the test's own tree, which is
  /// what editing MAKES in the same draft does.
  void makes(List<YieldDenomination> stated) =>
      setState(() => _yields = stated);

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      recipeMeasureRepositoryProvider.overrideWithValue(
        FakeRecipeMeasureRepo(),
      ),
    ],
    child: MaterialApp(
      home: FTheme(
        data: ansiThemeData(),
        child: FScaffold(
          child: ListView(
            children: [
              RecipeMeasuresEditor(
                recipeId: 'aioli',
                yields: yields,
                measures: words,
                onAdd: (word) async {
                  if (widget.refuseWith case final reason?) {
                    return RecipeMeasureTurnedDown(reason);
                  }
                  setState(() => words = [...words, word]);
                  return RecipeMeasureLanded(word);
                },
                onRestate: (word) async {
                  setState(() {
                    words = [
                      for (final m in words)
                        if (m.id == word.id) word else m,
                    ];
                  });
                  return RecipeMeasureLanded(word);
                },
                onDelete: (word) async =>
                    setState(() => words = [...words]..remove(word)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<_HostState> _pump(WidgetTester tester, _Host host) async {
  filterForuiSemanticsAssertions();
  tallSurface(tester);
  await tester.pumpWidget(host);
  await tester.pumpAndSettle();
  return tester.state<_HostState>(find.byType(_Host));
}

void main() {
  group('the editor on its own', () {
    testWidgets('with no MAKES there is no form — one sentence, and it names '
        'the fix', (tester) async {
      await _pump(tester, const _Host(yields: []));

      expect(find.text(kRecipeMeasureNoYieldRefusal), findsOneWidget);
      // ONE sentence: the empty-list line would be a second problem to read.
      expect(find.textContaining('No measures yet'), findsNothing);
      // And nothing that could only produce a refusal: no slots, no chip, no
      // button.
      expect(_labelField, findsNothing);
      expect(_unitChip, findsNothing);
      expect(find.widgetWithText(FButton, 'Save'), findsNothing);
    });

    testWidgets('the words the recipe already has are still listed when MAKES '
        'has gone, each saying what is missing', (tester) async {
      await _pump(tester, const _Host(yields: [], words: [_blob]));

      expect(find.text('blob'), findsOneWidget);
      expect(find.text('15 g'), findsOneWidget);
      expect(
        find.text('nothing to be a share of · MAKES states no weight yield'),
        findsOneWidget,
      );
      expect(find.text(kRecipeMeasureNoYieldRefusal), findsOneWidget);
    });

    testWidgets('a word is an amount in a unit, and the form opens on the '
        'unit MAKES is stated in', (tester) async {
      final state = await _pump(tester, const _Host(yields: _makesMass));

      expect(
        find.descendant(of: _unitChip, matching: find.text('g')),
        findsOneWidget,
      );
      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '15');
      await tester.pump();
      await _tapAdd(tester);

      final word = state.words.single;
      expect(word.label, 'blob');
      expect(word.amount, 15);
      expect(word.unit, g);
      expect(find.text('blob'), findsOneWidget);
      expect(find.text('15 g'), findsOneWidget);
    });

    testWidgets('a word that lands empties both slots and takes the keyboard '
        'back to the label — and KEEPS the unit', (tester) async {
      await _pump(tester, const _Host(yields: [(qty: 300.0, unit: g)]));

      await _pickUnit(tester, _unitChip, 'kg');
      await tester.enterText(_labelField, 'tub');
      await tester.enterText(_amountField, '1');
      await tester.pump();
      await _tapAdd(tester);

      expect(tester.widget<TextField>(_labelField).controller?.text, '');
      expect(tester.widget<TextField>(_amountField).controller?.text, '');
      expect(_labelHasFocus(tester), isTrue);
      // Three words usually come off one scale, so the unit is the one part of
      // the last word that is also true of the next.
      expect(
        find.descendant(of: _unitChip, matching: find.text('kg')),
        findsOneWidget,
      );
    });

    testWidgets('a word that merely names a unit is refused, and everything '
        'typed survives', (tester) async {
      final state = await _pump(tester, const _Host(yields: _makesMass));

      await tester.enterText(_labelField, 'cup');
      await tester.enterText(_amountField, '240');
      await tester.pump();
      await _tapAdd(tester);

      expect(state.words, isEmpty);
      expect(find.text(recipeMeasureUnitWordRefusal('cup')), findsOneWidget);
      expect(tester.widget<TextField>(_labelField).controller?.text, 'cup');
      expect(tester.widget<TextField>(_amountField).controller?.text, '240');
    });

    testWidgets('a blank word, and a word with no number, are each refused in '
        'their own sentence', (tester) async {
      await _pump(tester, const _Host(yields: _makesMass));

      await tester.enterText(_amountField, '15');
      await tester.pump();
      await _tapAdd(tester);
      expect(find.text(kRecipeMeasureNoLabelRefusal), findsOneWidget);

      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '');
      await tester.pump();
      await _tapAdd(tester);
      expect(find.text(recipeMeasureAmountRefusal('blob')), findsOneWidget);
    });

    testWidgets('the recipe’s own word cannot be minted twice — the refusal '
        'points at the re-statement', (tester) async {
      await _pump(tester, const _Host(yields: _makesMass, words: [_blob]));

      await tester.enterText(_labelField, 'Blob');
      await tester.enterText(_amountField, '18');
      await tester.pump();
      await _tapAdd(tester);

      expect(find.text(recipeMeasureWordTakenRefusal(_blob)), findsOneWidget);
    });

    testWidgets('a unit whose family MAKES does not state is refused, and the '
        'sentence names the second denomination', (tester) async {
      // Both families are stated, so the offer holds both…
      final state = await _pump(
        tester,
        const _Host(yields: [(qty: 300.0, unit: g), (qty: 1.0, unit: cup)]),
      );
      await _pickUnit(tester, _unitChip, 'ml');
      // …and then the recipe stops saying the volume one under the pick.
      state.makes(const [(qty: 300.0, unit: g)]);
      await tester.pumpAndSettle();

      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '15');
      await tester.pump();
      await _tapAdd(tester);

      expect(state.words, isEmpty);
      expect(
        find.text(
          recipeMeasureUnitFamilyRefusal('blob', ml, const [
            (qty: 300.0, unit: g),
          ]),
        ),
        findsOneWidget,
      );
      // The pick stands: a chip that silently re-aimed itself would change the
      // sentence the person typed.
      expect(
        find.descendant(of: _unitChip, matching: find.text('ml')),
        findsOneWidget,
      );
    });

    testWidgets('the unit offer is the families MAKES states — never `batch`, '
        'never a pinch', (tester) async {
      await _pump(tester, const _Host(yields: _makesMass));

      await tester.tap(_unitChip);
      await tester.pumpAndSettle();
      for (final offered in ['g', 'kg', 'oz', 'lb']) {
        expect(find.text(offered), findsWidgets, reason: offered);
      }
      for (final withheld in ['ml', 'cup', 'piece', 'batch', 'pinch']) {
        expect(find.text(withheld), findsNothing, reason: withheld);
      }
    });

    testWidgets(
      'a row is the door to re-stating it, and the row keeps its id',
      (tester) async {
        final state = await _pump(
          tester,
          const _Host(yields: _makesMass, words: [_blob]),
        );

        await tester.tap(find.text('blob'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(_editLabelField).controller?.text,
          'blob',
        );
        expect(
          tester.widget<TextField>(_editAmountField).controller?.text,
          '15',
        );

        await tester.enterText(_editAmountField, '18');
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('edit-recipe-measure-m-blob')),
            matching: find.widgetWithText(FButton, 'Save'),
          ),
        );
        await tester.pumpAndSettle();

        final word = state.words.single;
        expect(word.id, 'm-blob', reason: 'every line saying it follows');
        expect(word.amount, 18);
        expect(find.text('18 g'), findsOneWidget);
      },
    );

    testWidgets('a host that turns the word down says so under the field, and '
        'the form keeps it', (tester) async {
      final state = await _pump(
        tester,
        const _Host(
          yields: _makesMass,
          refuseWith: 'That word is not one of this recipe’s any more.',
        ),
      );

      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '15');
      await tester.pump();
      await _tapAdd(tester);

      expect(state.words, isEmpty);
      expect(
        find.text('That word is not one of this recipe’s any more.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_labelField).controller?.text, 'blob');
    });

    testWidgets('the bin hands the word to the host', (tester) async {
      final state = await _pump(
        tester,
        const _Host(yields: _makesMass, words: [_blob]),
      );

      // The word and its number read as one sentence; the bin keeps its name.
      expect(find.bySemanticsLabel('blob · 15 g'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Delete the measure'));
      await tester.pumpAndSettle();
      expect(state.words, isEmpty);
    });
  });

  group('the recipe editor’s MEASURES section', () {
    /// The aioli, with a weight for a batch so a word can be held to it.
    Recipe aioli({
      double? yieldQty = 300,
      Unit? yieldUnit = g,
      List<RecipeMeasure> measures = const [],
    }) => Recipe(
      id: '1',
      title: 'Romesco Aioli',
      servingsBase: 4,
      yieldQty: yieldQty,
      yieldUnit: yieldUnit,
      measures: measures,
      groups: const [IngredientGroup(id: 'g1')],
    );

    Future<({FakeRecipeRepo recipes, FakeRecipeMeasureRepo words})> pump(
      WidgetTester tester,
      Recipe recipe, {
      Map<String, RecipeMeasureUsage> usage = const {},
    }) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final recipes = FakeRecipeRepo(recipe);
      final words = FakeRecipeMeasureRepo(usage: usage);
      await tester.pumpWidget(
        hostEditor('1', [
          recipeRepositoryProvider.overrideWithValue(recipes),
          recipeMeasureRepositoryProvider.overrideWithValue(words),
        ]),
      );
      await tester.pumpAndSettle();
      return (recipes: recipes, words: words);
    }

    testWidgets('it sits under MAKES, because it depends on it', (
      tester,
    ) async {
      await pump(tester, aioli());
      expect(
        tester.getTopLeft(find.text('MEASURES')).dy,
        greaterThan(tester.getTopLeft(find.text('MAKES')).dy),
      );
      expect(
        tester.getTopLeft(find.text('TIMES')).dy,
        greaterThan(tester.getTopLeft(find.text('MEASURES')).dy),
      );
      expect(
        find.text('· optional · what you call one of these'),
        findsOneWidget,
      );
    });

    testWidgets('a word typed here rides the draft and lands with the recipe — '
        'nothing is written before Save', (tester) async {
      final fakes = await pump(tester, aioli());

      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '15');
      await tester.pump();
      // The button reads `Add` on this host: the tap only fills the draft.
      await _tapAdd(tester, 'Add');

      expect(fakes.recipes.saved, isEmpty, reason: 'the draft holds it');
      expect(find.text('15 g'), findsOneWidget);

      await saveEditor(tester);
      final word = fakes.recipes.saved.single.measures.single;
      expect(word.label, 'blob');
      expect(word.amount, 15);
      expect(word.unit, g);
      expect(word.recipeId, '1');
      expect(word.sortOrder, 0);
    });

    testWidgets('MAKES edited in the same draft re-evaluates the section on '
        'the same keystroke', (tester) async {
      await pump(tester, aioli(measures: const [_blob]));
      expect(find.textContaining('nothing to be a share of'), findsNothing);

      // The one yield, restated into the other family under a live word.
      await _pickUnit(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('yield-1')),
          matching: find.byType(UnitChip),
        ),
        'ml',
      );

      expect(
        find.text('nothing to be a share of · MAKES states no weight yield'),
        findsOneWidget,
      );
      // And the add form follows MAKES rather than the word that is stranded.
      expect(
        find.descendant(of: _unitChip, matching: find.text('ml')),
        findsOneWidget,
      );
    });

    testWidgets('a Save that takes the yield away from a live word warns '
        'first, and proceeds on confirm — nothing is deleted', (tester) async {
      final fakes = await pump(tester, aioli(measures: const [_blob]));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('yield-1')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pumpAndSettle();
      await saveEditor(tester);

      expect(find.text('Leave that measure on nothing?'), findsOneWidget);
      expect(
        find.textContaining('“blob” (15 g) has nothing left to be a share of'),
        findsOneWidget,
      );
      expect(fakes.recipes.saved, isEmpty, reason: 'the warning comes first');

      await tester.tap(find.text('Save anyway'));
      await tester.pumpAndSettle();

      // It warns, never refuses: the word survives the Save it warned about.
      expect(fakes.recipes.saved.single.measures.single, _blob);
      expect(fakes.recipes.saved.single.yieldQty, isNull);
    });

    testWidgets('…and Keep editing writes nothing at all', (tester) async {
      final fakes = await pump(tester, aioli(measures: const [_blob]));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('yield-1')),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.pumpAndSettle();
      await saveEditor(tester);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(fakes.recipes.saved, isEmpty);
      expect(
        find.text('MEASURES'),
        findsOneWidget,
        reason: 'still in the form',
      );
    });

    testWidgets('a word already orphaned when the editor opened is not '
        're-warned about', (tester) async {
      // The word says grams; the recipe has only ever said a volume.
      final fakes = await pump(
        tester,
        aioli(yieldQty: 1, yieldUnit: cup, measures: const [_blob]),
      );
      expect(find.textContaining('nothing to be a share of'), findsOneWidget);

      await saveEditor(tester);
      expect(find.text('Leave that measure on nothing?'), findsNothing);
      expect(fakes.recipes.saved.single.measures.single, _blob);
    });

    testWidgets('the bin is refused while lines still say the word, and the '
        'door lists the recipes', (tester) async {
      final fakes = await pump(
        tester,
        aioli(measures: const [_blob]),
        usage: const {
          'm-blob': RecipeMeasureUsage(
            lines: 3,
            recipes: [(id: 'r9', title: 'Sausage Sliders')],
          ),
        },
      );

      await tester.tap(find.bySemanticsLabel('Delete the measure'));
      await tester.pumpAndSettle();

      // Counted at the tap, from the repository — not from the draft.
      expect(fakes.words.counted, ['m-blob']);
      expect(
        find.textContaining(
          'Can’t delete “blob” yet · 3 lines still say it, in 1 recipe.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Show me where'));
      await tester.pumpAndSettle();
      expect(find.text('STILL SAYS “blob”'), findsOneWidget);
      expect(find.text('Sausage Sliders'), findsOneWidget);

      await tester.tap(find.text('Sausage Sliders'));
      await tester.pumpAndSettle();
      // The word is still the recipe's: a refused delete changes nothing.
      expect(find.text('15 g'), findsNothing, reason: 'on the recipe now');
    });

    testWidgets('a word no Save has written yet just leaves the draft', (
      tester,
    ) async {
      final fakes = await pump(tester, aioli());

      await tester.enterText(_labelField, 'blob');
      await tester.enterText(_amountField, '15');
      await tester.pump();
      await _tapAdd(tester, 'Add');
      expect(find.text('15 g'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Delete the measure'));
      await tester.pumpAndSettle();
      expect(find.text('15 g'), findsNothing);

      await saveEditor(tester);
      expect(fakes.recipes.saved.single.measures, isEmpty);
    });

    testWidgets('a stored word the draft drops is soft-deleted by the Save, '
        'not by the tap', (tester) async {
      final fakes = await pump(tester, aioli(measures: const [_blob]));

      await tester.tap(find.bySemanticsLabel('Delete the measure'));
      await tester.pumpAndSettle();

      // The gate asked, and nothing was written: the diff inside `saveRecipe`
      // is the one place a row is retired.
      expect(fakes.words.counted, ['m-blob']);
      expect(fakes.words.deleted, isEmpty);
      await saveEditor(tester);
      expect(fakes.recipes.saved.single.measures, isEmpty);
    });

    testWidgets('a Save the repository refuses says what it refused, and the '
        'draft is still there', (tester) async {
      filterForuiSemanticsAssertions();
      tallSurface(tester);
      final recipes = _RefusingRepo(aioli(measures: const [_blob]));
      await tester.pumpWidget(
        hostEditor('1', [
          recipeRepositoryProvider.overrideWithValue(recipes),
          recipeMeasureRepositoryProvider.overrideWithValue(
            FakeRecipeMeasureRepo(),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      await saveEditor(tester);

      expect(find.text('That Save didn’t land'), findsOneWidget);
      expect(find.text(_RefusingRepo.reason), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      // Still in the editor, with the word still in the draft.
      expect(find.text('MEASURES'), findsOneWidget);
      expect(find.text('15 g'), findsOneWidget);
    });
  });
}

/// A repository whose Save refuses a word, the way one that both edits `makes`
/// and re-states a word in the same transaction does.
class _RefusingRepo extends FakeRecipeRepo {
  _RefusingRepo(Recipe super.recipe);

  static const reason =
      'This recipe makes 1 cup, so “blob” can’t be said in g — a recipe has no '
      'density to get from one to the other.';

  @override
  Future<void> saveRecipe(Recipe recipe) async =>
      throw const RecipeMeasureRefused('recipe_measure/unit_family', reason);
}
