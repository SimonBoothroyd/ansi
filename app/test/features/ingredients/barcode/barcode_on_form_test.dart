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
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

    OffLookup lookupAnswering(String fixture) => OffLookup(
      client: MockClient((_) async => http.Response(offFixture(fixture), 200)),
    );

    /// Opens the form's scan surface and types [barcode] in.
    Future<void> scanOnForm(WidgetTester tester, String barcode) async {
      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, barcode);
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();
    }

    testWidgets('fills the EMPTY macro fields, keeps the name and a USDA '
        'provenance — and writes nothing until Save', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(
        host(
          repo,
          at: '/ingredients/curry',
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
      expect(macroFieldText(tester, 'fat'), '30.9');
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

    testWidgets('on a row with no source, Save stamps off:<barcode> in the '
        'same write as the macros', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: '/ingredients/bare',
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
      expect(saved.macros!.kcal, 539);
      expect(saved.status, IngredientStatus.stub);
    });

    testWidgets('a panel already typed is not overwritten, and the card says '
        'so', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: '/ingredients/bare',
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
          at: '/ingredients/bare',
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
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Scan a barcode'), findsNothing);
    });
  });
}
