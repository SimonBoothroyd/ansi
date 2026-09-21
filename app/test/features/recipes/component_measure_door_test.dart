/// The ＋ on a component's quantity dock — the door a word is usually coined
/// through (ADR-0018).
///
/// The owner's scenario is the one this file is really about: he thinks of
/// `blob` while writing the recipe that SAYS it, taps ＋ on the sauce's dock,
/// coins the word there, and the line now reads `3 blob`. Everything else here
/// is what that door must not get wrong — a refusal printed where it was
/// caused, a failure that is never silent, a retirement that cannot strand the
/// line it was picked for, and the two hosts that must not offer the door at
/// all.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/recipe_measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/presentation/unit_chips.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_authoring.dart';
import 'package:ansi/features/recipes/domain/recipe_measure_repository.dart';
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart';
import 'package:ansi/features/recipes/presentation/recipe_measures_editor.dart';
import 'package:ansi/shared/ansi_tap.dart';
import 'package:ansi/shared/unit_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_recipe_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/measure_fixtures.dart';
import '../../helpers/pump_app.dart';

/// The same sauce with no MAKES — the gate's own state.
const _unmeasured = SubRecipeTarget(id: 'aioli', title: 'Romesco Aioli');

/// The manage chip: a real icon, not a glyph — the bundled fonts carry no
/// U+FF0B, so the row draws [FLucideIcons.plus].
final _plus = find.descendant(
  of: find.byType(UnitChipRow),
  matching: find.byIcon(FLucideIcons.plus),
);

final _labelField = find.descendant(
  of: find.byKey(const ValueKey('add-word-measure-label')),
  matching: find.byType(TextField),
);
final _amountField = find.descendant(
  of: find.byKey(const ValueKey('add-word-measure-amount')),
  matching: find.byType(TextField),
);
final _editAmountField = find.descendant(
  of: find.byKey(const ValueKey('edit-word-measure-amount')),
  matching: find.byType(TextField),
);

/// A chip in the dock's row, by its bare label — `find.text` alone would also
/// match the sentence beside the number, which says `blob (15 g)`.
Finder _chip(String label) => find.descendant(
  of: find.byType(UnitChipRow),
  matching: find.widgetWithText(UnitChip, label),
);

bool _chipIsSelected(WidgetTester tester, String label) =>
    tester.widget<UnitChip>(_chip(label)).selected;

/// What the sheet handed back, and the store it wrote through.
typedef _Door = ({FakeRecipeMeasureRepo words, List<ComponentQuantity> done});

Future<_Door> _pumpDoor(
  WidgetTester tester, {
  SubRecipeTarget target = aioliTarget,
  List<RecipeMeasure> words = const [],

  /// What the HOST handed over, where that differs from the live store — the
  /// import review strips the words it cannot say.
  List<RecipeMeasure>? snapshot,
  Map<String, RecipeMeasureUsage> usage = const {},
  String? refuseWith,
  Object? failWith,
  double? initialQuantity,
  Unit? initialUnit = batches,
  String? initialMeasureId,
  bool mayCoinWords = true,
  VoidCallback? onSetYield,
}) async {
  filterForuiSemanticsAssertions();
  tallSurface(tester);
  final repo = FakeRecipeMeasureRepo(
    usage: usage,
    measures: words,
    refuseWith: refuseWith,
    failWith: failWith,
  );
  final done = <ComponentQuantity>[];
  await tester.pumpAnsiApp(
    FScaffold(
      child: ComponentQuantityEditor(
        target: target.copyWith(measures: snapshot ?? words),
        initialQuantity: initialQuantity,
        initialUnit: initialUnit,
        initialMeasureId: initialMeasureId,
        mayCoinWords: mayCoinWords,
        onSetYield: onSetYield,
        onDone: done.add,
      ),
    ),
    overrides: [recipeMeasureRepositoryProvider.overrideWithValue(repo)],
  );
  await tester.pumpAndSettle();
  return (words: repo, done: done);
}

