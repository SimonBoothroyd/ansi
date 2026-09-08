/// The macros section's per-serving mode (plan 0027 front M): a US label is
/// entered per serving and stored per 100 g, and a barcode's own serving
/// panel lands on the same selector.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:convert';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart';
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
        'weight', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();

      // Nobody who never taps the segment sees anything new.
      expect(find.text('One serving is'), findsNothing);
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      expect(find.text('One serving is'), findsOneWidget);
      expect(
        find.text('type the serving weight from the pack'),
        findsOneWidget,
      );

      await typeMacros(tester, kcal: '100', protein: '0', carb: '0', fat: '11');
      // The four are in, the serving is not: the preview says what it needs
      // and Save refuses rather than dividing by a blank.
      expect(
        find.textContaining('stored per 100 g: needs the serving weight'),
        findsOneWidget,
      );
      await saveForm(tester);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);
      expect((await repo.byId('spread'))!.macros, isNull);

      await tester.enterText(servingAmountField, '14');
      await tester.pumpAndSettle();
      // The derivation, before Save, in the person's sight (invariant 3).
      expect(
        find.textContaining('stored per 100 g: 714 kcal · 0P 79F 0C'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'from a 14 g serving — the label’s rounding scales with it',
        ),
        findsOneWidget,
      );

      await saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      // Per 100, unrounded (M-D3); the printed four are nowhere on the row.
      expect(saved.macros!.kcal, closeTo(714.2857, 0.0001));
      expect(saved.macros!.fat, closeTo(78.5714, 0.0001));
      expect(saved.macros!.protein, 0);
      expect(saved.macrosBasis, MacrosBasis.perG);
      // A label fills fields; confirming stays a human act (plan 0020 D5).
      expect(saved.status, IngredientStatus.stub);
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets('the serving unit is the basis: an ml serving stores per 100 '
        'ml', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await tester.pumpWidget(host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      // The `ml` chip inside the serving row — the admission chips carry one
      // too, so scope it.
      await tester.tap(
        find.descendant(
          of: find.byType(ServingRow),
          matching: find.widgetWithText(AnsiModeChip, 'ml'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(servingAmountField, '240');
      await typeMacros(tester, kcal: '120', protein: '8', carb: '12', fat: '5');
      await tester.pumpAndSettle();
      expect(find.textContaining('stored per 100 ml: 50 kcal'), findsOneWidget);

      // The basis moved under the default unit, so `g` is no longer sayable
      // on this row (D4c) — and Save says so rather than writing a row that
      // cannot say its own default. The one-tap fix IS the save.
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
      expect(saved.macros!.kcal, 50);
      expect(saved.defaultUnit, ml);
    });

    /// The shared setup for the two M-D2 legs: a bare per-100 g stub, put
    /// into per-serving mode with a 14 g "1 tbsp" serving and a label's four.
    Future<Finder> armTheOffer(
      WidgetTester tester,
      FakeIngredientRepo repo,
    ) async {
      await tester.pumpWidget(host(repo, at: '/ingredients/spread'));
      await tester.pumpAndSettle();
      expect(lockedUnitLabels(tester), containsAll(['tbsp', 'ml']));

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.enterText(servingAmountField, '14');
      await tester.enterText(servingNameField, '1 tbsp');
      await typeMacros(tester, kcal: '100', protein: '0', carb: '0', fat: '11');
      await tester.pumpAndSettle();

      expect(find.text('THIS SERVING ALSO SAYS'), findsOneWidget);
      final tick = find.byKey(const ValueKey('serving-offer'));
      expect(find.text('1 tbsp weighs 14 g — set as density'), findsOneWidget);
      expect(tester.widget<FCheckbox>(tick).value, isFalse);
      return tick;
    }

    testWidgets('the offer is OFF by default — an untouched Save writes the '
        'macros and NOTHING else', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      await armTheOffer(tester, repo);

      await saveForm(tester);
      final saved = (await repo.byId('spread'))!;
      expect(saved.macros, isNotNull);
      // The whole point: a pack's "about 1 tbsp" is sometimes a guess, and a
      // density minted from a guess would decide what units the row admits.
      expect(saved.densityGPerMl, isNull);
    });

    testWidgets(
      'ticked, the same Save lands it through setDensity and the volume chips '
      'unlock',
      (tester) async {
        filterForuiSemanticsAssertions();
        tallScreen(tester);
        final repo = FakeIngredientRepo(const [spread]);
        final tick = await armTheOffer(tester, repo);

        await tester.tap(tick);
        await tester.pumpAndSettle();
        expect(tester.widget<FCheckbox>(tick).value, isTrue);
        expect(find.textContaining('= 0.947 g/ml'), findsOneWidget);

        // One Save: the macros through the row's own write, the density through
        // density entry's own spoon arithmetic (ADR-0008 §2), and ADR-0009's
        // unlock. Save ends the page, so we walk back in to read the chips.
        await saveForm(tester, reopen: 'Buttery spread');
        final saved = (await repo.byId('spread'))!;
        expect(saved.densityGPerMl, closeTo(14 / tbsp.ratioToBase!, 1e-9));
        expect(lockedUnitLabels(tester), isNot(contains('tbsp')));
        expect(lockedUnitLabels(tester), isNot(contains('ml')));
        expect(find.textContaining('0.947 g/ml'), findsWidgets);
        // Landed, and it cannot be written twice: the reopened form reads the
        // row's own per-100 macros, so there is no serving and no offer at all.
        expect(find.text('THIS SERVING ALSO SAYS'), findsNothing);
      },
    );

    testWidgets('a serving that names a thing — “1 slice = 28 g” — is offered '
        'as a measure, through the measures editor’s write', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [spread]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: '/ingredients/spread', measures: measures),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await tester.enterText(servingAmountField, '28');
      await tester.enterText(servingNameField, '1 slice');
      await typeMacros(tester, kcal: '80', protein: '3', carb: '14', fat: '1');
      await tester.pumpAndSettle();

      expect(find.text('1 slice = 28 g — add as a measure'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('serving-offer')));
      await tester.pumpAndSettle();
      expect(measures.rows, isEmpty, reason: 'a tick writes nothing yet');

      await saveForm(tester);
      // The offer rides the form's ONE write now, so what it asked for is
      // where the assertion lives (plan 0029 W3).
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'slice');
      expect(asked.measuresAdded.single.amount, 28);
      expect((await repo.byId('spread'))!.macros!.kcal, closeTo(285.71, 0.01));
      // No density from a slice — that offer is a spoon's alone.
      expect(asked.density, isA<DensityUnchanged>());
      expect((await repo.byId('spread'))!.densityGPerMl, isNull);
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
          at: '/ingredients/bare',
          lookup: lookupAnswering(offFixture('peanut_butter_per_serving')),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester);

      expect(find.text('One serving is'), findsOneWidget);
      expect(fieldText(tester, servingAmountField), '32');
      expect(fieldText(tester, servingNameField), '2 Tbsp');
      expect(macroFieldText(tester, 'kcal'), '180');
      expect(macroFieldText(tester, 'fat'), '14');
      expect(
        find.textContaining('stored per 100 g: 563 kcal · 19P 44F 31C'),
        findsOneWidget,
      );
      // The card says what it read, and the M-D2 offer reads the pack's own
      // "2 Tbsp (32 g)" as a spoon.
      expect(
        find.textContaining('panel read per serving of 32 g'),
        findsOneWidget,
      );
      expect(find.text('1 tbsp weighs 16 g — set as density'), findsOneWidget);
      // Nothing written until Save.
      expect((await repo.byId('bare'))!.macros, isNull);

      await saveForm(tester);
      final saved = (await repo.byId('bare'))!;
      expect(saved.macros!.kcal, 562.5);
      expect(saved.macros!.protein, 18.75);
      expect(saved.macrosBasis, MacrosBasis.perG);
      expect(saved.source, 'off:0851087000250');
      expect(saved.status, IngredientStatus.stub);
      expect(saved.densityGPerMl, isNull, reason: 'the offer was not taken');
    });

    testWidgets('on the form, no numeric serving: the amount is empty and '
        'flagged with the pack’s words, never parsed out of them', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [bare]);
      await tester.pumpWidget(
        host(
          repo,
          at: '/ingredients/bare',
          lookup: lookupAnswering(withoutServingQuantity()),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester);

      expect(fieldText(tester, servingAmountField), isEmpty);
      expect(
        find.text('the pack says “2 Tbsp (32 g)” — type the serving weight'),
        findsOneWidget,
      );
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
        find.textContaining('stored per 100 g: 563 kcal · 19P 44F 31C'),
        findsOneWidget,
      );

      await saveForm(tester);

      final created = repo.rows.single;
      expect(created.macros!.kcal, 562.5);
      expect(created.macros!.carb, 31.25);
      expect(created.macrosBasis, MacrosBasis.perG);
      expect(created.source, 'off:0851087000250');
      expect(created.status, IngredientStatus.stub);
    });

    testWidgets('creating by barcode, no numeric serving: flagged, and no '
        'panel is stored unless the weight is typed', (tester) async {
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

      // Without the weight there is nothing to divide by, so Save REFUSES
      // and says which number is missing — the sheet used to warn about it
      // in advance, and the form's own guard is the better place for it:
      // it cannot be ignored, and it names the field.
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty);
      expect(find.textContaining('One serving is how much?'), findsOneWidget);

      await tester.enterText(servingAmountField, '32');
      await tester.pumpAndSettle();

      await saveForm(tester);
      expect(repo.rows.single.macros!.kcal, 562.5);
    });
  });
}
