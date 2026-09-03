/// Sim smoke — WEEK → COOK → SHOP: the redesigned week — an empty week is a
/// STATE of the screen (never the retired blank-week page), copy-last-week
/// from its inline chip, Edit/Done's two modes, removal and edit-eaters
/// through the entry sheet (the per-row `⋯` and the eaters dialog are both
/// retired), the two-step add flow (recipe picker v2 — Favorites tab included
/// → confirm v2 with the full batch prose → portions), and the `Everyone`
/// lens DIMMING rather than removing; one cook session covering two close
/// meals and a split for a far one; the rolled-up shopping list with
/// provenance, a manual top-up through the shared quantity sheet, and
/// check-off. Runs with LIVE sync — `plan_entry.eaters` must survive the
/// jsonb round-trip as a real array.
///
/// The recipe the week plans — a favourited, two-day-shelf-life "Chicken
/// Curry" (Garlic 4 clove, Onion 1, two steps) — is SEEDED through the app's
/// own recipe repository over the throwaway database, then round-tripped
/// through sync, before the Week tab opens. The editor file drives the UI
/// that authors the same recipe; this file's subject is what the week does
/// with it.
///
/// Then the usual portion (plan 0027 front P): Jun's factor set to ×¾ from
/// the Library `⋯` ▸ Household sheet — the first client UPDATE on
/// `household_member`, so the round trip and a direct server read are what
/// prove the `0026` RLS door — and the fraction it makes said on the entry
/// sheet, under the per-person lens, and on the Cook tab's session row and
/// whole-batch nudge. The lens leg plans a second seeded recipe ("Macro
/// Bowl", 200 g Almonds — a line that resolves), because the curry's count
/// lines are honestly incomplete and a refused total names no share.
///
/// Local gate only (`make test-sim FILE=week`), never CI. Needs the local
/// backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/core/units/units.dart' show g, pieces;
import 'package:ansi/features/cook_plan/presentation/cook_view.dart'
    show CookView;
import 'package:ansi/features/planning/domain/planning.dart' show mondayOf;
import 'package:ansi/features/planning/presentation/week_view.dart'
    show WeekView;
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:ansi/features/shopping/presentation/shopping_view.dart'
    show ShoppingView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:uuid/uuid.dart';

import 'support/drive.dart';
import 'support/library.dart';
import 'support/stack.dart';
import 'support/week.dart';

const _uuid = Uuid();

/// Writes the recipe this file plans — the state the editor file leaves
/// behind after its edit leg — through the real repository, filed under the
/// household's default book and favourited. Returns the recipe id.
Future<String> _seedChickenCurry(
  PowerSyncDatabase db, {
  required String householdId,
}) async {
  final garlic = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Garlic' "
    'AND deleted_at IS NULL',
  );
  final onion = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Onion' "
    'AND deleted_at IS NULL',
  );
  // The starter measure cloned at onboarding (step 7.6) — the chip the
  // editor file taps. A measure line stores `unit = 'piece'` beside its FK:
  // the honest count fallback, never invented grams.
  final clove = await db.getOptional(
    'SELECT id FROM ingredient_measure WHERE ingredient_id = ? '
    "AND label = 'clove' AND deleted_at IS NULL",
    [garlic['id']],
  );
  expect(clove, isNotNull, reason: "Garlic's seeded 'clove' measure");
  // The default book the session controller ensured on first sync: the
  // Library renders books and skips book-less recipes.
  final book = await db.get(
    'SELECT id FROM book WHERE deleted_at IS NULL '
    'ORDER BY sort_order, created_at LIMIT 1',
  );
  final repo = SqliteRecipeRepository(db, householdId: householdId);
  final recipeId = _uuid.v4();
  await repo.saveRecipe(
    Recipe(
      id: recipeId,
      title: 'Chicken Curry',
      servingsBase: 2,
      keepsForDays: 2,
      bookId: book['id'] as String,
      steps: const ['Brown the aromatics.', 'Simmer until thick.'],
      groups: [
        IngredientGroup(
          id: _uuid.v4(),
          items: [
            LineItem(
              id: _uuid.v4(),
              ingredientId: garlic['id'] as String,
              ingredientName: 'Garlic',
              unit: pieces,
              quantity: 4,
              measureId: clove!['id'] as String,
            ),
            LineItem(
              id: _uuid.v4(),
              ingredientId: onion['id'] as String,
              ingredientName: 'Onion',
              unit: pieces,
              quantity: 1,
            ),
          ],
        ),
      ],
    ),
  );
  await repo.setFavorite(recipeId, true);
  return recipeId;
}

