/// The *Units & measures* section's piece-weight block on its own (ADR-0015)
/// — the count-side twin of `DensityEntry`, and the same contract: one
/// sentence, folded once the number is stated, and a widget that knows no
/// repository.
///
/// The host below IS the seam under test. Both real hosts land the number
/// themselves — the flesh-out form into its draft, the quantity sheet's manage
/// state straight through the vocabulary — so what this file pins is what the
/// widget reports and when, not what anything stores.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/piece_weight_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// A count row nobody has weighed — the state the entry exists to clear.
const _shallot = Ingredient(
  id: 'shallot',
  canonicalName: 'Shallot',
  defaultUnit: pieces,
  status: IngredientStatus.stub,
  category: 'produce',
);

/// The same row once someone typed the number.
const _weighedShallot = Ingredient(
  id: 'shallot',
  canonicalName: 'Shallot',
  defaultUnit: pieces,
  status: IngredientStatus.stub,
  category: 'produce',
  pieceBasisAmount: 45,
  pieceSource: 'manual',
);

/// A weight the seed copied off a curated size rather than one anybody typed
/// here — [Ingredient.pieceSource] is shown, never interpreted.
const _borrowed = Ingredient(
  id: 'onion',
  canonicalName: 'Onion',
  defaultUnit: pieces,
  status: IngredientStatus.stub,
  pieceBasisAmount: 350,
  pieceSource: 'borrowed from onion, medium',
);

/// The entry inside the form's own page padding, with the write seam replaced
/// by a recorder. [landsAs] is the row the host swaps in once a save reports
/// landed — both real hosts do that, and the fold is a fact about the row that
/// comes back.
Widget _host(
  Ingredient ingredient, {
  List<double>? saves,
  List<void>? removals,
  bool lands = true,
  Ingredient? landsAs,
  String saveLabel = 'Add',
}) {
  var shown = ingredient;
  return MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: FScaffold(
        childPad: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: StatefulBuilder(
            builder: (context, setState) => PieceWeightEntry(
              ingredient: shown,
              saveLabel: saveLabel,
              onSave: (amount) async {
                saves?.add(amount);
                if (!lands) return false;
                if (landsAs != null) setState(() => shown = landsAs);
                return true;
              },
              onRemove: () async {
                removals?.add(null);
                setState(() => shown = ingredient);
                return true;
              },
            ),
          ),
        ),
      ),
    ),
  );
}

Finder get _saveButton => find.byKey(const ValueKey('piece-weight-save'));

