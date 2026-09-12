/// The macro fields as a **sentence** — `[285.7] kcal · [0] protein · …` —
/// and the one muted line that sits under them on a scan that named no
/// serving.
///
/// The fonts are real here (`loadAnsiFonts`): under the test binding's square
/// fallback face every label measures half again as wide as it draws on a
/// phone, so a run assertion made without them says nothing about the app.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/serving_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fonts.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

/// A bare stub by name — the row a scan lands on.
const _bare = Ingredient(
  id: 'bare',
  canonicalName: 'Hazelnut spread',
  defaultUnit: g,
  status: IngredientStatus.stub,
  source: 'manual',
);

const _macroNames = ['kcal', 'protein', 'carb', 'fat', 'fibre'];

const _nudge =
    'the pack printed it per serving? switch to per serving and type it '
    'as read';

/// The sentence's own container — one [Wrap], keyed so a run assertion cannot
/// wander onto the density sentence's.
final Finder _sentence = find.byKey(const ValueKey('macro-sentence'));

void main() {
  setUpAll(loadAnsiFonts);

  group('the macros are a sentence, not five boxes', () {
    testWidgets('five slots in ONE Wrap, each with its name after it', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: editRoute('mango')),
      );
      await tester.pumpAndSettle();

      expect(_sentence, findsOneWidget);
      for (final name in _macroNames) {
        // The slot and its name are both inside the one Wrap…
        expect(
          find.descendant(of: _sentence, matching: macroField(name)),
          findsOneWidget,
          reason: '$name is not in the sentence',
        );
        final label = find.descendant(of: _sentence, matching: find.text(name));
        expect(label, findsOneWidget, reason: '$name has no name beside it');

        // …the name comes AFTER the number, and shares its run.
        final slot = tester.getRect(macroField(name));
        final caption = tester.getRect(label);
        expect(
          caption.left,
          greaterThanOrEqualTo(slot.right),
          reason: '$name is not after its slot',
        );
        expect(
          caption.top < slot.bottom && slot.top < caption.bottom,
          isTrue,
          reason: '$name broke away from its own number',
        );
      }
    });

    testWidgets('it holds two runs at 402 pt — kcal · protein · carb, then '
        'fat · fibre — and never overflows', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: editRoute('mango')),
      );
      await tester.pumpAndSettle();

      final tops = {
        for (final name in _macroNames)
          name: tester.getRect(macroField(name)).top,
      };
      final runs = tops.values.toSet();
      expect(
        runs.length,
        lessThanOrEqualTo(2),
        reason: 'the sentence should not need a third run: $tops',
      );
      expect(
        tops['kcal'],
        tops['carb'],
        reason: 'kcal · protein · carb share the first run',
      );
      expect(
        tops['fat'],
        tops['fibre'],
        reason: 'fat · fibre share the second',
      );
      expect(tops['fat'], greaterThan(tops['carb']!));

      // Inside the width, not over it.
      final available = tester.getRect(_sentence);
      for (final name in _macroNames) {
        expect(
          tester.getRect(macroField(name)).right,
          lessThanOrEqualTo(available.right),
          reason: '$name overflows the sentence',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a derived panel is SHOWN through the display rule and SAVED '
        'whole — opening a row is not an edit of its macros', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // What a per-serving entry leaves behind: 80 kcal per 28 g, per 100.
      const derived = Macros(
        kcal: 285.7142857142857,
        protein: 0,
        carb: 21.428571428571427,
        fat: 25,
        fiber: 0,
      );
      final repo = FakeIngredientRepo([mango.copyWith(macros: derived)]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      // The fields read like a label, not like a division.
      expect(macroFieldText(tester, 'kcal'), '286');
      expect(macroFieldText(tester, 'carb'), '21');
      expect(macroFieldText(tester, 'fat'), '25');

      await saveForm(tester);
      // …and the row still holds every digit, so the label's own figures
      // reverse out of it exactly.
      expect((await repo.byId('mango'))!.macros, derived);
    });

    testWidgets('the fifth slot still reaches the draft: typing fibre saves '
        'it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      await tester.enterText(macroField('fibre'), '3.4');
      await tester.pump();
      expect(macroFieldText(tester, 'fibre'), '3.4');

      await saveForm(tester);
      expect((await repo.byId('mango'))!.macros!.fiber, 3.4);
    });
  });

  group('a scanned per-100 row that names no serving says per-serving is '
      'there', () {
    testWidgets('the nudge sits under the fields, and goes the moment the '
        'mode moves', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [_bare]),
          at: editRoute('bare'),
          // Nutella: a per-100 g panel, and Open Food Facts holds no serving
          // for it at all — the owner's own scan.
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(_nudge), findsNothing, reason: 'nothing scanned yet');

      await scanOnForm(tester, '3017620422003');
      expect(find.text(_nudge), findsOneWidget);
      // It is the comparison line's slot, and its manners: under the fields,
      // above the next group.
      expect(
        tester.getRect(find.text(_nudge)).top,
        greaterThan(tester.getRect(macroField('fibre')).bottom),
      );
      expect(find.byType(ScannedPerServingNudge), findsOneWidget);

      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      expect(find.text(_nudge), findsNothing);
    });

    testWidgets('one edited figure and it is gone — what is on screen is '
        'yours now', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [_bare]),
          at: editRoute('bare'),
          lookup: lookupAnswering('nutella_per_100g'),
        ),
      );
      await tester.pumpAndSettle();
      await scanOnForm(tester, '3017620422003');
      expect(find.text(_nudge), findsOneWidget);

      await tester.enterText(macroField('kcal'), '540');
      await tester.pump();
      expect(find.text(_nudge), findsNothing);
    });

    testWidgets('a pack that DID print its serving is entered in it — there '
        'is nothing left to advise', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [_bare]),
          at: editRoute('bare'),
          lookup: lookupAnswering('cheddar_shreds_cup_serving_as_ml'),
        ),
      );
      await tester.pumpAndSettle();

      await scanOnForm(tester, '0099482514778');
      expect(find.text(_nudge), findsNothing);
      expect(basisChip(tester, 'per serving').selected, isTrue);
      expect(macroFieldText(tester, 'kcal'), '80');
      // The comparison holds in this mode too: the fields' figures against the
      // pack's own per-100 column.
      expect(find.textContaining('the pack prints'), findsOneWidget);
    });

    testWidgets('a hand-typed row is never nudged — nobody there is reading '
        'a mode they did not choose', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [_bare]), at: editRoute('bare')),
      );
      await tester.pumpAndSettle();

      await typeMacros(
        tester,
        kcal: '539',
        protein: '6.3',
        carb: '57.5',
        fat: '30.9',
      );
      expect(find.text(_nudge), findsNothing);
    });
  });
}
