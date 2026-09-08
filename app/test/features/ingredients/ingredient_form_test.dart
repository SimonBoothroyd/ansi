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
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart';
import 'package:ansi/features/ingredients/presentation/measures_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/forui_semantics.dart';
import '../../helpers/silent_usda_probe.dart';
import '_form_harness.dart';

void main() {
  group('the flesh-out form', () {
    testWidgets('a stub without macros: the CTA is refused with its reason, '
        'and the status line says it is out of the totals', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: '/ingredients/curry'),
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
      await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
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
        await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
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
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
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

    testWidgets('the full cycle: locked → a density unlocks → deleting it '
        'strips again, with the basis family live throughout', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      // A piece-default per-g row with no density: mass is its basis family
      // (always sayable), volume is the density-derived side.
      const bareMango = Ingredient(
        id: 'mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        category: 'produce',
        macros: mangoMacros,
      );
      final repo = FakeIngredientRepo(const [bareMango]);
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
      await tester.pumpAndSettle();

      // 1. Locked: the cross-family chips are drawn dashed, with the hint.
      expect(lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
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
      expect(lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
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
        'handful',
      });
      expect(lockedUnitLabels(tester), {'tsp', 'tbsp', 'cup', 'ml', 'pt'});
    });

    testWidgets('a density-less row draws the locked chips, and the note above '
        'them is ONE line naming exactly those units', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [curryLeaves]), at: '/ingredients/curry'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('unlock when this row has a density'),
        findsOneWidget,
      );
      // It used to be three sentences, one of which claimed a family was
      // locked from the basis rather than from what is actually dashed.
      expect(
        find.text('no density — tsp · tbsp · cup · ml · pt locked'),
        findsOneWidget,
      );
      expect(find.textContaining('That blocks nothing'), findsNothing);
    });

    testWidgets('a row with a density says nothing at all there — a note with '
        'no news is noise', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [mango]), at: '/ingredients/mango'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no density —'), findsNothing);
    });

    testWidgets('delete is refused with the count while a live line points '
        'here', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(
        const [mango],
        references: const {'mango': (recipeCount: 3, lineCount: 4)},
      );
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
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
      await tester.pumpWidget(host(repo, at: '/ingredients/mango'));
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
      await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
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
          at: '/ingredients/mango',
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
      // is indistinguishable from a stored one here, which is what lets the
      // `piece` question and "Counts as" point at it before it exists.
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
          at: '/ingredients/mango',
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

    // --- plan 0022 / ADR-0010: the one question in the `piece` model --------
    //
    // `piece` is the fallback for "we have nothing better to call it". The
    // moment a row's FIRST measure names the thing, that stops being true —
    // and the household decides, once, with a default, never a rule.

    /// Saves a measure through the shared editor and settles the dialog it
    /// may raise.
    Future<void> addMeasure(
      WidgetTester tester,
      String label,
      String amount,
    ) async {
      final fields = find.descendant(
        of: find.byType(MeasuresEditor),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, label);
      await tester.enterText(fields.last, amount);
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
    }

    testWidgets('the FIRST measure asks whether `piece` stays offered, and the '
        'default answer takes it out of allowed_units', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));

      await addMeasure(tester, 'mango, medium', '207');

      // The board's frame (c): named, weighed, and about this row.
      expect(
        find.textContaining('Still offer “piece” for Mango?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('nobody can tell which was meant'),
        findsOneWidget,
      );

      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      // The answer IS the draft now (plan 0029 W5): `piece` leaves the chips
      // the form holds at once, and the row keeps it until Save. That is the
      // lane B trap answered — the chips follow the draft, not a row nobody
      // has written.
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));

      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
      // Nothing else went with it — one word, not a re-curation.
      expect(asked.row.allowedUnits, contains(g));
      // …and the same act said what a bare "1 mango" means (seam D1).
      expect(
        (asked.defaultMeasure as DefaultMeasureSet).measureId,
        asked.measuresAdded.single.id,
      );
      expect(asked.measuresAdded.single.label, 'mango, medium');
    });

    testWidgets('“Keep both” leaves the admission exactly as it was — and so '
        'does dismissing the question', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: FakeMeasureRepo()),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(allowedUnitsFor(repo.rows.single), contains(pieces));
    });

    testWidgets('a SECOND measure asks nothing — the row already answered, '
        'whichever way', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(
        host(
          repo,
          at: '/ingredients/mango',
          measures: FakeMeasureRepo(const [
            Measure(id: 'm-usda', label: 'mango, medium', amount: 207),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, large', '280');

      expect(find.textContaining('Still offer “piece”'), findsNothing);
      expect(allowedUnitsFor(repo.rows.single), contains(pieces));
    });

    testWidgets('deleting the last measure does NOT put `piece` back — the '
        'admission chips offer it, unlocked and one tap away', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FLucideIcons.trash2).first);
      await tester.pumpAndSettle();

      // The measure leaves the list at once; the row is written on Save.
      expect(find.byType(MeasureRow), findsNothing);
      // Save ends the page, so walk back in to read the chips.
      await saveForm(tester, reopen: 'Mango');
      // No automatic re-add: the household said no, and a deletion is not
      // them changing their mind.
      expect(repo.savedForms.last.row.allowedUnits, isNot(contains(pieces)));
      // But the chip is still drawn, and drawn LIVE (not dashed): a count
      // row needs no density for `piece`, so it is one tap from returning.
      expect(lockedUnitLabels(tester), isNot(contains('piece')));
      expect(find.text('piece'), findsWidgets);
    });

    // --- seam D1: "Counts as", the second half of the same answer ----------

    testWidgets('answering No also sets Counts as — the two questions were '
        'always one, and the prompt says so', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      final measures = FakeMeasureRepo();
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, isNull);

      await addMeasure(tester, 'mango, medium', '207');
      expect(
        find.textContaining('Answering No also sets Counts as: mango, medium'),
        findsOneWidget,
      );

      await tester.tap(find.text('No — “mango, medium” says it'));
      await tester.pumpAndSettle();

      // Both halves ride the form's one Save now, and they ride it together —
      // which is the point seam D1 was always making.
      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(
        (asked.defaultMeasure as DefaultMeasureSet).measureId,
        asked.measuresAdded.single.id,
      );
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
    });

    testWidgets('“Keep both” leaves Counts as unset — the honest reading of '
        '"both words are sayable here"', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: FakeMeasureRepo()),
      );
      await tester.pumpAndSettle();

      await addMeasure(tester, 'mango, medium', '207');
      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(repo.rows.single.defaultMeasureId, isNull);
    });

    testWidgets('the Counts as picker sets it, and "Ask me each time" clears '
        'it without touching a single measure', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final repo = FakeIngredientRepo(const [mango]);
      final measures = FakeMeasureRepo(const [
        Measure(id: 'm-med', label: 'mango, medium', amount: 207),
        Measure(id: 'm-lrg', label: 'mango, large', amount: 280),
      ]);
      await tester.pumpWidget(
        host(repo, at: '/ingredients/mango', measures: measures),
      );
      await tester.pumpAndSettle();

      expect(find.text('COUNTS AS'), findsOneWidget);
      expect(find.text('One mango is'), findsOneWidget);
      expect(find.text('— not set'), findsOneWidget);

      await tester.tap(find.text('— not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('mango, medium · 207 g').last);
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, 'm-med');

      // …and back to "Ask me each time", which is a real answer.
      await tester.tap(find.text('mango, medium · 207 g').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ask me each time').last);
      await tester.pumpAndSettle();
      expect(repo.rows.single.defaultMeasureId, isNull);
      // Clearing a default never destroys a measure: the row keeps every
      // label it had and only stops having a preferred one.
      expect(measures.rows.map((m) => m.label), [
        'mango, medium',
        'mango, large',
      ]);
    });

    testWidgets('a row with NO measures is not asked — there is nothing to '
        'choose and nothing to ask', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(
          FakeIngredientRepo(const [mango]),
          at: '/ingredients/mango',
          measures: FakeMeasureRepo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COUNTS AS'), findsNothing);
      expect(find.text('One mango is'), findsNothing);
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
      await tester.pumpWidget(host(repo, at: '/ingredients/yeast'));
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
      await tester.pumpWidget(host(repo, at: '/ingredients/yeast'));
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
      await tester.pumpWidget(
        host(repo, at: '/ingredients/curry', probe: probe),
      );
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
        find.textContaining(
          'Curry leaves, raw · FDC 11216 · matches only part of ',
        ),
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
      await tester.pumpWidget(
        host(repo, at: '/ingredients/curry', probe: probe),
      );
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
      await tester.pumpWidget(
        host(repo, at: '/ingredients/curry', probe: probe),
      );
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
      await tester.pumpWidget(
        host(repo, at: '/ingredients/curry', probe: probe),
      );
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
      await tester.pumpWidget(host(repo, at: '/ingredients/rice'));
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
      await tester.pumpWidget(host(repo, at: '/ingredients/curry'));
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

    testWidgets('the default-unit selector locks the other family while no '
        'density bridges it', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      await tester.pumpWidget(
        host(FakeIngredientRepo(const [blackRice]), at: '/ingredients/rice'),
      );
      await tester.pumpAndSettle();

      // The basis family, count and imprecise stay pickable…
      expect(defaultUnitChip(tester, 'g').enabled, isTrue);
      expect(defaultUnitChip(tester, 'kg').enabled, isTrue);
      expect(defaultUnitChip(tester, 'piece').enabled, isTrue);
      expect(defaultUnitChip(tester, 'pinch').enabled, isTrue);
      // …the volume family does not, since nothing bridges it.
      expect(defaultUnitChip(tester, 'ml').enabled, isFalse);
      expect(defaultUnitChip(tester, 'tbsp').enabled, isFalse);
      // The stored default still renders as the selection — it is the truth
      // about the row, and the note is how it gets fixed.
      expect(defaultUnitChip(tester, 'cup').selected, isTrue);

      // A density unlocks the whole selector again — off the DRAFT, before
      // anything is written (plan 0029 W5).
      await draftDensity(tester, '0.75');

      expect(defaultUnitChip(tester, 'ml').enabled, isTrue);
      expect(find.textContaining('needs a density on this row'), findsNothing);
    });

    testWidgets('offline: the short-list says nothing came back and never '
        'raises an error — the trigger is still the backstop', (tester) async {
      filterForuiSemanticsAssertions();
      tallScreen(tester);
      final plain = curryLeaves.copyWith(source: 'manual');
      final repo = FakeIngredientRepo([plain]);
      await tester.pumpWidget(
        // The unconfigured probe answers exactly like an offline device.
        host(repo, at: '/ingredients/curry', probe: const SilentUsdaProbe()),
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
      // Still nothing written — the whole point of C2, and what makes backing
      // out of a half-filled form cost nothing.
      expect(repo.rows, isEmpty);

      await saveForm(tester);
      final asked = repo.savedForms.single;
      expect(asked.row.canonicalName, 'Curry leaves');
      expect((asked.density as DensitySet).gPerMl, 0.4);
      expect(repo.rows.single.canonicalName, 'Curry leaves');
      // Born a stub whatever was filled in (D5): only Mark complete promotes,
      // and that is a human act.
      expect(repo.rows.single.status, IngredientStatus.stub);
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
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Curry leaves',
      );
    });
  });
}