void main() {
  group('a stated weight folds to a headline', () {
    testWidgets('the number, its unit and a way back in', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_weighedShallot));
      await tester.pumpAndSettle();

      expect(find.text('PIECE WEIGHT'), findsOneWidget);
      expect(find.text('45 g'), findsOneWidget);
      expect(find.text('· change'), findsOneWidget);
      // The sentence is not the everyday height of this block.
      expect(find.text('1 piece weighs'), findsNothing);
      expect(find.text('remove the piece weight'), findsNothing);

      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      expect(find.text('1 piece weighs'), findsOneWidget);
      expect(find.text('remove the piece weight'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });

    testWidgets('a borrowed number says whose it is — the provenance is shown, '
        'never interpreted', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_borrowed));
      await tester.pumpAndSettle();

      expect(find.text('350 g · borrowed from onion, medium'), findsOneWidget);
    });

    testWidgets('a typed number says nothing extra — "yours" is the default '
        'reading of a row you are editing', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_weighedShallot));
      await tester.pumpAndSettle();

      expect(find.textContaining('manual'), findsNothing);
    });

    testWidgets('a row with no weight opens on the sentence, and says so', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_shallot));
      await tester.pumpAndSettle();

      expect(find.text('none yet — what one of these weighs'), findsOneWidget);
      expect(find.text('1 piece weighs'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });

    testWidgets('a number landed in this visit does NOT fold under your hands '
        '— the fold is where the block OPENS', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_shallot, landsAs: _weighedShallot));
      await tester.pumpAndSettle();

      await tester.enterText(pieceWeightField, '45');
      await tester.pump();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      // The headline follows the row, the sentence stays where the typing was,
      // and the affordance the number unlocks joins it.
      expect(find.text('45 g'), findsOneWidget);
      expect(find.text('1 piece weighs'), findsOneWidget);
      expect(find.text('remove the piece weight'), findsOneWidget);
      expect(find.text('· change'), findsNothing);
    });
  });

  group('the sentence reports, it does not store', () {
    testWidgets('a positive number reaches onSave in the basis unit', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      final saves = <double>[];
      await tester.pumpWidget(_host(_shallot, saves: saves));
      await tester.pumpAndSettle();

      expect(find.text('g'), findsOneWidget, reason: 'the basis unit');
      await tester.enterText(pieceWeightField, '45.5');
      await tester.pump();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(saves, [45.5]);
    });

    testWidgets('zero, a negative and an empty field are refused with the '
        'reason, and nothing is reported', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      final saves = <double>[];
      await tester.pumpWidget(_host(_shallot, saves: saves));
      await tester.pumpAndSettle();

      for (final bad in ['', '0', '-3']) {
        await tester.enterText(pieceWeightField, bad);
        await tester.pump();
        await tester.tap(_saveButton);
        await tester.pumpAndSettle();
        expect(
          find.text('weigh one: g per piece must be positive'),
          findsOneWidget,
          reason: bad.isEmpty ? '(empty)' : bad,
        );
      }
      expect(saves, isEmpty);

      // …and a good number clears the refusal.
      await tester.enterText(pieceWeightField, '45');
      await tester.pump();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('must be positive'), findsNothing);
      expect(saves, [45]);
    });

    testWidgets('the inline button says what the HOST will do with the tap', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      // `Add` on the form, where the tap only drafts; `Save` on the quantity
      // sheet, where the tap writes.
      await tester.pumpWidget(_host(_shallot));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FButton, 'Add'), findsOneWidget);

      await tester.pumpWidget(_host(_shallot, saveLabel: 'Save'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FButton, 'Save'), findsOneWidget);
    });
  });

  group('the weight takes a unit', () {
    testWidgets('an ounce reaches onSave as grams — the row still stores its '
        'basis', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      final saves = <double>[];
      await tester.pumpWidget(_host(_shallot, saves: saves));
      await tester.pumpAndSettle();

      await pickUnit(
        tester,
        find.byKey(const ValueKey('piece-weight-unit')),
        'oz',
      );
      await tester.enterText(pieceWeightField, '4');
      await tester.pumpAndSettle();
      await tester.tap(_saveButton);
      await tester.pumpAndSettle();

      expect(saves.single, closeTo(4 * 28.349523125, 1e-9));
    });

    testWidgets('the picker offers only what this row can convert — the other '
        'family waits on a density', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_shallot));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('piece-weight-unit')));
      await tester.pumpAndSettle();
      expect(find.text('kg'), findsWidgets);
      expect(
        find.text('cup'),
        findsNothing,
        reason: 'no density on this row — a cup could not become grams',
      );
    });
  });

  group('removing it', () {
    testWidgets('asks first, naming what it costs, and only then reports', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      final removals = <void>[];
      await tester.pumpWidget(_host(_weighedShallot, removals: removals));
      await tester.pumpAndSettle();

      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('remove the piece weight'));
      await tester.pumpAndSettle();

      // The consequence, not "are you sure": `piece` locks again.
      expect(find.textContaining('piece locks again'), findsOneWidget);
      expect(removals, isEmpty, reason: 'asking is not doing');

      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(removals, hasLength(1));
    });

    testWidgets('“keep it” backs out and reports nothing', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      final removals = <void>[];
      await tester.pumpWidget(_host(_weighedShallot, removals: removals));
      await tester.pumpAndSettle();

      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('remove the piece weight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('keep it'));
      await tester.pumpAndSettle();

      expect(removals, isEmpty);
      expect(find.text('remove the piece weight'), findsOneWidget);
    });

    testWidgets('a row with no weight offers no removal at all', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(_host(_shallot));
      await tester.pumpAndSettle();

      expect(find.text('remove the piece weight'), findsNothing);
    });
  });
}
