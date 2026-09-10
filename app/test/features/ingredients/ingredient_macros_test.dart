/// The macros section's per-serving mode: a US label is entered as printed,
/// in any kitchen unit, and the row stores per 100 of whichever basis that
/// unit names — with the derivation shown, never in the fields' place.
///
/// The serving states no density. That is the density section's subject, and
/// the only thing the serving does about it is offer itself as the left-hand
/// side of that sentence.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:convert';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/serving_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

void main() {
  group('the macros section’s per-serving mode', () {
    /// A bare stub by name, per-100 g, no density — the row a US label
    /// lands on. Its volume chips are dashed until a density arrives.
    const spread = Ingredient(
      id: 'spread',
      canonicalName: 'Buttery spread',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    testWidgets('the label typed as printed, the row stored per 100 — '
        'unrounded, previewed live, and refused without the serving '
        'amount', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(host(repo, at: editRoute('spread')));
      await tester.pumpAndSettle();

      // Nobody who never taps the segment sees anything new.
      expect(find.text('One serving is'), findsNothing);
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      expect(find.text('One serving is'), findsOneWidget);
      // The row is an amount and a unit picker, and NOTHING else: the free
      // text beside them is gone, along with everything that was parsed out
      // of it.
      expect(find.byKey(const ValueKey('serving-amount')), findsOneWidget);
      expect(find.byKey(const ValueKey('serving-name')), findsNothing);
      expect(servingUnitSelect, findsOneWidget);

      await typeMacros(tester, kcal: '100', protein: '0', carb: '0', fat: '11');
      // The four are in, the serving is not: the preview says what it needs
      // and Save refuses rather than dividing by a blank.
      expect(
        find.textContaining('stored per 100 g: needs the serving amount'),
        findsOneWidget,
      );
      await saveForm(tester);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);
      expect((await repo.byId('spread'))!.macros, isNull);

      await tester.enterText(servingAmountField, '14');
      await tester.pumpAndSettle();
      // The derivation, before Save, in the person's sight (invariant 3).
      expect(
        find.textContaining('stored per 100 g · 714.3 kcal · 0P 78.6F 0C'),
        findsOneWidget,
      );

      await saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      // Per 100, unrounded; the printed four are nowhere on the row.
      expect(saved.macros!.kcal, closeTo(714.2857, 0.0001));
      expect(saved.macros!.fat, closeTo(78.5714, 0.0001));
      expect(saved.macros!.protein, 0);
      expect(saved.macrosBasis, MacrosBasis.perG);
      // A label fills fields; confirming stays a human act.
      expect(saved.status, IngredientStatus.stub);
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets('the picker offers every kitchen unit, and a volume serving '
        'lands the row per 100 ml through the catalog — no density', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: editRoute('spread'), measures: measures),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.tap(servingUnitSelect);
      await tester.pumpAndSettle();
      // Every mass and volume unit the catalog holds, and nothing else — no
      // `piece`, no `pinch`: a label prints a weight or a measure.
      expect(
        find.byWidgetPredicate((w) => w is FSelectItem<Unit>),
        findsNWidgets(kServingUnits.length),
      );
      for (final u in kServingUnits) {
        expect(servingUnitOption(u), findsOneWidget, reason: u.id);
      }
      for (final u in [pieces, pinch, batches]) {
        expect(servingUnitOption(u), findsNothing, reason: u.id);
      }
      await tester.ensureVisible(servingUnitOption(cup));
      await tester.pumpAndSettle();
      await tester.tap(servingUnitOption(cup));
      await tester.pumpAndSettle();

      await tester.enterText(servingAmountField, '1');
      await typeMacros(tester, kcal: '110', protein: '1', carb: '17', fat: '5');
      await tester.pumpAndSettle();

      // 1 cup is 236.59 ml by the catalog. Nothing weighs it, and the line
      // says which conversion it took.
      expect(
        find.textContaining('stored per 100 ml · 46.5 kcal'),
        findsOneWidget,
      );
      expect(find.textContaining('from 1 cup = 236.59 ml'), findsOneWidget);

      // The basis moved under the default unit, so `g` is no longer sayable
      // on this row (D4c) — the one-tap fix IS the save.
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('can’t have g as the default unit'),
        findsOneWidget,
      );
      await tester.tap(find.text('switch to ml'));
      await tester.pumpAndSettle();

      final saved = (await repo.byId('spread'))!;
      expect(saved.macrosBasis, MacrosBasis.perMl);
      expect(saved.macros!.kcal, closeTo(110 / 236.5882365 * 100, 1e-9));
      expect(saved.defaultUnit, ml);
      // A volume serving is not a density: the row still states none.
      expect(saved.densityGPerMl, isNull);
      // And the serving is kept as ONE measure, so the label's own line can
      // be printed back.
      final asked = repo.savedForms.last;
      expect(asked.serving!.label, 'serving · 1 cup');
      expect(asked.serving!.amount, closeTo(236.5882365, 1e-9));
    });

    testWidgets('switching to per serving CLEARS the four fields, and '
        'switching back fills them with the derivation', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(host(repo, at: editRoute('spread')));
      await tester.pumpAndSettle();

      await typeMacros(tester, kcal: '60', protein: '1', carb: '15', fat: '0');
      await tester.pumpAndSettle();
      expect(macroFieldText(tester, 'kcal'), '60');

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      // They were per 100; carrying them into fields that mean per serving is
      // how a right number becomes a wrong one.
      expect(macroFieldText(tester, 'kcal'), isEmpty);

      await tester.enterText(servingAmountField, '50');
      await typeMacros(tester, kcal: '30', protein: '1', carb: '7', fat: '0');
      await tester.pumpAndSettle();
      await tester.tap(find.text('per 100 g'));
      await tester.pumpAndSettle();
      expect(macroFieldText(tester, 'kcal'), '60');
    });

    testWidgets('a volume serving prefills the DENSITY sentence — the one '
        'place a density is stated', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(host(repo, at: editRoute('spread')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await pickServingUnit(tester, tbsp);
      await tester.enterText(servingAmountField, '2');
      await typeMacros(tester, kcal: '190', protein: '7', carb: '7', fat: '16');
      await tester.pumpAndSettle();

      // The serving row makes no offer of its own any more.
      expect(find.text('THIS SERVING ALSO SAYS'), findsNothing);
      // The density sentence takes the serving as its left-hand side and asks
      // only for the weight.
      expect(fieldText(tester, densityAmountField), '2');
      expect(
        find.text('the serving you typed above · the pack’s “(32g)” goes here'),
        findsOneWidget,
      );

      await tester.enterText(densityField, '32');
      await tester.pumpAndSettle();
      // 32 g per 2 tbsp is 1.08 g/ml — the amount is in the arithmetic, not
      // halved in somebody's head.
      expect(find.text('= 1.08 g/ml'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Add').first);
      await tester.pumpAndSettle();

      await saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      expect(saved.densityGPerMl, closeTo(16 / tbsp.ratioToBase!, 1e-9));
    });
  });

  group('a per-serving barcode panel lands on the selector', () {
    const bare = Ingredient(
      id: 'bare',
      canonicalName: 'Peanut butter',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    OffLookup lookupAnswering(String body) =>
        OffLookup(client: MockClient((_) async => http.Response(body, 200)));

    /// The peanut-butter fixture with OFF's numeric serving removed — the
    /// pack whose serving is prose only.
    String withoutServingQuantity() {
      final body =
          jsonDecode(offFixture('peanut_butter_per_serving'))
              as Map<String, Object?>;
      (body['product']! as Map<String, Object?>)
        ..remove('serving_quantity')
        ..remove('serving_quantity_unit');
      return jsonEncode(body);
    }

    Future<void> scanOnForm(WidgetTester tester) async {
      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, '0851087000250');
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();
    }

    testWidgets('on the form: per-serving mode opens, the four as printed, the '
        'serving prefilled from serving_quantity — and Save stores per '
        '100', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering(offFixture('peanut_butter_per_serving')),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester);

      expect(find.text('One serving is'), findsOneWidget);
      expect(fieldText(tester, servingAmountField), '32');
      expect(macroFieldText(tester, 'kcal'), '180');
      expect(macroFieldText(tester, 'fat'), '14');
      expect(
        find.textContaining('stored per 100 g · 562.5 kcal · 18.8P 43.8F'),
        findsOneWidget,
      );
      // The card says what it read.
      expect(
        find.textContaining('panel read per serving of 32 g'),
        findsOneWidget,
      );
      // Nothing written until Save.
      expect((await repo.byId('bare'))!.macros, isNull);

      await saveForm(tester);
      final saved = (await repo.byId('bare'))!;
      expect(saved.macros!.kcal, 562.5);
      expect(saved.macros!.protein, 18.75);
      expect(saved.macrosBasis, MacrosBasis.perG);
      expect(saved.source, 'off:0851087000250');
      expect(saved.status, IngredientStatus.stub);
      // A gram serving says nothing about density — nothing here does.
      expect(saved.densityGPerMl, isNull);
      expect(repo.savedForms.single.serving!.label, 'serving · 32 g');
    });

    testWidgets('on the form, no numeric serving: the amount is empty, and no '
        'panel is stored until it is typed', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: lookupAnswering(withoutServingQuantity()),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester);

      expect(fieldText(tester, servingAmountField), isEmpty);
      expect(macroFieldText(tester, 'kcal'), '180');
      await saveForm(tester);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);
      expect((await repo.byId('bare'))!.macros, isNull);

      await tester.enterText(servingAmountField, '32');
      await tester.pumpAndSettle();
      await saveForm(tester);
      expect((await repo.byId('bare'))!.macros!.kcal, 562.5);
    });

    testWidgets('creating by barcode: the serving row under the card, '
        'prefilled — and Save stores the per-100 derivation', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(
        addHost(repo, body: offFixture('peanut_butter_per_serving')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, '0851087000250');
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(find.text('180 kcal · 6P 14F 10C'), findsOneWidget);
      expect(
        find.textContaining('panel read per serving of 32 g (“2 Tbsp (32 g)”)'),
        findsOneWidget,
      );
      expect(fieldText(tester, servingAmountField), '32');
      expect(
        find.textContaining('stored per 100 g · 562.5 kcal'),
        findsOneWidget,
      );

      await saveForm(tester);

      final created = repo.rows.single;
      expect(created.macros!.kcal, 562.5);
      expect(created.macros!.carb, 31.25);
      expect(created.macrosBasis, MacrosBasis.perG);
      expect(created.source, 'off:0851087000250');
      // A new row is saved COMPLETE or not at all: the scan filled in the one
      // thing the gate asks for, so the single Save counts it in.
      expect(created.status, IngredientStatus.complete);
    });

    testWidgets('creating by barcode, no numeric serving: no panel is stored '
        'unless the amount is typed', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(addHost(repo, body: withoutServingQuantity()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, '0851087000250');
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(fieldText(tester, servingAmountField), isEmpty);

      // Without the amount there is nothing to divide by, so a new row cannot
      // be saved at all — the dock's one button is dark and the line above it
      // names the number that is missing, before anything is tapped.
      expect(tester.widget<FButton>(find.byKey(kFormSaveKey)).onPress, isNull);
      expect(repo.rows, isEmpty);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);

      await tester.enterText(servingAmountField, '32');
      await tester.pumpAndSettle();

      await saveForm(tester);
      expect(repo.rows.single.macros!.kcal, 562.5);
    });
  });

  group('a scanned per-100 panel that also names its serving', () {
    const bare = Ingredient(
      id: 'bare',
      canonicalName: 'Cheddar shreds',
      defaultUnit: g,
      status: IngredientStatus.stub,
      source: 'manual',
    );

    testWidgets('the cheddar shreds: per 100 g in the fields, the pack’s own '
        'line checked against them, and the serving kept as a measure', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: OffLookup(
            client: MockClient(
              (_) async => http.Response(
                offFixture('cheddar_shreds_cup_serving_as_ml'),
                200,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, '0099482514778');
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      // The panel is per 100, so there is no reason to reach for per serving.
      expect(find.text('One serving is'), findsNothing);
      expect(macroFieldText(tester, 'kcal'), '285.714285714286');
      // Both readings are the pack's, and they agree.
      expect(
        find.textContaining(
          'the pack prints 80 kcal per 0.25 cup (28 g) · that is 285.7 per '
          '100 g — these agree',
        ),
        findsOneWidget,
      );

      await saveForm(tester);
      // A quarter-cup on a per-100 g row would need a density the pack does
      // not carry, so the serving kept is the bracket the label printed for
      // exactly this purpose.
      expect(repo.savedForms.single.serving!.label, 'serving · 28 g');
      expect(repo.savedForms.single.serving!.amount, 28);
    });

    testWidgets('the oat milk: per 100 ml, and no serving is invented', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: editRoute('bare'),
          lookup: OffLookup(
            client: MockClient(
              (_) async =>
                  http.Response(offFixture('oat_milk_ml_label_as_100g'), 200),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan a barcode'));
      await tester.pumpAndSettle();
      await tester.enterText(scanField, '0850032825009');
      await tester.pump();
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(macroFieldText(tester, 'kcal'), '46.511627906977');
      expect(basisChip(tester, 'per 100 ml').selected, isTrue);
      // The carton names no serving, so nothing here says one.
      expect(find.textContaining('the pack prints'), findsNothing);

      await tester.tap(find.text('switch to ml'));
      await tester.pumpAndSettle();
      expect(repo.savedForms.single.serving, isNull);
    });
  });
}