/// A recipe whose macros RESOLVE — one weighed line of a vocab row the seed
/// filled (Almonds, 579 kcal per 100 g), serving two — so the per-person
/// lens has a total to name its share under. Filed in the default book like
/// the curry; never favourited, so the Favorites tab stays the curry's.
Future<void> _seedMacroBowl(
  PowerSyncDatabase db, {
  required String householdId,
}) async {
  final almonds = await db.get(
    "SELECT id FROM ingredient WHERE canonical_name = 'Almonds' "
    "AND status = 'complete' AND deleted_at IS NULL",
  );
  final book = await db.get(
    'SELECT id FROM book WHERE deleted_at IS NULL '
    'ORDER BY sort_order, created_at LIMIT 1',
  );
  await SqliteRecipeRepository(db, householdId: householdId).saveRecipe(
    Recipe(
      id: _uuid.v4(),
      title: 'Macro Bowl',
      servingsBase: 2,
      keepsForDays: 2,
      bookId: book['id'] as String,
      groups: [
        IngredientGroup(
          id: _uuid.v4(),
          items: [
            LineItem(
              id: _uuid.v4(),
              ingredientId: almonds['id'] as String,
              ingredientName: 'Almonds',
              unit: g,
              quantity: 200,
            ),
          ],
        ),
      ],
    ),
  );
}

