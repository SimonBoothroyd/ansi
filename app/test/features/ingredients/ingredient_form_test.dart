/// The flesh-out form (frames b and c) and the create flow the `＋` opens:
/// the confirm CTA's gate and its reversal, the delete refusal's count, the
/// density-locked units and the measures editor — and, since plan 0029 C2,
/// that saving a form with no row behind it IS the add flow.
// The pumped ProviderScope IS the root scope of each test's tree (the same
// pattern connecting_view_test documents).
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/presentation/density_entry.dart'
    show AnsiModeChip;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:ansi/features/ingredients/presentation/piece_weight_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';
import '_form_harness.dart';

/// The volume family as the chips label it — what a per-100 g row draws
/// locked while it carries no density, which is the only lock left.
const _volumeLabels = {'tsp', 'tbsp', 'fl oz', 'cup', 'ml', 'l', 'pt', 'qt'};

void main() {
  group('the flesh-out form', () {
    testWidgets('a stub without macros: the CTA is refused with its reason, '
        'and the status line says it is out of the totals', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: editRoute('curry')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Still a stub — left out of macro totals until confirmed.'),
        findsOneWidget,
      );
      // G6's trim: the status line one row up already explains what a stub
      // costs, so the CTA's own note says only what it is waiting for.
      expect(find.text('needs macros'), findsOneWidget);
      final cta = tester.widget<FButton>(find.byKey(kFormCompleteKey));
      expect(cta.onPress, isNull);
    });

    testWidgets('typing the four macros arms the CTA, and confirming flips the '
        'row to complete — density never asked for', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(host(repo, at: editRoute('curry')));
      await tester.pumpAndSettle();

      for (final (label, value) in const [
        ('kcal', '108'),
        ('protein', '6'),
        ('carb', '19'),
        ('fat', '1'),
      ]) {
        await tester.enterText(macroField(label), value);
        await tester.pump();
      }

      await tester.tap(find.byKey(kFormCompleteKey));
      await tester.pumpAndSettle();

      final row = await repo.byId('curry');
      expect(row!.status, IngredientStatus.complete);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.densityGPerMl, isNull); // never required (D5)
      // Completing ends the page — the caller that pushed it is waiting.
      expect(find.text('CANONICAL NAME'), findsNothing);
    });

    testWidgets(
      'a complete row opens here too, and the confirm is reversible',
      (tester) async {
        filterForuiSemanticsAssertions();
        tallScreen(tester);
        final repo = FakeIngredientRepo(const [mango]);
        await tester.pumpWidget(host(repo, at: editRoute('mango')));
        await tester.pumpAndSettle();

        expect(
          find.text('Complete — counts in conversions and macro totals.'),
          findsOneWidget,
        );
        await openMoreMenu(tester);
        await tester.tap(find.text('Return it to a stub'));
        await tester.pumpAndSettle();

        final row = await repo.byId('mango');
        expect(row!.status, IngredientStatus.stub);
        // Unconfirming stops it counting; it does not erase what was typed.
        expect(row.macros, mangoMacros);
      },
    );

    testWidgets('THE MANGO CHIPS: a piece default with a density admits cup, '
        'and nothing is dashed', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: editRoute('mango')),
      );
      await tester.pumpAndSettle();
      for (final label in ['piece', 'g', 'cup', 'tbsp', 'tsp', 'ml']) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(
        find.textContaining('unlock when this row has a density'),
        findsNothing,
      );
    });

    testWidgets('two locks, two lines: piece waits on a piece weight, never '
        'on the density (ADR-0015)', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // A piece-default per-g row with NEITHER number: the volume family is
      // density-locked and `piece` is weight-locked. One line for both would
      // promise that a density unlocks `piece`, which nothing ever will.
      const unweighed = Ingredient(
        id: 'mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        category: 'produce',
        macros: mangoMacros,
      );
      final repo = FakeIngredientRepo(const [unweighed]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      expect(lockedUnitLabels(tester), _volumeLabels);
      expect(lockedUnitLabels(tester), isNot(contains('piece')));
      expect(
        find.text('piece unlocks when this row has a piece weight'),
        findsOneWidget,
      );

      // The weight in the draft clears ITS line and leaves the density's.
      await draftPieceWeight(tester, '200');
      expect(
        find.text('piece unlocks when this row has a piece weight'),
        findsNothing,
      );
      expect(lockedUnitLabels(tester), _volumeLabels);
    });

    testWidgets('the full cycle: locked → a density unlocks → deleting it '
        'strips again, with the basis family live throughout', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // A piece-default per-g row with no density: mass is its basis family
      // (always sayable), volume is the density-derived side. It carries its
      // piece weight so the ONLY thing missing here is the density.
      const bareMango = Ingredient(
        id: 'mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        category: 'produce',
        macros: mangoMacros,
        pieceBasisAmount: 200,
        pieceSource: 'manual',
      );
      final repo = FakeIngredientRepo(const [bareMango]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      // 1. Locked: the cross-family chips are drawn dashed, and the ONE
      // density line on the page — under the default-unit row, which is
      // missing the same family for the same reason — names them.
      expect(lockedUnitLabels(tester), _volumeLabels);
      expect(
        find.textContaining('unlock when this row has a density'),
        findsOneWidget,
      );
      // The basis side is toggleable from the start — it never needed one.
      expect(lockedUnitLabels(tester), isNot(contains('g')));
      expect(lockedUnitLabels(tester), isNot(contains('piece')));

      // 2. A density in the draft: the chips come live IMMEDIATELY, because
      // they read what the form holds — but nothing is written until Save
      // (W5). That split is the whole point of lane B.
      await draftDensity(tester, '0.66');

      expect(
        (await repo.byId('mango'))!.densityGPerMl,
        isNull,
        reason: 'the density is in the draft, not the database, until Save',
      );
      expect(lockedUnitLabels(tester), isEmpty);
      expect(
        find.textContaining('unlock when this row has a density'),
        findsNothing,
      );

      await saveForm(tester, reopen: 'Mango');
      expect((await repo.byId('mango'))!.densityGPerMl, 0.66);

      // 3. Delete it: the strip leg, in the same write, with the consequence
      // named before it happens. The saved number folded the block (C-D3), so
      // the affordance is one tap in.
      await openDensityEntry(tester);
      await tester.tap(find.text('remove the density'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lock again'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();
      // Same rule on the way out: the chips lock again at once, the row keeps
      // its number until Save.
      expect(lockedUnitLabels(tester), _volumeLabels);
      await saveForm(tester, reopen: 'Mango');

      final after = (await repo.byId('mango'))!;
      expect(after.densityGPerMl, isNull);
      // The cross-family units are gone from the stored list; the basis
      // family, the default unit's own family, and the category's imprecise
      // word (J3 — produce earns `handful`, which owes the density nothing)
      // all survive.
      expect(after.allowedUnits!.map((u) => u.id).toSet(), {
        'piece',
        'g',
        'kg',
        'oz',
        'lb',
        'handful',
      });
      expect(lockedUnitLabels(tester), _volumeLabels);
    });

    testWidgets('a density-less row draws the locked chips under ONE line '
        'naming exactly those units, and no second line saying it again', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: editRoute('curry')),
      );
      await tester.pumpAndSettle();
      // ONCE on the page, under the default-unit row: the allowed-units row
      // right below is dashed for the same reason and does not say it again.
      expect(
        find.text(
          'tsp · tbsp · fl oz · cup · ml · l · pt · qt unlock when this row '
          'has a density',
        ),
        findsOneWidget,
      );
      // One fact, one sentence. The section used to print the same list
      // twice — once as what a density unlocks, once as what its absence
      // locks — and then once per chip row.
      expect(find.textContaining('no density —'), findsNothing);
      expect(find.textContaining('That blocks nothing'), findsNothing);
    });

    testWidgets('delete is refused with the count while a live line points '
        'here', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(
        const [mango],
        references: const {'mango': (recipeCount: 3, lineCount: 4)},
      );
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();

      await openMoreMenu(tester);
      await tester.tap(find.text('Delete ingredient'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Still used by 3 recipes (4 lines)'),
        findsOneWidget,
      );
      expect(repo.rows, hasLength(1)); // untouched
    });

    testWidgets('an unreferenced row deletes and leaves the form', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();
      await openMoreMenu(tester);
      await tester.tap(find.text('Delete ingredient'));
      await tester.pumpAndSettle();
      expect(repo.rows, isEmpty);
    });

    testWidgets('renaming rewrites the match text and says so on the '
        'form', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(host(repo, at: editRoute('curry')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('renaming rewrites the match text'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Curry leaf, dried');
      // The last "Save" is the form's; the density entry has one too.
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect(repo.matchTextById['curry'], 'curry leaf dried');
    });

    testWidgets('measures are EDITABLE here — the shared editor, not a '
        'read-only note', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final measures = FakeMeasureRepo(const [
        Measure(id: 'm-usda', label: 'mango, medium', amount: 207),
      ]);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: editRoute('mango'),
          measures: measures,
        ),
      );
      await tester.pumpAndSettle();

      // The deferral is gone.
      expect(
        find.textContaining('added from a recipe line’s quantity sheet'),
        findsNothing,
      );
      expect(find.byType(MeasuresEditor), findsOneWidget);
      expect(find.text('mango, medium'), findsOneWidget);

      // Author one, in the row's basis unit.
      final add = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(add.first, 'half cheek');
      await tester.enterText(add.last, '90');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          matching: find.widgetWithText(FButton, 'Add'),
        ),
      );
      await tester.pumpAndSettle();

      // On screen at once, and NOT written (plan 0029 W5): a pending measure
      // is indistinguishable from a stored one here.
      expect(
        find.descendant(
          of: find.byType(MeasureRow),
          matching: find.text('half cheek'),
        ),
        findsOneWidget,
      );
      expect(
        measures.rows.map((m) => m.label),
        isNot(contains('half cheek')),
        reason: 'nothing is written until the form is saved',
      );

      // …and delete one. Also draft-only: it leaves the list, and the stored
      // row is untouched until Save.
      await tester.tap(find.byIcon(FLucideIcons.trash2).first);
      await tester.pumpAndSettle();
      expect(find.text('mango, medium'), findsNothing);
      expect(measures.rows.map((m) => m.label), contains('mango, medium'));

      // One Save carries both, and the form asked for exactly them.
      final repo = repoOf(tester);
      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'half cheek');
      expect(asked.measuresAdded.single.amount, 90);
      expect(asked.measuresRemoved, {'m-usda'});
    });

    testWidgets('a volume-named measure label is still refused and redirected '
        'into the density entry (ADR-0008 §2)', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: editRoute('mango'),
          measures: measures,
        ),
      );
      await tester.pumpAndSettle();

      final add = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(add.first, 'cup');
      await tester.enterText(add.last, '120');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          // `Add` on this host: the tap fills the draft, and the form's own
          // docked Save is what writes (plan 0029 R3).
          matching: find.widgetWithText(FButton, 'Add'),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing written, the reason on screen, and the density entry above
      // switched to the spoon phrasing with `cup` picked — the one door.
      expect(measures.rows, isEmpty);
      expect(
        find.textContaining('that mapping is the density'),
        findsOneWidget,
      );
      expect(find.text('weighs'), findsOneWidget);
    });

    // --- ADR-0015: what one of these weighs ---------------------------------
    //
    // `piece` is sayable when the row is counted AND something weighs one.
    // The count is the default unit; the weight is a number on the row, and
    // this is where it is typed.

    testWidgets('picking `piece` with nothing weighing one strands the row: '
        'the line says so, and Save refuses with both ways out', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // A gram row, moved onto the count by the chip that is always tappable.
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(host(repo, at: editRoute('curry')));
      await tester.pumpAndSettle();
      expect(find.byType(PieceWeightEntry), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('default-unit-row')),
          matching: find.widgetWithText(AnsiModeChip, 'piece'),
        ),
      );
      await tester.pumpAndSettle();

      // The flag names the number and the other way out, and the sentence
      // that clears it is directly below.
      expect(
        find.text('piece needs a weight on this row — enter one below, or'),
        findsOneWidget,
      );
      expect(find.text('switch to g'), findsOneWidget);
      expect(find.text('1 piece weighs'), findsOneWidget);

      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Piece can’t be the default unit with nothing weighing one — '
          'enter what one weighs below, or make it g.',
        ),
        findsOneWidget,
      );
      expect(repo.savedForms, isEmpty);
      expect(find.text('CANONICAL NAME'), findsOneWidget, reason: 'still here');
    });

    testWidgets('typing what one weighs unlocks the `piece` chip at once and '
        'lands on Save — the draft holds it meanwhile', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(host(repo, at: editRoute('curry')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('default-unit-row')),
          matching: find.widgetWithText(AnsiModeChip, 'piece'),
        ),
      );
      await tester.pumpAndSettle();
      await draftPieceWeight(tester, '350');

      // The chips read what the FORM holds, so the stranded line goes at once
      // — and the row is untouched until Save (W5).
      expect(find.textContaining('needs a weight on this row'), findsNothing);
      expect(
        (await repo.byId('curry'))!.pieceBasisAmount,
        isNull,
        reason: 'the weight is in the draft, not the database, until Save',
      );

      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.pieceWeight, isA<PieceWeightSet>());
      expect((asked.pieceWeight as PieceWeightSet).amount, 350);
      expect(asked.row.defaultUnit, pieces);
      expect(asked.row.allowedUnits, contains(pieces));
      expect((await repo.byId('curry'))!.pieceBasisAmount, 350);
    });

    testWidgets('removing the weight strips `piece` from the draft, with the '
        'consequence named before it happens', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // Mango is weighed, so its block opens folded.
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(host(repo, at: editRoute('mango')));
      await tester.pumpAndSettle();
      expect(find.text('200 g'), findsOneWidget);

      await openPieceWeightEntry(tester);
      await tester.tap(find.text('remove the piece weight'));
      await tester.pumpAndSettle();
      expect(find.textContaining('piece locks again'), findsOneWidget);
      await tester.tap(find.widgetWithText(FButton, 'Remove'));
      await tester.pumpAndSettle();

      // Which strands the default — the row is counted with nothing weighing
      // one — so the form says so rather than saving it.
      expect(
        find.text('piece needs a weight on this row — enter one below, or'),
        findsOneWidget,
      );
      await tester.tap(find.text('switch to g'));
      await tester.pumpAndSettle();

      final asked = repoOf(tester).savedForms.single;
      expect(asked.pieceWeight, isA<PieceWeightCleared>());
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
      expect(asked.row.defaultUnit, g);
    });

    testWidgets('the block is drawn only where the DRAFT is counted — moving '
        'the default off `piece` takes it away with the chip', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: editRoute('mango')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PieceWeightEntry), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('default-unit-row')),
          matching: find.widgetWithText(AnsiModeChip, 'g'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PieceWeightEntry), findsNothing);
      expect(find.text('PIECE WEIGHT'), findsNothing);
      // …and the admission chip goes with it: `piece` is offered only where
      // the row is counted.
      final admission = repoOf(tester);
      await saveForm(tester);
      expect(
        admission.savedForms.single.row.allowedUnits,
        isNot(contains(pieces)),
      );
    });

    testWidgets('the piece question and "Counts as" are gone — a measure is a '
        'measure, and it asks nothing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: editRoute('mango'), measures: measures),
      );
      await tester.pumpAndSettle();
      expect(find.text('COUNTS AS'), findsNothing);
      expect(find.text('One mango is'), findsNothing);

      final fields = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, 'mango, medium');
      await tester.enterText(fields.last, '207');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(MeasuresEditor),
          matching: find.widgetWithText(FButton, 'Add'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Still offer'), findsNothing);
      expect(find.text('COUNTS AS'), findsNothing);
      // The measure is drafted, and `piece` is untouched by its arrival: what
      // makes a count sayable is the weight, not the absence of a measure.
      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.measuresAdded.single.label, 'mango, medium');
      expect(asked.row.allowedUnits, contains(pieces));
    });

    testWidgets('the '
        "category is a dropdown of the household's own categories — free text "
        'is gone', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // The density is not what this test is about — it is what makes the
      // row savable at all: a tsp default on a per-100 g row is stranded,
      // and D4c refuses the write until one of its two fixes is taken.
      final repo = FakeIngredientRepo([
        mango,
        curryLeaves,
        yeast.copyWith(densityGPerMl: 0.4),
      ]);
      await tester.pumpWidget(host(repo, at: editRoute('yeast')));
      await tester.pumpAndSettle();

      // The only free-text fields left on the form are the ones that MUST be
      // free text — the name and the four macro inputs. The category is not
      // among them.
      expect(categorySelect, findsOneWidget);
      expect(find.widgetWithText(FTextField, 'e.g. produce'), findsNothing);

      // Opening it offers what the vocabulary actually carries, plus the
      // honest "none" — not a fixed taxonomy this app invented.
      await tester.tap(categorySelect);
      await tester.pumpAndSettle();
      expect(find.text('produce'), findsWidgets);
      expect(find.text('pantry'), findsWidgets);
      expect(find.text('no category'), findsWidgets);

      await tester.tap(find.text('produce').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect((await repo.byId('yeast'))!.category, 'produce');
    });

    testWidgets('a category nothing else carries is still offered, and a new '
        'one can be coined', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // Its own category is unique to it — the dropdown must not orphan it.
      const onlyOne = Ingredient(
        id: 'yeast',
        canonicalName: 'Nutritional yeast',
        defaultUnit: tsp,
        status: IngredientStatus.complete,
        category: 'oddments',
        // A spoon default needs the density before D4c will let the row be
        // saved at all; the category is what this test is about.
        densityGPerMl: 0.4,
        macros: Macros(kcal: 385, protein: 50, carb: 36, fat: 5),
      );
      final repo = FakeIngredientRepo(const [mango, onlyOne]);
      await tester.pumpWidget(host(repo, at: editRoute('yeast')));
      await tester.pumpAndSettle();
      expect(find.text('oddments'), findsWidgets);

      await tester.tap(find.widgetWithText(FButton, 'New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'store cupboard');
      await tester.tap(find.widgetWithText(FButton, 'Use it'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Save').last);
      await tester.pumpAndSettle();

      expect((await repo.byId('yeast'))!.category, 'store cupboard');
    });

    testWidgets('THE OWNER’S FLOW, rebuilt: rename then look up — USDA is '
        'asked about the name in the FIELD, and nothing is written to get '
        'there', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final plain = curryLeaves.copyWith(source: 'manual');
      final repo = FakeIngredientRepo([plain]);
      final probe = RecordingProbe(usdaAnswer);
      await tester.pumpWidget(host(repo, at: editRoute('curry'), probe: probe));
      await tester.pumpAndSettle();

      // Rename in the form and DON'T save — the exact state the owner hit.
      await tester.enterText(find.byType(TextField).first, 'Chicken Breast');
      await tester.pump();

      await lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The bug F1 was written for cannot recur: the query is the field, so
      // there is no stored name to go stale — and asking costs no write.
      expect(probe.asked.single, normalizeMatchText('Chicken Breast'));
      expect(
        (await repo.byId('curry'))!.macros,
        isNull,
        reason: 'a pick fills the draft; Save writes it (plan 0029 W5)',
      );

      // One Save carries the rename AND the pick — to the person they were
      // always one act, and now they are one write. Save ends the page, so
      // walk back in to read what the form says afterwards.
      await saveForm(tester, reopen: 'Chicken Breast');
      final row = (await repo.byId('curry'))!;
      expect(row.canonicalName, 'Chicken Breast');
      expect(repo.matchTextById['curry'], normalizeMatchText('Chicken Breast'));
      // …and the picked answer landed, without completing the row (D5).
      expect(row.densityGPerMl, 0.35);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.source, 'usda_fdc:11216');
      expect(row.sourceLabel, 'Curry leaves, raw');
      expect(row.status, IngredientStatus.stub);
      // Since 0027 the fill is NAMED where the numbers live, and the lookup
      // section (with its "filled this in" note) retires — the provenance
      // line and its doors are the way the match changes from here.
      expect(find.text('Filled from USDA · not confirmed'), findsOneWidget);
      expect(
        find.textContaining('Curry leaves, raw · matches only part of '),
        findsOneWidget,
      );
      expect(find.text('Look up in USDA'), findsNothing);
    });

    testWidgets('a successful lookup lands its numbers in the OPEN form’s '
        'macro fields — the row filling up is not the same as the form showing '
        'it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo([curryLeaves.copyWith(source: 'manual')]);
      final probe = RecordingProbe(usdaAnswer);
      await tester.pumpWidget(host(repo, at: editRoute('curry'), probe: probe));
      await tester.pumpAndSettle();

      // A bare stub: four empty fields, and a pending edit in a field the
      // form's own save does not touch.
      expect(macroFieldText(tester, 'kcal'), isEmpty);
      await tester.enterText(measureLabelField, 'small bunch');
      await tester.pump();

      await lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The FIELDS got the numbers at once — which is G1's whole subject —
      // while the row waits for Save.
      expect((await repo.byId('curry'))!.macros, isNull);
      // …and so did the fields, without leaving the screen. This is G1: the
      // controllers are seeded once at build, so before the row-version key
      // they went on showing the blanks they were born with.
      expect(macroFieldText(tester, 'kcal'), '108');
      expect(macroFieldText(tester, 'protein'), '6');
      expect(macroFieldText(tester, 'carb'), '19');
      expect(macroFieldText(tester, 'fat'), '1');
      // The density landed too, and the entry reads it off the row.
      expect(find.textContaining('0.35'), findsWidgets);
      // The uncommitted edit elsewhere is exactly where it was left: the
      // re-seed replaces the macro subtree at its own fixed slot, and shifts
      // nothing.
      expect(
        tester.widget<TextField>(measureLabelField).controller!.text,
        'small bunch',
      );
    });

    testWidgets('numbers the user is part-way through typing are never '
        'clobbered — a pending edit outranks the row', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo([curryLeaves.copyWith(source: 'manual')]);
      final probe = RecordingProbe(usdaAnswer);
      await tester.pumpWidget(host(repo, at: editRoute('curry'), probe: probe));
      await tester.pumpAndSettle();

      // Half a panel in flight. The lookup no longer saves the form to run
      // (F1 is retired), so an incoherent draft no longer BLOCKS it — the
      // question is the name in the field and costs nothing. What still
      // holds is G1's own rule: the pick's numbers reach the fields, and the
      // half-typed one they replace was the row's to replace.
      await tester.enterText(macroField('kcal'), '999');
      await tester.pump();

      await lookUpUsdaAndPick(tester, 'Curry leaves, raw');

      // The pick is an explicit act on the macros, so it wins the macro
      // fields outright…
      expect(macroFieldText(tester, 'kcal'), '108');
      // …and an edit in a field the fill has no opinion about is untouched.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        curryLeaves.canonicalName,
      );
    });

    testWidgets('a pick the user dismisses changes nothing at '
        'all', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo([curryLeaves.copyWith(source: 'manual')]);
      final probe = RecordingProbe(usdaAnswer);
      await tester.pumpWidget(host(repo, at: editRoute('curry'), probe: probe));
      await tester.pumpAndSettle();

      await tester.enterText(macroField('kcal'), '999');
      await tester.pump();
      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();
      // Close the short-list without choosing.
      await tester.tap(find.byIcon(FLucideIcons.x).first);
      await tester.pumpAndSettle();

      // Asked, and nothing else: no write, and the number in flight is still
      // in flight. This is what replaces F1's "Save this form first" state —
      // there is nothing to save first any more.
      expect(probe.asked, isNotEmpty);
      expect((await repo.byId('curry'))!.macros, isNull);
      expect(macroFieldText(tester, 'kcal'), '999');
    });

    // **G3 is retired with `_UsdaLookup`.** Its test pinned a lookup STATUS
    // sentence — "USDA has that name but no numbers for it" — and the rule
    // that a later edit to the row must retire it, because the sentence was
    // the only feedback an automatic probe gave. The fill door is a search
    // now: the feedback is the short-list you are looking at, and a candidate
    // with nothing to copy is left out of it rather than reported afterwards
    // (see the U-D3 test's "Curry, nameless"). There is no status to go
    // stale, so there is nothing to retire.

    testWidgets('the density row fits a phone — in its "none yet" state, and '
        'in the spoon phrasing', (tester) async {
      filterForuiSemanticsAssertions();
      phoneWidth(tester);
      // The section on its own, at the width the form gives it. Scoped
      // deliberately: the test font draws every glyph as a square of the font
      // size, so a whole-form assertion would fail on rows that fit fine on a
      // real device — and pass nothing useful about this one.
      await tester.pumpWidget(densityHost(curryLeaves));
      await tester.pumpAndSettle();

      // The longest caption plus both phrasing chips: 55px of debug stripe on
      // the owner's 402pt device before G2.
      expect(find.text('none yet — unlocks volume⇄weight'), findsOneWidget);
      expect(tester.takeException(), isNull);

      expect(find.text('weighs'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cup default on a per-100 g row with no density is FLAGGED '
        'with its repair, never rewritten', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [blackRice]);
      await tester.pumpWidget(host(repo, at: editRoute('rice')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cup needs a density on this row'),
        findsOneWidget,
      );
      // Reading the form changed nothing: how a household buys a thing is
      // not ours to edit behind its back.
      expect((await repo.byId('rice'))!.defaultUnit, cup);

      await tester.tap(find.text('switch to g'));
      await tester.pumpAndSettle();

      expect((await repo.byId('rice'))!.defaultUnit, g);
      expect(find.textContaining('needs a density on this row'), findsNothing);
    });

    testWidgets('a default the row cannot say REFUSES the save — flipping the '
        'basis to per 100 ml strands the g default, and the message names '
        'both fixes', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // The owner's shape: `g` was picked while the row read per 100 g, and
      // the macros then moved to per 100 ml. The chips would never have
      // OFFERED g here; nothing stopped the row keeping it.
      final repo = FakeIngredientRepo(const [curryLeaves]);
      await tester.pumpWidget(host(repo, at: editRoute('curry')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('per 100 ml'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('g needs a density on this row'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();

      // Refused in the message line, with the unit, the basis and both ways
      // out — and the form is still open, because nothing was written.
      expect(
        find.textContaining(
          'Macros per 100 ml and no density can’t have g as the default unit',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('add a density below, or make it ml'),
        findsOneWidget,
      );
      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(repo.savedForms, isEmpty);
      expect((await repo.byId('curry'))!.macrosBasis, MacrosBasis.perG);

      // The one-tap fix takes it, and the same Save lands.
      await tester.tap(find.text('switch to ml'));
      await tester.pumpAndSettle();

      final saved = (await repo.byId('curry'))!;
      expect(saved.defaultUnit, ml);
      expect(saved.macrosBasis, MacrosBasis.perMl);
    });

    testWidgets('the default-unit selector offers only the sayable units, '
        'keeps the stranded one it is already on, and a density clears the '
        'flag and brings the rest back', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [blackRice]), at: editRoute('rice')),
      );
      await tester.pumpAndSettle();

      // Per 100 g, no density: the mass family, the count and the words are
      // offered. The volume family is NOT a chip — it is the note's subject.
      for (final label in ['g', 'kg', 'oz', 'lb', 'piece', 'pinch']) {
        expect(defaultUnitChip(tester, label).enabled, isTrue, reason: label);
      }
      for (final label in ['ml', 'l', 'tsp', 'tbsp', 'fl oz', 'pt', 'qt']) {
        expect(defaultUnitChipFinder(label), findsNothing, reason: label);
      }

      // `cup` is the exception, and the reason the row draws it: it IS the
      // stored default. Drawn, selected, and painted STRANDED — the person
      // cannot fix a chip nobody shows them.
      expect(defaultUnitChip(tester, 'cup').selected, isTrue);
      expect(defaultUnitChip(tester, 'cup').stranded, isTrue);
      expect(defaultUnitChip(tester, 'g').stranded, isFalse);
      expect(
        find.textContaining('cup needs a density on this row'),
        findsOneWidget,
      );
      // The note names what a density would unlock — and never the chip
      // already on screen above it.
      expect(
        find.text(
          'tsp · tbsp · fl oz · ml · l · pt · qt unlock when this row has a '
          'density',
        ),
        findsOneWidget,
      );

      // A density repairs it — off the DRAFT, before anything is written —
      // and the whole family becomes pickable in the same breath.
      await draftDensity(tester, '0.75');

      expect(defaultUnitChip(tester, 'cup').stranded, isFalse);
      expect(defaultUnitChip(tester, 'tbsp').enabled, isTrue);
      expect(find.textContaining('needs a density on this row'), findsNothing);
      expect(find.textContaining('unlock when this row has'), findsNothing);
    });

    testWidgets('a blank new row offers the units it can already be counted '
        'in, and the note says what the rest are waiting on', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      // Nothing is filled in: per 100 g by default, no macros, no density. So
      // the mass family, the count and the words are chips; the volume family
      // is a sentence, because a spoon of a per-100 g food with no density is
      // a default the row could not convert.
      for (final u in kIngredientUnits) {
        final volume = u.family == UnitFamily.volume;
        expect(
          defaultUnitChipFinder(u.label),
          volume ? findsNothing : findsOneWidget,
          reason: u.label,
        );
      }
      expect(
        find.text(
          'tsp · tbsp · fl oz · cup · ml · l · pt · qt unlock when this row '
          'has a density',
        ),
        findsOneWidget,
      );

      // The density is the way in, off the DRAFT — and the volume family
      // arrives as chips the moment it is typed.
      await draftDensity(tester, '0.88');
      expect(find.textContaining('unlock when this row has'), findsNothing);
      await tester.tap(defaultUnitChipFinder('tsp'));
      await tester.pumpAndSettle();

      expect(defaultUnitChip(tester, 'tsp').selected, isTrue);
      expect(defaultUnitChip(tester, 'tsp').stranded, isFalse);
      expect(find.textContaining('needs a density on this row'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Vanilla extract');
      await tester.pump();
      await typeMacros(
        tester,
        kcal: '288',
        protein: '0.1',
        carb: '13',
        fat: '0',
      );
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();

      expect(repo.savedForms, hasLength(1));
      expect(repo.savedForms.single.row.defaultUnit, tsp);
    });

    testWidgets('offline: the short-list says nothing came back and never '
        'raises an error — the trigger is still the backstop', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final plain = curryLeaves.copyWith(source: 'manual');
      final repo = FakeIngredientRepo([plain]);
      await tester.pumpWidget(
        // The unconfigured probe answers exactly like an offline device.
        host(repo, at: editRoute('curry'), probe: const SilentUsdaProbe()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Look up in USDA'));
      await tester.pumpAndSettle();

      // The short-list's own empty state, which covers offline and "nothing
      // close enough" together — a person cannot act differently on the two,
      // and the server trigger re-runs the same probe on upload either way.
      expect(find.textContaining('nothing came back for'), findsOneWidget);
      // No dialog, and the row is untouched.
      expect(find.byType(FDialog), findsNothing);
      expect((await repo.byId('curry'))!.macros, isNull);
    });
  });

  group('creating an ingredient — the form IS the add flow', () {
    testWidgets('the ＋ opens a form with no row behind it: it says so, it '
        'offers no ⋯, and backing out writes nothing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      expect(find.text('CANONICAL NAME'), findsOneWidget);
      expect(
        find.text('New — nothing is saved until you tap Save.'),
        findsOneWidget,
      );
      // Nothing to delete and nothing to un-confirm on a row that is not
      // there, so the header carries no menu at all.
      expect(find.byIcon(FLucideIcons.ellipsis), findsNothing);
      expect(repo.rows, isEmpty);
    });

    testWidgets('one Save makes the row AND its children — the sheet needed '
        'two screens, and had already written by the time you saw the second', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pump();
      await draftDensity(tester, '0.4');
      await typeMacros(tester, kcal: '108', protein: '6', carb: '19', fat: '1');
      // Still nothing written — the whole point of C2, and what makes backing
      // out of a half-filled form cost nothing.
      expect(repo.rows, isEmpty);

      await saveForm(tester);
      final asked = repo.savedForms.single;
      // Save tidies a name that was typed in: the line's plural becomes the
      // entry it names.
      expect(asked.row.canonicalName, 'Curry Leaves');
      expect((asked.density as DensitySet).gPerMl, 0.4);
      expect(repo.rows.single.canonicalName, 'Curry Leaves');
      // Saved COMPLETE, in the same write. A new row is not a stub in
      // waiting: this form is not the door stubs come through.
      expect(asked.markComplete, isTrue);
      expect(repo.rows.single.status, IngredientStatus.complete);
    });

    testWidgets('the dock is one Save, live only once the row would count — '
        'and the line above it says what is still missing', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const []);
      await tester.pumpWidget(host(repo, at: '/ingredients/new'));
      await tester.pumpAndSettle();

      // No `Mark complete` at all: on a row that does not exist the two acts
      // are one act.
      expect(find.byKey(kFormCompleteKey), findsNothing);
      expect(find.text('Mark complete'), findsNothing);

      // Blank: the name is what the refusal names first, in its own words.
      expect(saveButton(tester).onPress, isNull);
      expect(
        find.text('A name is the one field an ingredient can’t go without.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).first, 'Curry leaves');
      await tester.pump();
      expect(saveButton(tester).onPress, isNull);
      expect(find.text('needs macros'), findsOneWidget);

      // A part of a panel is not a panel — the same sentence a stub's form
      // uses, said before the tap rather than after it.
      await tester.enterText(macroField('kcal'), '108');
      await tester.pump();
      expect(saveButton(tester).onPress, isNull);
      expect(find.textContaining('a part of a panel isn’t a panel'), findsOne);

      await typeMacros(tester, kcal: '108', protein: '6', carb: '19', fat: '1');
      expect(saveButton(tester).onPress, isNotNull);
      expect(
        find.text('saving it counts it in conversions and macro totals'),
        findsOneWidget,
      );

      await saveForm(tester);
      expect(repo.rows.single.status, IngredientStatus.complete);
    });

    testWidgets('a stub that already EXISTS keeps both buttons — the seed’s '
        'stubs are still there to be finished', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: editRoute('curry')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(kFormSaveKey), findsOneWidget);
      expect(find.byKey(kFormCompleteKey), findsOneWidget);
      // And its Save is live with no macros: putting a stub down half-filled
      // is exactly what a stub is for.
      expect(saveButton(tester).onPress, isNotNull);
    });

    testWidgets('a name carried in from a picker prefills the field', (
      tester,
    ) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const []),
          at: '/ingredients/new?name=Curry%20leaves',
        ),
      );
      await tester.pumpAndSettle();
      // The picker's query is prose, and the field opens on its tidied form —
      // the silent half only: the picker does not get to choose a new word.
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curry Leaves',
      );
    });
  });
}
