/// The form's third prefill door: reading the nutrition label off a photo.
///
/// The reader and the photo intake are both faked, so nothing here touches a
/// camera, a cropper or the network. What is under test is the door, what a
/// reading does to the fields, and the tense — nothing is saved until Save,
/// and one tap puts it back.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/data/remote_import_repository.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/label_reading.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/label_read_progress.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// An EU back-of-pack table: a per-100 g column beside a per-30 g one.
const euLabel = LabelReading(
  serving: LabelServing(
    amount: 30,
    unitPrinted: 'g',
    textPrinted: 'per 30 g (1 oatcake)',
  ),
  perServing: LabelMacros(
    kcal: 113,
    protein: 4.1,
    carb: 18.6,
    fat: 1.9,
    fiber: 3.2,
  ),
  per100: LabelPer100(
    basis: MacrosBasis.perG,
    macros: LabelMacros(
      kcal: 377,
      protein: 13.7,
      carb: 62.1,
      fat: 6.2,
      fiber: 10.6,
    ),
  ),
);

/// A US Nutrition Facts panel: one per-serving column and no per-100 one.
const usLabel = LabelReading(
  serving: LabelServing(
    amount: 55,
    unitPrinted: 'g',
    textPrinted: '2/3 cup (55g)',
  ),
  perServing: LabelMacros(kcal: 230, protein: 3, carb: 37, fat: 8, fiber: 4),
);

/// The bare row a label is read onto: named, in an aisle, and missing exactly
/// the figures the panel carries.
const oatcakes = Ingredient(
  id: 'oatcakes',
  canonicalName: 'Oatcakes',
  defaultUnit: g,
  status: IngredientStatus.stub,
  category: 'pantry',
  source: 'manual',
);