/// The chip labelled [label] on the Household sheet's row for [name] — the
/// segment sits under the member's name, so the row is found by ancestry
/// (the host test's finder).
Finder _memberChip(String name, String label) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(Column)).first,
  matching: find.text(label),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('week → cook → shop over the real local db', (tester) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibrary(tester);

    // Runs with LIVE sync: every planned entry below round-trips through the
    // server, so `plan_entry.eaters` (a jsonb column) must come back down as
    // a real array — the explicit round-trip check after the edit-eaters step
    // pins that. (Kept as one testWidgets: 3a–3c build on each other's data,
    // and one launch keeps the file fast; live-sync coverage is what
    // mattered, not the split.)

    // ------------------------------------------------------------------------
    // 3a · WEEK — copy-last-week, two-step add, batch hint, eaters, lens.
    // ------------------------------------------------------------------------
    final recipeId = await _seedChickenCurry(
      db,
      householdId: stack.householdId,
    );
    await _seedMacroBowl(db, householdId: stack.householdId);
    // The seeds go up and come back down before anything reads them: the
    // week plans a recipe the server has, exactly as it would one authored
    // on the partner's device.
    await stack.waitForSyncRoundTrip(tester);
    final household = await db.get('SELECT id FROM household LIMIT 1');
    final members = await db.getAll(
      'SELECT id, display_name FROM household_member ORDER BY sort_order',
    );
    final adaId = members.first['id'] as String;
    final junId = members.last['id'] as String;
    final currentKey = isoDate(mondayOf(DateTime.now()));

    Future<List<Map<String, Object?>>> currentEntries() => db.getAll(
      'SELECT pe.id, pe.day_of_week, pe.eaters, pe.portions, pe.deleted_at '
      'FROM plan_entry pe JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE wp.week_start_date = ? AND pe.deleted_at IS NULL '
      'ORDER BY pe.day_of_week',
      [currentKey],
    );

    // Seed LAST week directly in the local db (as sync would deliver a week
    // planned earlier, e.g. from the partner's device). The Week screen pins to
    // the week containing today, so the "blank following week" the copy flow
    // wants IS the current week once an earlier week exists.
    final lastMonday = mondayOf(
      DateTime.now(),
    ).subtract(const Duration(days: 7));
    final now = DateTime.now().toUtc().toIso8601String();
    final lastWeekId = _uuid.v4();
    await db.execute(
      'INSERT INTO week_plan (id, household_id, week_start_date, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?)',
      [lastWeekId, household['id'], isoDate(lastMonday), now, now],
    );
    await db.execute(
      'INSERT INTO plan_entry (id, household_id, week_plan_id, day_of_week, '
      'meal_slot, recipe_id, eaters, portions, sort_order, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        household['id'],
        lastWeekId,
        3, // Thursday
        'Dinner',
        recipeId,
        jsonEncode([adaId, junId]),
        null,
        0,
        now,
        now,
      ],
    );

    // Week tab → the current week with nothing in it. Since the redesign
    // that is a STATE of this screen, not a page of its own (D5): the
    // switcher, the mode action, the lens and all seven day cards are present,
    // and `copy last week` is a chip beside the one primary door.
    await tapTab(tester, FLucideIcons.calendarDays);
    await pumpUntilFound(tester, find.text('Add the first meal'));
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget); // was "Shared" (D8)
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('nothing planned'), findsWidgets);
    expect(find.text('A blank week'), findsNothing); // the page is gone (D5)
    await pumpUntilFound(tester, find.text('copy last week'));
    await tester.tap(find.text('copy last week'));
    await pumpUntilFound(tester, find.text('Chicken Curry'));
    await pumpUntilFound(tester, find.text('DINNER'));
    await waitForDb(
      tester,
      () async => (await currentEntries()).length == 1,
      'the copied entry in the current week',
    );

    // Remove the copied meal through the ENTRY SHEET — the per-row `⋯` and
    // the standalone eaters dialog are both retired into it (D7). The seeded
    // entry sits on Thursday.
    await enterWeekEditMode(tester);
    await scrollTo(tester, find.text('Thursday'));
    await tester.tap(
      find.descendant(
        of: dayCard('Thursday'),
        matching: find.text('Chicken Curry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This meal'), findsOneWidget);
    await tester.tap(find.text('Remove from the week'));
    await tester.pumpAndSettle();
    // The NEW assertion, and the more valuable one: the screen does NOT
    // change. Removing the last meal used to teleport you off the grid
    // mid-edit, because the blank-week page fired on `entries.isEmpty` too.
    // The first-meal bar sits at the TOP of the (lazy) list, and we are
    // scrolled to Thursday — scroll back up rather than wait for a widget the
    // viewport has not built.
    expect(find.text('Thursday'), findsOneWidget);
    await scrollTo(tester, find.text('Add the first meal'), delta: -300);
    expect(find.text('Add the first meal'), findsOneWidget);
    await waitForDb(
      tester,
      () async => (await currentEntries()).isEmpty,
      'the copied entry to be tombstoned',
    );

    // Two-step add flow (Monday): picker → confirm → portions override. Back
    // to the resting state first, so the picker's own "Add a meal" header is
    // the only one on screen.
    await leaveWeekEditMode(tester);
    await tester.tap(find.text('Add the first meal'));
    await tester.pumpAndSettle();
    expect(find.text('Add a meal'), findsOneWidget); // picker header
    expect(find.textContaining('Monday, Dinner'), findsOneWidget); // context
    // The Favorites tab (7.7) holds the seeded, favourited recipe.
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Curry'), findsWidgets);
    // The row is information-honest: per-serving line present (incomplete —
    // Garlic/Onion are count lines, honesty over zeros).
    expect(find.textContaining('serves '), findsWidgets);
    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken Curry').last);
    await tester.pumpAndSettle();
    expect(find.text('Add to plan'), findsOneWidget); // confirm sheet
    expect(find.text('2 portions'), findsOneWidget); // defaults to |eaters|
    await tester.tap(find.byIcon(FLucideIcons.plus).last);
    await tester.pumpAndSettle();
    expect(find.text('3 portions'), findsOneWidget);
    await tester.tap(find.text('Add to Monday'));
    await pumpUntilFound(tester, find.text('DINNER'));

    // Second meal on Wednesday — within the 2-day fridge window, so the
    // confirm sheet cues that it cooks in Monday's batch.
    await enterWeekEditMode(tester);
    await scrollTo(tester, find.text('Wednesday'));
    final add = find.descendant(
      of: dayCard('Wednesday'),
      matching: find.text('Add a meal'),
    );
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chicken Curry').last);
    await tester.pumpAndSettle();
    // The FULL batch prose (confirm v2): dish, day, window, conclusion.
    expect(
      find.textContaining(
        'Chicken Curry already cooks Monday and keeps 2 days',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('joins Monday’s batch'), findsOneWidget);
    await tester.tap(find.text('Add to Wednesday'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final rows = await currentEntries();
      return rows.length == 2 &&
          rows.first['day_of_week'] == 0 &&
          rows.first['portions'] == 3 &&
          rows.last['day_of_week'] == 2 &&
          rows.last['portions'] == null;
    }, 'both planned entries with the portions override');

    // Edit who's eating on the Wednesday meal: drop Jun. It lives in the
    // entry sheet now (D7) — and the sheet writes through on the tap, so
    // there is nothing to save, only a dismissal.
    await enterWeekEditMode(tester);
    await scrollTo(tester, find.text('Wednesday'));
    await tester.tap(
      find.descendant(
        of: dayCard('Wednesday'),
        matching: find.text('Chicken Curry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("WHO'S EATING"), findsOneWidget);
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final rows = await currentEntries();
      final eaters =
          jsonDecode(rows.last['eaters']! as String) as List<dynamic>;
      return eaters.length == 1 && eaters.single == adaId;
    }, "Wednesday's eaters to be just Ada");

    // The jsonb round-trip check: after the server echoes the edit back down,
    // `eaters` must still parse as an array of member ids (the old connector
    // double-encoded it into a string, crashing every parser).
    await stack.waitForSyncRoundTrip(tester);
    final roundTripped = await currentEntries();
    expect(jsonDecode(roundTripped.last['eaters']! as String), [
      adaId,
    ], reason: 'plan_entry.eaters must survive live sync as a real JSON array');

    // The lens DIMS, it no longer removes (D8) — and `Shared` is `Everyone`.
    await leaveWeekEditMode(tester);
    await scrollTo(tester, find.text('Everyone'), delta: -150);
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    // Wednesday is Ada's alone after the edit above. Under Jun's lens it is
    // dimmed but STILL THERE: a day somebody else cooks for themselves is not
    // an empty day, which is exactly what the old hard filter implied.
    expect(find.text('Chicken Curry'), findsNWidgets(2));

    // D7 (nav) — the lens is a filter the user CHOSE, and the shell keeps it:
    // a round trip through Cook comes back under Jun, not reset to Everyone.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await tapTab(tester, FLucideIcons.calendarDays);
    await pumpUntilFound(tester, find.text('Everyone'));
    expect(find.text('Chicken Curry'), findsNWidgets(2));
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Curry'), findsNWidgets(2));

    // ------------------------------------------------------------------------
    // 3b · COOK — the derived batch plan reacts to the Week (tracker: plan two
    // far-apart meals → two session cards).
    // ------------------------------------------------------------------------
    // Mon + Wed sit inside the 2-day window → ONE session covers both.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await pumpUntilFound(tester, find.text('Cook Mon'));
    expect(find.textContaining('Cook '), findsOneWidget);
    // Monday's override (3) + Wednesday's single eater after the edit (1).
    expect(find.text('covers Mon + Wed dinner · 4 portions'), findsOneWidget);
    expect(find.text('4 portions across the week · keeps 2 d'), findsOneWidget);

    // Plan a third meal on Saturday — beyond the fridge window from Monday.
    await tapTab(tester, FLucideIcons.calendarDays);
    await pumpUntilFound(tester, find.text('Everyone'));
    await addMealOn(tester, 'Saturday', 'Chicken Curry');

    // The cook plan re-derives: two sessions, flagged as a split.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.text('Cook Sat'));
    expect(find.text('Cook Mon'), findsOneWidget);
    expect(find.textContaining('Cook '), findsNWidgets(2));
    expect(find.textContaining('cook it again, fresh'), findsOneWidget);

    final count = await db.get(
      'SELECT COUNT(*) AS c FROM plan_entry pe '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE wp.week_start_date = ? AND pe.deleted_at IS NULL',
      [isoDate(mondayOf(DateTime.now()))],
    );
    expect(count['c'], 3);

    // ------------------------------------------------------------------------
    // 3c · SHOP — provenance roll-up, a manual top-up, and check-off.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.byKey(ShoppingView.rootKey));
    await pumpUntilFound(tester, find.text('Garlic'));
    expect(find.text('Onion'), findsOneWidget);
    // Both cook sessions contribute, labelled per batch.
    expect(find.textContaining('Chicken Curry · cook Mon'), findsNWidgets(2));
    expect(find.textContaining('Chicken Curry · cook Sat'), findsNWidgets(2));

    // Manual top-up: +2 piece of Garlic through the add sheet.
    await scrollTo(tester, find.textContaining('add item or top up'));
    await tester.tap(find.textContaining('add item or top up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Top up an ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'garlic');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garlic').last);
    await tester.pumpAndSettle();
    // The shared quantity sheet (7.7): type into its qty field (the
    // overlay's last EditableText) and confirm — the default unit (piece)
    // stands, so no chip tap is needed.
    await tester.enterText(find.byType(EditableText).last, '2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add top-up'));
    await pumpUntilFound(tester, find.textContaining('manual top-up'));

    final garlic = await db.get(
      "SELECT id FROM ingredient WHERE canonical_name = 'Garlic'",
    );
    final entry = await db.get(
      'SELECT id, checked FROM shopping_list_entry '
      'WHERE ingredient_id = ? AND deleted_at IS NULL',
      [garlic['id']],
    );
    final topUp = await db.get(
      'SELECT quantity, unit, source_type FROM shopping_list_contribution '
      'WHERE entry_id = ? AND deleted_at IS NULL',
      [entry['id']],
    );
    expect(topUp['source_type'], 'manual');
    expect(topUp['quantity'], 2);

    // Check off the rolled-up Onion line (lazily creates its overlay entry).
    final onion = await db.get(
      "SELECT id FROM ingredient WHERE canonical_name = 'Onion'",
    );
    await tester.tap(find.text('Onion'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final row = await db.getOptional(
        'SELECT checked FROM shopping_list_entry '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [onion['id']],
      );
      return row != null && row['checked'] == 1;
    }, 'the Onion check-off overlay row');
    // A checked line hides its provenance breakdown, so only Garlic's cook
    // lines remain.
    await tester.pumpAndSettle();
    expect(find.textContaining('Chicken Curry · cook Mon'), findsOneWidget);

    // ------------------------------------------------------------------------
    // 3d · A USUAL PORTION PER PERSON (plan 0027 P-D3/D4/D5) — set on the
    // account page (0028 E6 moved the roster off the Library `⋯` and out of a
    // sheet), proven on the server, then read everywhere the head-count used
    // to be. Runs last so every number above is the
    // all-factors-1 identity the plan promised.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.library);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await openLibraryMenu(tester);
    await tester.tap(find.text('Account'));
    await pumpUntilFound(tester, find.text('USUAL PORTION'));
    // Both at ×1: a meal for both is still two portions.
    expect(find.textContaining('counts as 2 portions'), findsOneWidget);
    await tester.tap(_memberChip('Jun', '×¾'));
    await tester.pumpAndSettle();
    // The write lands in the sheet's own foot line (P-D3: Ada set Jun's).
    await pumpUntilFound(tester, find.textContaining('counts as 1¾ portions'));

    // The RLS door `0026` added: `household_member` never took a client
    // write before this. The upload queue draining is the connector's word
    // that the PATCH was accepted; the server read is the table's own.
    await stack.waitForSyncRoundTrip(tester);
    final local = await db.get(
      'SELECT portion_factor FROM household_member WHERE id = ?',
      [junId],
    );
    expect((local['portion_factor']! as num).toDouble(), closeTo(0.75, 1e-9));
    final server = await Supabase.instance.client
        .from('household_member')
        .select('portion_factor')
        .eq('id', junId)
        .single();
    expect(
      (server['portion_factor']! as num).toDouble(),
      closeTo(0.75, 1e-9),
      reason: 'the household-scoped UPDATE policy let Ada set Jun’s factor',
    );
    // Back off the pushed page rather than closing a sheet.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('USUAL PORTION'), findsNothing);

    // On the Week: the Saturday curry has both eaters and no override, so
    // its entry sheet speaks the fraction (P-D4) — never 1.75. The screen
    // is as 3b left it — in edit mode, scrolled to Saturday — so neither
    // `Edit` nor the lens row at the top of the lazy list is in the tree;
    // anchor on the view itself.
    await tapTab(tester, FLucideIcons.calendarDays);
    await pumpUntilFound(tester, find.byType(WeekView));
    // The lens leg's meal first: Macro Bowl on Sunday, for both.
    await addMealOn(tester, 'Sunday', 'Macro Bowl');
    await scrollTo(tester, find.text('Saturday'));
    await tester.tap(
      find.descendant(
        of: dayCard('Saturday'),
        matching: find.text('Chicken Curry'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('This meal'), findsOneWidget);
    expect(find.text('1¾ portions'), findsOneWidget);
    expect(find.text('Ada 1 · Jun ¾ — their usual'), findsOneWidget);
    expect(find.textContaining('1.75'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Under Jun's lens the Sunday total is ¾ of a 579 kcal serving, and the
    // denominator names the share (P-D5). The curry's own days stay refused
    // — count lines without a measure resolve to no total, whoever looks.
    await leaveWeekEditMode(tester);
    await scrollTo(tester, find.text('Everyone'), delta: -300);
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('1 meal · Jun · ¾ of 1¾ portions'));
    expect(find.text('434 kcal'), findsWidgets);
    await scrollTo(tester, find.text('Everyone'), delta: -300);
    await tester.tap(find.text('Everyone'));
    await tester.pumpAndSettle();

    // The Cook tab: 1¾ portions of a serves-2 recipe is ×0.88, and the
    // whole-batch nudge speaks the quarter left over (P-D4). Monday's
    // override (3) and Wednesday's lone eater (1) are untouched by Jun's
    // factor, so that session still says 4.
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(tester, find.byKey(CookView.rootKey));
    await scrollTo(tester, find.text('covers Mon + Wed dinner · 4 portions'));
    await scrollTo(tester, find.text('covers Sat dinner · 1¾ portions'));
    expect(
      find.text(
        'cook ×1 instead — covers 2 portions · ¼ portion left over · '
        'shopping still buys ×0.88',
      ),
      findsWidgets,
    );
    await scrollTo(tester, find.text('covers Sun dinner · 1¾ portions'));
    expect(
      find.text('1¾ portions across the week · keeps 2 d'),
      findsOneWidget,
    );
    expect(find.textContaining('1.75'), findsNothing);
  });
}