/// Coins one word behind the ＋; a word that lands returns to the amount.
Future<void> _coin(
  WidgetTester tester, {
  required String label,
  required String amount,
}) async {
  await tester.enterText(_labelField, label);
  await tester.enterText(_amountField, amount);
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(RecipeMeasuresEditor),
      matching: find.widgetWithText(FButton, 'Save'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Back out of the manage state, to the amount.
Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Back'));
  await tester.pumpAndSettle();
}

/// The sheet on its REAL route, which is what the re-statement test needs: the
/// crash it pins is a scroll inside the open row's own field, and a field only
/// scrolls where the surface it sits on can.
Future<FakeRecipeMeasureRepo> _pumpSheet(
  WidgetTester tester, {
  List<RecipeMeasure> words = const [blobWord],
}) async {
  filterForuiSemanticsAssertions();
  final repo = FakeRecipeMeasureRepo(measures: words);
  await tester.pumpAnsiApp(
    FScaffold(
      child: Builder(
        builder: (context) => AnsiTap(
          onTap: () => showComponentQuantitySheet(
            context,
            target: aioliTarget.copyWith(measures: words),
            initialQuantity: 2,
            initialMeasureId: words.isEmpty ? null : words.first.id,
            mayCoinWords: true,
          ),
          semanticsLabel: 'open',
          child: const Text('open'),
        ),
      ),
    ),
    overrides: [recipeMeasureRepositoryProvider.overrideWithValue(repo)],
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('he thinks of the word while writing the OTHER recipe: ＋, coin '
      'it, and the line says 3 blob', (tester) async {
    final door = await _pumpDoor(tester, initialQuantity: 1);
    expect(_chip('blob'), findsNothing, reason: 'no such word yet');

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    expect(find.text('Measures'), findsOneWidget);
    expect(find.text('Romesco Aioli'), findsWidgets);

    await _coin(tester, label: 'blob', amount: '15');
    // The direct door has no Save of its own: the word is written on the tap.
    expect(door.words.added.single.label, 'blob');
    expect(door.words.added.single.recipeId, 'aioli');

    // Back on the amount with no Back tap, as the ingredient dock does. It is
    // a chip because the sheet WATCHES the target's words, and the selected
    // one because this door was opened mid-sentence.
    expect(find.text('Measures'), findsNothing);
    expect(_chip('blob'), findsOneWidget);
    expect(_chipIsSelected(tester, 'blob'), isTrue);

    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pumpAndSettle();
    expect(
      find.text('3 blob = 0.15 of a batch · a blob is 15 g'),
      findsWidgets,
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    final saved = door.done.single;
    expect(saved.quantity, 3);
    expect(saved.recipeMeasureId, door.words.added.single.id);
    expect(saved.unit, isNull, reason: 'a unit here would lose the word');
  });

  testWidgets('the repository’s refusal is printed under the field, with '
      'everything typed still there', (tester) async {
    const reason =
        'This recipe makes 300 g, so “blob” can’t be said in ml — a recipe has '
        'no density to get from one to the other.';
    final door = await _pumpDoor(tester, refuseWith: reason);

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await _coin(tester, label: 'blob', amount: '15');

    expect(find.text(reason), findsOneWidget);
    expect(tester.widget<TextField>(_labelField).controller?.text, 'blob');
    expect(tester.widget<TextField>(_amountField).controller?.text, '15');
    expect(door.words.measures, isEmpty);
  });

  testWidgets('a write that fails for any other reason says so through the '
      'write door — never in silence', (tester) async {
    final door = await _pumpDoor(tester, failWith: StateError('no network'));

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await _coin(tester, label: 'blob', amount: '15');

    // The write door's own surface, not a second sentence under the field.
    expect(find.textContaining('coin “blob”'), findsWidgets);
    expect(door.words.measures, isEmpty);
    // And the draft is untouched, so the retry is one tap.
    expect(tester.widget<TextField>(_labelField).controller?.text, 'blob');
  });

  testWidgets('the bin behind the ＋ asks the gate, and a word lines still say '
      'does not go', (tester) async {
    final door = await _pumpDoor(
      tester,
      words: const [blobWord],
      usage: const {
        'm-blob': RecipeMeasureUsage(
          lines: 3,
          recipes: [(id: 'r9', title: 'Sausage Sliders')],
        ),
      },
      initialUnit: null,
      initialMeasureId: 'm-blob',
    );

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete the measure'));
    await tester.pumpAndSettle();

    // Counted at the tap, from the repository — never off the list on screen.
    expect(door.words.counted, ['m-blob']);
    expect(
      find.textContaining(
        'Can’t delete “blob” yet · 3 lines still say it, in 1 recipe.',
      ),
      findsOneWidget,
    );
    expect(door.words.deleted, isEmpty);
  });

  testWidgets('retiring the word the line is written in reconciles the '
      'selection, so Done cannot write a tombstone', (tester) async {
    final door = await _pumpDoor(
      tester,
      words: const [blobWord],
      initialQuantity: 2,
      initialUnit: null,
      initialMeasureId: 'm-blob',
    );
    expect(_chipIsSelected(tester, 'blob'), isTrue);

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete the measure'));
    await tester.pumpAndSettle();
    expect(door.words.deleted, ['m-blob']);

    await _back(tester);
    expect(_chip('blob'), findsNothing);
    expect(find.text('“blob” retired — back to g'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(door.done.single.recipeMeasureId, isNull);
    expect(door.done.single.unit, g);
  });

  testWidgets('with no MAKES the ＋ says one sentence and offers the same door '
      'to the yield as the amount does', (tester) async {
    var sent = 0;
    await _pumpDoor(tester, target: _unmeasured, onSetYield: () => sent++);

    await tester.tap(_plus);
    await tester.pumpAndSettle();

    expect(find.text(kRecipeMeasureNoYieldRefusal), findsOneWidget);
    expect(_labelField, findsNothing, reason: 'a form here could only refuse');
    await tester.tap(find.text('Set the yield'));
    expect(sent, 1);
  });

  testWidgets('with no MAKES and nowhere to set it there is no ＋ — the page '
      'could only refuse', (tester) async {
    await _pumpDoor(tester, target: _unmeasured);

    expect(_plus, findsNothing);
  });

  testWidgets('a re-statement the repository refuses is printed under the open '
      'row, and the row stays open', (tester) async {
    const reason = 'That measure is not one of this recipe’s any more.';
    final door = await _pumpDoor(
      tester,
      words: const [blobWord],
      refuseWith: reason,
      initialQuantity: 2,
      initialUnit: null,
      initialMeasureId: 'm-blob',
    );

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RecipeMeasuresEditor),
        matching: find.text('blob'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_editAmountField, '18');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('edit-recipe-measure-m-blob')),
        matching: find.widgetWithText(FButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(reason), findsOneWidget);
    expect(door.words.restated, isEmpty);
    expect(tester.widget<TextField>(_editAmountField).controller?.text, '18');
  });

  testWidgets('a word re-stated under the sheet follows through to the line '
      'that says it — the row is watched, not copied', (tester) async {
    final door = await _pumpDoor(
      tester,
      words: const [blobWord],
      initialQuantity: 2,
      initialUnit: null,
      initialMeasureId: 'm-blob',
    );
    expect(find.text('2 blob = 0.1 of a batch · a blob is 15 g'), findsWidgets);

    // A blob that turns out to be 18 g — re-stated behind the ＋ here, or on
    // the other phone, which reaches this sheet by the same door.
    await door.words.restateRecipeMeasure(
      measureId: 'm-blob',
      label: 'blob',
      amount: 18,
      unit: g,
    );
    await tester.pumpAndSettle();

    // The id is kept, so the line still says the word — with the new number.
    expect(_chipIsSelected(tester, 'blob'), isTrue);
    expect(find.textContaining('a blob is 15 g'), findsNothing);
    expect(find.text('2 blob = ⅛ of a batch · a blob is 18 g'), findsWidgets);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(door.done.single.recipeMeasureId, 'm-blob');
  });

  testWidgets('re-stating a word behind the ＋ saves it — and takes no scroll '
      'down with the row it closes', (tester) async {
    final words = await _pumpSheet(tester);

    await tester.tap(_plus);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(RecipeMeasuresEditor),
        matching: find.text('blob'),
      ),
    );
    await tester.pumpAndSettle();
    // Typing leaves the slot's own caret scroll animating; Save then takes the
    // whole form out of the tree under it, which is the assertion this pins.
    await tester.enterText(_editAmountField, '18');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('edit-recipe-measure-m-blob')),
        matching: find.widgetWithText(FButton, 'Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'a scroll over the row Save removed',
    );
    expect(words.restated.single.amount, 18);
    expect(_editAmountField, findsNothing, reason: 'the row closed');
  });

  testWidgets('a host that cannot say a word offers no ＋ — the import review, '
      'whose line has no column for one', (tester) async {
    await _pumpDoor(
      tester,
      words: const [blobWord],
      // The review's two doors hand the sheet a target with its words
      // stripped, and this one must not go behind their backs for them.
      snapshot: const [],
      mayCoinWords: false,
    );

    expect(_plus, findsNothing);
    // And the watch is not even asked: the offer is the caller's snapshot.
    expect(_chip('blob'), findsNothing);
  });

  testWidgets('a component whose recipe row has not synced offers no ＋ — '
      'there is nothing to stamp a word onto', (tester) async {
    await _pumpDoor(
      tester,
      target: const SubRecipeTarget(id: '', title: 'Romesco Aioli'),
    );

    expect(_plus, findsNothing);
  });
}
