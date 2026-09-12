/// The form's own barcode scan (plan 0025 #8): a scan prefills a DRAFT and
/// never completes a row on its own — provenance and ODbL credit carried, a
/// panel-less product left blank with the reason, and a dismissed scan
/// changing nothing.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../../helpers/fake_ingredient_repository.dart';
import '../../../helpers/fake_measure_repository.dart';
import '../../../helpers/forui_semantics.dart';
import '../_form_harness.dart';

void main() {
  group('the form scans a barcode into itself', () {
    /// A bare stub created by name — no numbers, `manual` provenance: the
    /// row the picker's add-new chain lands on the form.
    const bare = Ingredient(
      id: 'bare',
      canonicalName: 'Hazelnut spread',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    testWidgets('fills the EMPTY macro fields, keeps the name and a USDA '
        'provenance — and writes nothing until Save', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('curry'),
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3017620422003');

      // The card, with what it left alone named on it.
      expect(find.text('FOUND · OPEN FOOD FACTS'), findsOneWidget);
      expect(
        find.textContaining('kept: the name — yours stays'),
        findsOneWidget,
      );
      expect(
        find.textContaining('the provenance — this row already names a source'),
        findsOneWidget,
      );
      // The panel reached the FIELDS (the G1 lesson), the name did not move.
      expect(macroFieldText(tester, 'kcal'), '539');
      expect(macroFieldText(tester, 'fat'), '31');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curry leaves, fresh',
      );
      // Nothing has been written.
      expect((await repo.byId('curry'))!.macros, isNull);
      expect(find.textContaining('filled in, not saved'), findsOneWidget);

      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      final saved = (await repo.byId('curry'))!;
      expect(saved.macros!.kcal, 539);
      expect(saved.macrosBasis, MacrosBasis.perG);
      expect(saved.source, 'usda_fdc:11216', reason: 'a source stays');
      // A scan prefills and never completes (D1/D5).
      expect(saved.status, IngredientStatus.stub);
    });

    testWidgets('THE OAT MILK: a label printed per 100 ml lands on the ml '
        'chip, and nothing pretends to know what it weighs', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // The owner's own scan. Open Food Facts files this carton's per-100 ml
      // panel under `nutrition_data_per: "100g"` — the field's default, not a
      // statement — so the macros used to arrive as grams.
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering('oat_milk_ml_label_as_100g'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '0850032825009');

      expect(basisChip(tester, 'per 100 ml').selected, isTrue);
      expect(basisChip(tester, 'per 100 g').selected, isFalse);
      expect(macroFieldText(tester, 'kcal'), '47');

      // Nothing pretends to know what a millilitre of it weighs, so the `g`
      // default the stub was born with is now stranded — named on the line
      // under the chips, and refused at Save. A density minted to paper over
      // it is exactly what invariant 3 forbids.
      expect(
        find.textContaining('g needs a density on this row'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      expect((await repo.byId('bare'))!.macros, isNull);

      // The one-tap fix takes it, and the same Save lands.
      await tester.tap(find.text('switch to ml'));
      await tester.pumpAndSettle();

      final saved = (await repo.byId('bare'))!;
      expect(saved.macrosBasis, MacrosBasis.perMl);
      expect(saved.macros!.kcal, 46.511627906977);
      expect(saved.defaultUnit, ml);
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets('on a row with no source, Save stamps off:<barcode> — and the '
        'pack’s NAME beside it, in the same write as the macros', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3017620422003');
      expect(find.textContaining('the provenance'), findsNothing);
      expect((await repo.byId('bare'))!.source, 'manual');

      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();
      final saved = (await repo.byId('bare'))!;
      expect(saved.source, 'off:3017620422003');
      // The stamp is a key; this is what a person reads. Without it the row
      // could say nothing at all about where its numbers came from.
      expect(saved.sourceLabel, 'Nutella');
      // A scan is an exact fetch, so there is no coverage of the typed name to
      // report and none is invented.
      expect(saved.sourceScore, isNull);
      expect(saved.macros!.kcal, 539);
      expect(saved.status, IngredientStatus.stub);
    });

    testWidgets('the saved row NAMES the pack when the form is opened again — '
        'one line, and no doors: a barcode is not a match to re-choose', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering('nesquik_no_panel'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3033710065967');
      await saveForm(tester, reopen: 'Hazelnut spread');

      expect((await repo.byId('bare'))!.sourceLabel, 'Nestlé NESQUIK Cacao');
      // The head names the basis the four figures are per — the whole trap
      // the mapper exists to avoid, said out loud on the row it landed on.
      expect(
        find.text('Filled from a barcode · per 100 g\nNestlé NESQUIK Cacao'),
        findsOneWidget,
      );
      // The code itself is never printed at anybody.
      expect(find.textContaining('3033710065967'), findsNothing);
      // The USDA card's doors have no counterpart here.
      expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsNothing);
    });

    testWidgets('a panel already typed is not overwritten, and the card says '
        'so', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(macroField('kcal'), '100');
      await tester.pump();

      await scanOnForm(tester, '3017620422003');

      expect(macroFieldText(tester, 'kcal'), '100');
      expect(
        find.textContaining('the macros — the ones already entered stay'),
        findsOneWidget,
      );
    });

    testWidgets('the pack size is an offer: tapped, it becomes a measure in '
        'the row’s basis', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          measures: measures,
          lookup: lookupAnswering('nesquik_no_panel'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '3033710065967');
      // No panel: the fields stay blank with the reason, never zeros.
      expect(macroFieldText(tester, 'kcal'), isEmpty);
      expect(
        find.text('Open Food Facts has no nutrition panel for this product.'),
        findsOneWidget,
      );
      // "1 kg" on a per-100 g row is offered as 1000 g — and only offered.
      final offer = find.text('＋ add “pack” = 1000 g as a measure');
      expect(offer, findsOneWidget);
      expect(measures.rows, isEmpty);

      await tester.tap(offer);
      await tester.pumpAndSettle();
      // In the list at once and in the DRAFT, not the database (plan 0029
      // W5) — which is also what lets a barcode-CREATED row carry its pack
      // size before the row exists at all.
      expect(
        find.descendant(
          of: find.byType(MeasureRow),
          matching: find.text('pack'),
        ),
        findsOneWidget,
      );
      expect(measures.rows, isEmpty);
      expect(offer, findsNothing);
      expect(find.textContaining('pack added below'), findsOneWidget);

      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'pack');
      expect(asked.measuresAdded.single.amount, 1000);
    });

    testWidgets('a confirmed row offers no scan — nothing on it is empty', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: editRoute('mango')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a barcode'), findsNothing);
    });
  });
}