void main() {
  group('reading a nutrition label off a photo', () {
    /// Opens the edit form over a reader that answers with [reading], or
    /// throws [fails], and an intake holding one photo.
    Future<(FakeIngredientRepo, FakeLabelReader)> open(
      WidgetTester tester, {
      LabelReading? reading,
      Exception? fails,
      Completer<void>? gate,
    }) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [oatcakes]);
      final reader = FakeLabelReader(
        reading: reading,
        fails: fails,
        gate: gate,
      );
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('oatcakes'),
          labelReader: reader,
          intake: intakeAnswering(['/tmp/label.jpg']),
        ),
      );
      await tester.pumpAndSettle();
      return (repo, reader);
    }

    testWidgets('the door stands in the fill-it-in row, beside the other two', (
      tester,
    ) async {
      await open(tester, reading: usLabel);
      expect(find.text('FILL IT IN FROM'), findsOneWidget);
      expect(find.text('Read a label'), findsOneWidget);
      expect(find.text('Look up in USDA'), findsOneWidget);
    });

    testWidgets(
      'a US panel lands PER SERVING, and the per-100 the row stores is the '
      'serving row’s own arithmetic',
      (tester) async {
        final (repo, reader) = await open(tester, reading: usLabel);
        await readLabelOnForm(tester);

        // The photo the intake produced is what the reader was handed.
        expect(reader.asked, ['/tmp/label.jpg']);
        // One per-serving column, so the form enters per-serving mode and the
        // serving row holds what the label printed.
        expect(find.text('One serving is'), findsOneWidget);
        expect(fieldText(tester, servingAmountField), '55');
        expect(macroFieldText(tester, 'kcal'), '230');
        expect(macroFieldText(tester, 'protein'), '3');
        expect(macroFieldText(tester, 'carb'), '37');
        expect(macroFieldText(tester, 'fat'), '8');
        expect(macroFieldText(tester, 'fibre'), '4');

        // 230 kcal in 55 g is 418.18 per 100 g — derived by the same
        // `Macros.per100From` a typed-in panel goes through, and stored
        // unrounded.
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repo.savedForms, hasLength(1));
        final stored = repo.savedForms.single.row.macros!;
        expect(stored.kcal, closeTo(230 * 100 / 55, 0.001));
        expect(stored.fiber, closeTo(4 * 100 / 55, 0.001));
      },
    );

    testWidgets(
      'an EU label’s own per-100 column is what lands — never a derivation',
      (tester) async {
        final (repo, _) = await open(tester, reading: euLabel);
        await readLabelOnForm(tester);

        // The label's own figures. Deriving 113 kcal over 30 g would have
        // stored 376.67, which is not a number printed anywhere on the pack.
        // The fields round for display from a gram up, as they do for every
        // other source; the draft keeps the label's full figure, which the
        // Save below proves.
        expect(macroFieldText(tester, 'kcal'), '377');
        expect(macroFieldText(tester, 'protein'), '14');
        expect(macroFieldText(tester, 'carb'), '62');
        expect(macroFieldText(tester, 'fat'), '6');
        expect(macroFieldText(tester, 'fibre'), '11');
        // And the form is not in per-serving mode: the column is per 100
        // already.
        expect(find.text('One serving is'), findsNothing);

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(repo.savedForms.single.row.macros!.kcal, 377);
      },
    );

    testWidgets('a figure the label did not print leaves its field alone', (
      tester,
    ) async {
      const noFibre = LabelReading(
        serving: LabelServing(amount: 55, unitPrinted: 'g'),
        perServing: LabelMacros(kcal: 230, protein: 3, carb: 37, fat: 8),
      );
      await open(tester, reading: noFibre);
      // Enter per-serving mode and type the fibre by hand first, so the read
      // has something of the person's to leave alone. Same mode, same basis:
      // the label says nothing about fibre, so it moves nothing.
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.enterText(servingAmountField, '55');
      await tester.pump();
      await tester.enterText(macroField('fibre'), '9');
      await tester.pump();

      await readLabelOnForm(tester);
      expect(macroFieldText(tester, 'kcal'), '230');
      expect(macroFieldText(tester, 'fibre'), '9');
    });

    testWidgets('the fill is a draft: it says so, and one tap puts it back', (
      tester,
    ) async {
      final (repo, _) = await open(tester, reading: euLabel);
      await readLabelOnForm(tester);

      expect(find.text('From a label · not saved'), findsOneWidget);
      expect(
        find.text('read from a photo — check it against the label'),
        findsOneWidget,
      );
      expect(repo.savedForms, isEmpty);

      await tester.tap(find.text('Undo the fill'));
      await tester.pumpAndSettle();
      expect(find.text('From a label · not saved'), findsNothing);
      expect(macroFieldText(tester, 'kcal'), isEmpty);
      expect(repo.savedForms, isEmpty);
    });

    testWidgets('Save is what stores it, stamped as a label photo', (
      tester,
    ) async {
      final (repo, _) = await open(tester, reading: euLabel);
      await readLabelOnForm(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final edit = repo.savedForms.single.row;
      expect(edit.source, labelPhotoSource);
      // A photo names no food — the person had already named the row — so
      // there is no label and no fit score to record.
      expect(edit.sourceLabel, isNull);
      expect(edit.sourceScore, isNull);
      expect(edit.macros?.fiber, 10.6);
    });

    testWidgets('a read that fails says so on the form and changes nothing', (
      tester,
    ) async {
      await open(
        tester,
        fails: const ImportException('that photo is too dark to read'),
      );
      await readLabelOnForm(tester);

      expect(find.text('that photo is too dark to read'), findsOneWidget);
      expect(find.text('From a label · not saved'), findsNothing);
      expect(macroFieldText(tester, 'kcal'), isEmpty);
    });

    testWidgets('what could not be read is said out loud, not hidden', (
      tester,
    ) async {
      const partial = LabelReading(
        serving: LabelServing(amount: 30, unitPrinted: 'g'),
        perServing: LabelMacros(kcal: 113, protein: 4.1, carb: 18.6, fat: 1.9),
        notes: ['The fibre row was cut off at the edge of the photo.'],
      );
      await open(tester, reading: partial);
      await readLabelOnForm(tester);
      expect(find.textContaining('The fibre row was cut off'), findsOneWidget);
    });

    testWidgets('while the label is read, the reading screen covers the form '
        'and takes its taps', (tester) async {
      final gate = Completer<void>();
      await open(tester, reading: usLabel, gate: gate);
      await tester.tap(find.text('Read a label'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take a photo'));
      // The spinner never settles while the read is in flight.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The import's own checklist row, not a line on the dock.
      expect(find.byType(LabelReadProgress), findsOneWidget);
      expect(find.text('Reading the label…'), findsOneWidget);
      // The dock is gone, so there is no Save to press mid-read.
      expect(find.byKey(kFormSaveKey), findsNothing);
      // The screen is opaque to taps, so nothing under it can be edited.
      expect(
        tester
            .widget<AbsorbPointer>(
              find.descendant(
                of: find.byType(LabelReadProgress),
                matching: find.byType(AbsorbPointer),
              ),
            )
            .absorbing,
        isTrue,
      );

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LabelReadProgress), findsNothing);
      expect(find.byKey(kFormSaveKey), findsOneWidget);
      expect(macroFieldText(tester, 'kcal'), '230');
    });

    testWidgets('the dock says no word about the photo, and why Save is '
        'refused is never hidden', (tester) async {
      // A panel with fat cut off: three of four figures, which the form
      // refuses rather than zero-filling.
      const threeOfFour = LabelReading(
        serving: LabelServing(amount: 55, unitPrinted: 'g'),
        perServing: LabelMacros(kcal: 230, protein: 3, carb: 37),
        notes: ['The fat row was cut off at the edge of the photo.'],
      );
      await open(tester, reading: threeOfFour);
      await readLabelOnForm(tester);

      expect(find.textContaining('Read from a photo'), findsNothing);
      expect(
        find.textContaining('Enter all four macros, or leave them all blank'),
        findsOneWidget,
      );
      // What could not be read is on the label's card, not on the dock.
      expect(find.textContaining('The fat row was cut off'), findsOneWidget);
    });

    testWidgets('a serving line that weighs a spoon lands the density with '
        'the figures — no Add to tap', (tester) async {
      final (repo, _) = await open(tester, reading: usLabel);
      await readLabelOnForm(tester);

      // Held by the draft and headlined as the pack said it, with the g/ml
      // derived from it beside.
      expect(find.text('⅔ cup weighs 55 g · 0.349 g/ml'), findsOneWidget);
      expect(
        find.text(
          'both halves come from the pack’s serving line — check them '
          'against it',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      final edit = repo.savedForms.single;
      expect(
        (edit.density as DensitySet).gPerMl,
        closeTo(55 / (236.5882365 * 2 / 3), 1e-9),
      );
      expect(edit.row.macros!.kcal, closeTo(230 * 100 / 55, 0.001));
    });
  });
}
