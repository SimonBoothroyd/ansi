/// The USDA match as the form carries it (plan 0027 front U, "The USDA match"
/// frames a–d): named at the head of the macros section with its band word,
/// with both doors beside it — confirm what came back, or refuse the food and
/// keep the row.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/forui_semantics.dart';
import '_form_harness.dart';

void main() {
  testWidgets(
    'a machine prefill is NAMED at the head of the macros section — the food, '
    'its FDC id, the band word — reads not confirmed, and offers both doors',
    (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: '/ingredients/curry'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
      expect(
        find.text(
          'Curry leaves, raw · FDC 11216 · matches every word of “Curry '
          'leaves, fresh”',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      // The old lookup button has no job on a row USDA already filled: the
      // doors are how the match changes.
      expect(find.text('Look up in USDA'), findsNothing);
      // D5 still: the status line says what a stub costs.
      expect(find.textContaining('Still a stub'), findsOneWidget);
    },
  );

  testWidgets('a pick covering only part of the name says so; a row filled '
      'before the match was named carries the id alone', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([curryLeaves.copyWith(sourceScore: 0.62)]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('matches only part of “Curry leaves, fresh”'),
      findsOneWidget,
    );

    // A legacy stamp with no label and no score: honest, not invented.
    await tester.pumpWidget(
      host(
        FakeIngredientRepo(const [
          Ingredient(
            id: 'old',
            canonicalName: 'Old prefill',
            defaultUnit: g,
            status: IngredientStatus.stub,
            source: 'usda_fdc:171705',
          ),
        ]),
        at: '/ingredients/old',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('FDC 171705'), findsOneWidget);
    // No band word invented for a score the row never carried.
    expect(find.textContaining('for “Old prefill”'), findsNothing);
  });

  testWidgets('a CONFIRMED prefill still names its match, and says confirmed', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      curryLeaves.copyWith(
        status: IngredientStatus.complete,
        macros: usdaAnswer.macros,
      ),
    ]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
    await tester.pumpAndSettle();
    expect(find.text('Filled from USDA · confirmed'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
  });

  testWidgets(
    'a DECLINED row names the food it refused, says the numbers were cleared, '
    'offers Choose another alone, and warns that a rename will not refill it',
    (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo([
        curryLeaves.copyWith(source: usdaDeclinedSource),
      ]);
      await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
      await tester.pumpAndSettle();
      expect(find.text('USDA · declined'), findsOneWidget);
      expect(
        find.text(
          'Curry leaves, raw — not this food · the filled numbers were '
          'cleared',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      expect(
        find.text('renaming this row will not refill it — you said no once'),
        findsOneWidget,
      );
      expect(find.text('Look up in USDA'), findsNothing);
    },
  );

  testWidgets('tapping Not this food clears the prefilled numbers from the row '
      'AND the open form, and the line turns into the declined '
      'one', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      curryLeaves.copyWith(
        densityGPerMl: usdaAnswer.densityGPerMl,
        macros: usdaAnswer.macros,
        allowedUnits: const [g, kg, tsp, tbsp, cup, ml],
      ),
    ]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
    await tester.pumpAndSettle();
    expect(macroFieldText(tester, 'kcal'), '108');
    // A pending edit in a field the undo has no business with.
    await tester.enterText(measureLabelField, 'small bunch');
    await tester.pump();

    await tester.tap(find.widgetWithText(FButton, 'Not this food'));
    await tester.pumpAndSettle();

    final row = (await repo.byId('curry'))!;
    expect(row.source, usdaDeclinedSource);
    expect(row.densityGPerMl, isNull);
    expect(row.macros, isNull);
    expect(row.sourceLabel, 'Curry leaves, raw');
    expect(row.status, IngredientStatus.stub);
    // D4b on screen: the volume family the density alone admitted is out.
    expect(row.allowedUnits!.map((u) => u.id).toSet(), {'g', 'kg'});
    // The form followed the row (G1): four blank fields, not stale numbers
    // a Save would write straight back.
    expect(macroFieldText(tester, 'kcal'), isEmpty);
    expect(macroFieldText(tester, 'fat'), isEmpty);
    expect(
      tester.widget<TextField>(measureLabelField).controller!.text,
      'small bunch',
    );
    expect(find.text('USDA · declined'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
    expect(
      find.textContaining('a rename will not bring them back'),
      findsOneWidget,
    );
  });

  testWidgets('Choose another asks for FIVE under the name in the FIELD — '
      'writing nothing to get there — lists them with their band word (the '
      'current match tagged, a nameless one left out), and a pick replaces the '
      'fill through the explicit apply', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      curryLeaves.copyWith(
        densityGPerMl: usdaAnswer.densityGPerMl,
        macros: usdaAnswer.macros,
      ),
    ]);
    final probe = RecordingProbe.list(const [
      usdaAnswer, // the current match, 11216
      UsdaCandidate(
        fdcId: 11217,
        description: 'Curry leaves, dried',
        category: 'Spices and Herbs',
        source: 'usda_fdc:11217',
        score: 1,
        macros: Macros(kcal: 300, protein: 12, carb: 60, fat: 5),
      ),
      UsdaCandidate(
        fdcId: 11218,
        description: 'Curry powder',
        source: 'usda_fdc:11218',
        score: 0.55,
        densityGPerMl: 0.5,
      ),
      UsdaCandidate(
        fdcId: 11219,
        description: 'Curry, nameless',
        source: 'usda_fdc:11219',
        score: 0.52,
      ),
    ]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry', probe: probe));
    await tester.pumpAndSettle();

    // A rename typed and not saved: the sheet must ask about THIS name.
    await tester.enterText(find.byType(TextField).first, 'Curry leaf');
    await tester.pump();
    await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
    await tester.pumpAndSettle();

    expect(probe.asked.single, normalizeMatchText('Curry leaf'));
    expect(probe.limits.single, 5);
    expect(find.text('USDA · for “Curry leaf”'), findsOneWidget);
    expect(find.text('Curry leaves, raw'), findsWidgets);
    expect(find.text('current'), findsOneWidget);
    expect(find.text('Curry leaves, dried'), findsOneWidget);
    expect(find.text('Spices and Herbs'), findsOneWidget);
    expect(find.text('all words'), findsOneWidget);
    expect(find.text('Curry powder'), findsOneWidget);
    expect(find.text('some words'), findsOneWidget);
    // Nothing to copy, nothing to pick.
    expect(find.text('Curry, nameless'), findsNothing);

    await tester.tap(find.text('Curry leaves, dried'));
    await tester.pumpAndSettle();

    // The pick is the DRAFT (plan 0029 W5) — it fills the fields and the
    // provenance it will stamp, and the form's one Save lands all of it.
    await saveForm(tester, reopen: 'Curry leaf');
    final row = (await repo.byId('curry'))!;
    // Looking something up wrote nothing (F1 is retired) — and the Save
    // that follows carries the rename and the pick together, because to
    // the person they were always one act.
    expect(row.canonicalName, 'Curry leaf');
    expect(row.source, 'usda_fdc:11217');
    expect(row.sourceLabel, 'Curry leaves, dried');
    expect(row.sourceScore, 1);
    expect(row.macros!.kcal, 300);
    expect(row.densityGPerMl, isNull); // the old fill is replaced whole
    expect(row.status, IngredientStatus.stub);
    // The form followed: the line names the new food, the fields carry
    // its numbers.
    expect(
      find.textContaining(
        'Curry leaves, dried · FDC 11217 · matches every word',
      ),
      findsOneWidget,
    );
    expect(macroFieldText(tester, 'kcal'), '300');
  });

  testWidgets('on a DECLINED row the refused food is tagged and the pick lands '
      'despite the decline — a person’s own choice', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      curryLeaves.copyWith(source: usdaDeclinedSource),
    ]);
    final probe = RecordingProbe.list(const [
      usdaAnswer,
      UsdaCandidate(
        fdcId: 11217,
        description: 'Curry leaves, dried',
        source: 'usda_fdc:11217',
        score: 1,
        macros: Macros(kcal: 300, protein: 12, carb: 60, fat: 5),
      ),
    ]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry', probe: probe));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
    await tester.pumpAndSettle();

    expect(find.text('declined'), findsOneWidget);
    await tester.tap(find.text('Curry leaves, dried'));
    await tester.pumpAndSettle();

    // The pick is the DRAFT (plan 0029 W5) — it fills the fields and the
    // provenance it will stamp, and the form's one Save lands all of it.
    await saveForm(tester, reopen: curryLeaves.canonicalName);
    final row = (await repo.byId('curry'))!;
    expect(row.source, 'usda_fdc:11217');
    expect(row.sourceLabel, 'Curry leaves, dried');
    expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
  });

  testWidgets('offline: the sheet says nothing came back, and closing it '
      'changes nothing', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo(const [curryLeaves]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('nothing came back for “Curry leaves, fresh”'),
      findsOneWidget,
    );
    expect(find.byType(FDialog), findsNothing);
    await tester.tap(find.byIcon(FLucideIcons.x).last);
    await tester.pumpAndSettle();
    expect((await repo.byId('curry'))!.source, 'usda_fdc:11216');
  });

  // --- The card's third state (plan 0040 B-D2) -------------------------------

  testWidgets('an EDITED row reads "edited here", still names the food and its '
      'FDC id, and says which numbers are yours', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    await tester.pumpWidget(
      host(FakeIngredientRepo(const [chex]), at: '/ingredients/chex'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Filled from USDA · edited here'), findsOneWidget);
    // The confirm word it replaces is gone — a row whose numbers you typed is
    // not "confirmed from USDA" in any sense a reader would mean.
    expect(find.text('Filled from USDA · confirmed'), findsNothing);
    // The food is STILL NAMED: the match is not what changed.
    expect(
      find.textContaining('Cereals ready-to-eat, GENERAL MILLS, Corn CHEX'),
      findsOneWidget,
    );
    expect(find.textContaining('FDC 168930'), findsOneWidget);
    expect(
      find.text(
        'your macros and your density — the numbers on this row are no '
        'longer the source’s',
      ),
      findsOneWidget,
    );
    // B-D3: both doors are exactly as they were.
    expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
    expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
    // Provenance, not a warning (B-D2): no ⚠, and nothing amber.
    expect(find.byIcon(FLucideIcons.triangleAlert), findsNothing);
  });

  testWidgets('the line names only the numbers the row actually carries', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    await tester.pumpWidget(
      host(
        FakeIngredientRepo([chex.copyWith(densityGPerMl: null)]),
        at: '/ingredients/chex',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('your macros — the numbers'), findsOneWidget);
    expect(find.textContaining('your density'), findsNothing);
  });

  testWidgets('typing your own macros over a prefill flips the card to '
      '"edited here" — and a rename alone does not', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      curryLeaves.copyWith(macros: usdaAnswer.macros),
    ]);
    await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
    await tester.pumpAndSettle();
    expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);

    // A rename is not a claim about the numbers (B-D1's fence).
    await tester.enterText(find.byType(TextField).first, 'Curry leaves');
    await tester.pump();
    await saveForm(tester, reopen: 'Curry leaves');
    expect((await repo.byId('curry'))!.sourceEdited, isFalse);
    expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);

    // The macros are.
    await typeMacros(tester, kcal: '120', protein: '6', carb: '19', fat: '1');
    await saveForm(tester, reopen: 'Curry leaves');
    expect((await repo.byId('curry'))!.sourceEdited, isTrue);
    expect(find.text('Filled from USDA · edited here'), findsOneWidget);
    expect(find.textContaining('Curry leaves, raw'), findsOneWidget);
  });

  testWidgets('choosing another food CLEARS it — the numbers are the new '
      'food’s again', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    final repo = FakeIngredientRepo([
      chex.copyWith(canonicalName: 'Curry leaves, fresh', id: 'curry'),
    ]);
    await tester.pumpWidget(
      host(
        repo,
        at: '/ingredients/curry',
        probe: RecordingProbe.list(const [usdaAnswer]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Filled from USDA · edited here'), findsOneWidget);

    await tester.tap(find.widgetWithText(FButton, 'Choose another ›'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Curry leaves, raw').last);
    await tester.pumpAndSettle();
    await saveForm(tester, reopen: 'Curry leaves, fresh');

    final row = (await repo.byId('curry'))!;
    expect(row.source, 'usda_fdc:11216');
    expect(row.sourceEdited, isFalse);
    expect(find.text('Filled from USDA · edited here'), findsNothing);
  });

  testWidgets('a row USDA never touched carries no provenance line at '
      'all', (tester) async {
    filterForuiSemanticsAssertions();
    tallScreen(tester);
    await tester.pumpWidget(
      host(FakeIngredientRepo(const [blackRice]), at: '/ingredients/rice'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('USDA ·'), findsNothing);
    expect(find.textContaining('from USDA'), findsNothing);
    expect(find.text('Look up in USDA'), findsOneWidget);
  });
}
