/// End-to-end smoke on a real device/simulator: the whole app over the real
/// step-7 stack — Supabase auth, PowerSync sync, and the derived Week → Cook →
/// Shop pipeline — driven through the UI. Local gate only (`make test-sim`),
/// never CI. Needs the local backend running (`make db-up`) and the usual
/// `--dart-define`s (the Makefile passes them from `.env.local`).
///
/// The suite is self-provisioning: `setUpAll` creates a throwaway two-person
/// household over plain HTTP (sign-up + `ensure_onboarded`, the same calls as
/// `scripts/smoke_auth.sh`) so the app can SIGN IN to an already-onboarded
/// account. In-app sign-UP is deliberately not exercised: a fresh signup's
/// token lacks the `household_id` claim, so its first sync is empty (known
/// step-7 gap; the password grant after onboarding carries the claim).
///
/// Scenarios (each `testWidgets` builds on the previous one's data, in order):
///   1 auth        sign-in gate → /connecting → Library with the synced
///                 household
///   2 library     new section → new recipe (vocab ingredients, shelf life,
///                 filed under book + section) → breadcrumb + local-db rows
///   3 week→cook→shop  copy-last-week, remove, the two-step add flow (picker
///                 → confirm → portions), batch hint, edit-eaters, per-person
///                 lens; one cook session covering two close meals and a
///                 split for a far one; the rolled-up shopping list with
///                 provenance, a manual top-up, and check-off. Runs with sync
///                 DISCONNECTED — the connector's live jsonb bug corrupts
///                 `plan_entry.eaters` on the round-trip (see the scope-around
///                 comment in the test).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mise/app.dart';
import 'package:mise/core/config/env.dart';
import 'package:mise/core/sync/database.dart';
import 'package:mise/core/sync/schema.dart';
import 'package:mise/core/sync/session.dart';
import 'package:mise/features/planning/domain/planning.dart' show mondayOf;
import 'package:powersync/powersync.dart' hide Column;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _password = 'smoke-password-123';
const _uuid = Uuid();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late Directory dir;
  late String email; // the provisioned user the app signs in as ("Ada")

  setUpAll(() async {
    expect(
      Env.isConfigured,
      isTrue,
      reason: 'run via `make test-sim` so the --dart-defines are set',
    );
    email = await _provisionHousehold();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // The local stack issues a legacy anon JWT (mirrors bootstrap.dart).
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
      // No persisted auth: the simulator can hold a session from an earlier
      // `make run` whose user a later `db reset` deleted — its JWT stays
      // validly signed for up to an hour and would drive the app as a ghost
      // user. In-memory-only sessions make every run start signed out; the
      // sign-in from scenario 1 still carries through the rest of the suite
      // (one process).
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
    // A throwaway database rather than the app's own file, so a rerun starts
    // empty and everything asserted below arrived through this run's sync.
    dir = Directory.systemTemp.createTempSync('mise_smoke');
    db = PowerSyncDatabase(schema: schema, path: '${dir.path}/smoke.db');
    await db.initialize();
  });

  tearDownAll(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// Filters two known, benign error reports; everything else still fails the
  /// test. Installed at the top of every scenario.
  ///
  /// 1. Opening a Forui dialog while the accessibility tree is live trips a
  ///    semantics assertion inside the framework — it reproduces in a plain
  ///    widget test with `ensureSemantics()`, and forui is already pinned at
  ///    the newest 0.22.x (tech-debt tracker, 2026-08-27).
  /// 2. `SessionController.build` fires `_handle` before `build` returns, and
  ///    `_handle` reads the controller's own `state` synchronously — an
  ///    uninitialized-provider StateError on every app start. In the app the
  ///    guarded zone just logs it (a later auth event re-runs `_handle` and
  ///    everything proceeds); here it would be recorded as a failure.
  void ignoreKnownStartupNoise() {
    // TODO(step7-fixes): drop the uninitialized-provider arm below once
    // SessionController defers its initial `_handle` past its own build.
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      if ('${details.exception}'.contains('semantics.dart')) return;
      if (details.exception is StateError &&
          '${details.exception}'.contains('uninitialized provider') &&
          '${details.stack}'.contains('session.dart')) {
        return;
      }
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
  }

  /// Builds the app on a provider container whose [SessionController] is
  /// pre-mounted inside a guarded zone.
  ///
  /// `SessionController.build` fires `_handle` before `build` returns, and
  /// `_handle` synchronously reads the controller's own `state` — an
  /// uninitialized-provider StateError in an unawaited Future on every app
  /// start. In the app, bootstrap's guarded zone just logs it (a later auth
  /// event re-runs `_handle` and everything proceeds), but flutter_test aborts
  /// the whole test on any unhandled zone error, detaching the still-running
  /// test body. Mounting the controller here keeps that error (and any later
  /// `_handle` failure — they inherit this zone through the auth listener) in
  /// a zone of ours: logged, never fatal. Real breakage still surfaces as the
  /// UI waits below time out.
  // TODO(step7-fixes): collapse back to a plain ProviderScope pump once
  // SessionController defers its initial `_handle` past its own build.
  Future<void> pumpApp(WidgetTester tester) async {
    late final ProviderContainer container;
    runZonedGuarded(
      () {
        container = ProviderContainer(
          overrides: [powerSyncDatabaseProvider.overrideWithValue(db)],
        )..listen(sessionControllerProvider, (_, _) {});
      },
      // ignore: avoid_print — visible in the `flutter test` log for diagnosis.
      (error, stack) => print('session zone error (non-fatal): $error'),
    );
    addTearDown(() async {
      // Unmount the tree before disposing, so no consumer touches a dead
      // container when the next test's pump replaces the root.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MiseApp()),
    );
    await tester.pump();
  }

  /// Pumps until [finder] matches, then settles. `pumpAndSettle` alone can't
  /// cross the network waits here (the /connecting spinner animates forever),
  /// so poll real time first. The settle matters: a widget is findable the
  /// moment it is *built*, which can be mid route transition — a tap taken
  /// then lands beside the still-sliding target (observed: the Week page's
  /// row menu at x=439 on a 402pt screen). A perpetual animation on the found
  /// screen just times the settle out; that's fine, proceed.
  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out after $timeout waiting for $finder');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    try {
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      // `pumpAndSettle` times out with a FlutterError (an Error, not an
      // Exception): still animating after 5s means an ambient spinner —
      // positions are stable enough, and the next wait re-checks anyway.
      // ignore: avoid_catching_errors
    } on FlutterError {
      // Intentionally swallowed; see above.
    }
  }

  /// Polls the local database until [probe] returns true.
  Future<void> waitForDb(
    WidgetTester tester,
    Future<bool> Function() probe,
    String what, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await probe()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Timed out after $timeout waiting for $what');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Launches the app already signed in (scenario 1 did the sign-in) and waits
  /// out /connecting until the Library renders.
  Future<void> openLibrary(WidgetTester tester) async {
    await pumpApp(tester);
    await pumpUntilFound(
      tester,
      find.text('Our Cookbook'),
      timeout: const Duration(seconds: 60),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(
    WidgetTester tester,
    Finder finder, {
    double delta = 150,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// The +1 button of the labelled `_StepperRow` in the recipe editor.
  Finder stepperPlus(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byIcon(FLucideIcons.plus),
  );

  /// The Week grid card for a full weekday name (nearest enclosing Column).
  Finder dayCard(String day) =>
      find.ancestor(of: find.text(day), matching: find.byType(Column)).first;

  /// Opens the recipe picker from [day]'s card and places [recipe] on it
  /// through the two-step flow, leaving the confirm sheet's defaults alone.
  Future<void> addMealOn(WidgetTester tester, String day, String recipe) async {
    await scrollTo(tester, find.text(day));
    final add = find.descendant(
      of: dayCard(day),
      matching: find.text('Add a meal'),
    );
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    // `.last`: the sheet renders after the week grid, whose rows can carry the
    // same title text (the tap must land on the overlay, not under it).
    await tester.tap(find.text(recipe).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to $day'));
    await tester.pumpAndSettle();
  }

  /// Adds one vocab ingredient to the recipe editor's (single) group and types
  /// its quantity. Asserts the picker actually searched the synced vocab.
  Future<void> addIngredient(
    WidgetTester tester,
    String name,
    String qty,
  ) async {
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    // The picker sheet's search field is the last EditableText (overlay).
    await tester.enterText(find.byType(EditableText).last, name.toLowerCase());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(FItem), matching: find.text(name)).first,
    );
    await tester.pumpAndSettle();
    // The new line's qty field lives in the same Column as its name.
    final line = find
        .ancestor(of: find.text(name), matching: find.byType(Column))
        .first;
    await tester.enterText(
      find.descendant(of: line, matching: find.byType(EditableText)).first,
      qty,
    );
    await tester.pump();
  }

  // ---------------------------------------------------------------------------
  // 1 · AUTH — sign in through the gate, out the other side of /connecting.
  // ---------------------------------------------------------------------------
  testWidgets('1 auth: signs in and reaches the synced Library', (
    tester,
  ) async {
    ignoreKnownStartupNoise();
    await pumpApp(tester);

    // Signed out → the router holds everything behind /sign-in.
    await pumpUntilFound(tester, find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, email);
    await tester.enterText(find.byType(EditableText).at(1), _password);
    await tester.pump();
    await tester.tap(find.text('Sign in'));

    // /connecting runs onboarding + first sync; then the Library with the
    // default book the session controller ensures.
    await pumpUntilFound(
      tester,
      find.text('Our Cookbook'),
      timeout: const Duration(seconds: 90),
    );

    // The synced household reached the local database: both members and the
    // cloned ingredient vocab (reachable-through-the-picker is scenario 2).
    final members = await db.getAll(
      'SELECT display_name FROM household_member ORDER BY sort_order',
    );
    expect(members.map((r) => r['display_name']).toList(), ['Ada', 'Jun']);
    final vocab = await db.get('SELECT COUNT(*) AS c FROM ingredient');
    expect(vocab['c'] as int, greaterThan(100));
  });

  // ---------------------------------------------------------------------------
  // 2 · LIBRARY — the pre-auth filing smoke, now behind the gate.
  // ---------------------------------------------------------------------------
  testWidgets('2 library: files a new recipe under a new section', (
    tester,
  ) async {
    ignoreKnownStartupNoise();
    await openLibrary(tester);

    await tester.tap(find.textContaining('new section'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'Weeknight');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Weeknight'), findsOneWidget);

    // The app-bar + (an FHeaderAction); the "+ new section" affordance now
    // carries the same icon, so scope to the header action.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.plus),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText).first, 'Chicken Curry');
    await tester.pump();

    // Shelf life: keeps 2 days in the fridge — scenario 4 relies on this to
    // split the far Saturday meal into its own cook session.
    await tester.tap(stepperPlus('Keeps in the fridge'));
    await tester.pump();
    await tester.tap(stepperPlus('Keeps in the fridge'));
    await tester.pumpAndSettle();
    expect(find.text('2 days'), findsOneWidget);

    // File under Our Cookbook · Weeknight (the section select starts on the
    // Unsectioned bucket).
    await tester.tap(find.text('Unsectioned'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weeknight').last);
    await tester.pumpAndSettle();

    // Two ingredients through the synced-vocab picker.
    await addIngredient(tester, 'Garlic', '3');
    await addIngredient(tester, 'Onion', '1');

    // METHOD stays empty on purpose.
    // TODO(step7-fixes): type method steps here (and assert them on the recipe
    // view) once the connector's jsonb upload fix lands — saving steps
    // currently corrupts after the sync round-trip.
    // TODO(step7-fixes): re-open the saved recipe and edit it (rename, tweak a
    // quantity) once the edit-recipe fix lands — an edit currently tombstones
    // the recipe's ingredients server-side.

    await scrollTo(tester, find.text('Save'), delta: -150);
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK · WEEKNIGHT'));
    // No further UI asserts on the recipe view: within ~a second of saving,
    // the sync round-trip rewrites `recipe.steps` double-encoded (the live
    // connector jsonb bug) and the recipe view's watch stream errors out.
    // The local-db asserts below are the real check.
    // TODO(step7-fixes): assert the rendered title here (and re-open the
    // recipe) once the connector's jsonb fix lands.

    // The write reached the local database, fully filed.
    final recipe = await db.get(
      'SELECT id, keeps_for_days, book_id, section_id FROM recipe '
      "WHERE title = 'Chicken Curry' AND deleted_at IS NULL",
    );
    expect(recipe['keeps_for_days'], 2);
    expect(recipe['book_id'], isNotNull);
    expect(recipe['section_id'], isNotNull);
    final items = await db.getAll(
      'SELECT li.quantity, li.unit FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    );
    expect(items, hasLength(2));
    expect(items.first['quantity'], 3);
    expect(items.last['quantity'], 1);
  });

  // ---------------------------------------------------------------------------
  // 3 · WEEK — copy-last-week, the two-step add flow, eaters, per-person lens.
  // ---------------------------------------------------------------------------
  testWidgets('3 week → cook → shop over the real local db', (tester) async {
    ignoreKnownStartupNoise();
    await openLibrary(tester);

    // KNOWN LIVE BUG scope-around: the connector uploads JSON-array columns as
    // plain strings, so Postgres stores a jsonb *string* and the row syncs
    // back down double-encoded — `plan_entry.eaters` then crashes every
    // parser (`type 'String' is not a subtype of type 'List<dynamic>'`,
    // observed live; same jsonb bug as recipe method steps). Until the
    // connector fix lands, run the planning scenarios with sync disconnected:
    // they verify the Week → Cook → Shop UI wiring over the real local
    // PowerSync db, which is exactly what steps 4–6 owed. The auth + library
    // scenarios above still cover live sync.
    // TODO(step7-fixes): delete this disconnect (and re-split the scenarios
    // into their own testWidgets) once the connector's jsonb fix lands, so
    // planned weeks round-trip through the server here too.
    //
    // The session controller's own `connect` may still be spawning its sync
    // stream when the Library first renders, and a disconnect issued mid-spawn
    // loses the race (observed: the fresh iteration started right after the
    // disconnect). Wait for the connection to be fully up, then take it down
    // and hold until the status agrees.
    await waitForDb(
      tester,
      () async => db.currentStatus.connected,
      'sync to finish connecting',
    );
    await db.disconnect();
    await waitForDb(tester, () async {
      final status = db.currentStatus;
      return !status.connected && !status.connecting;
    }, 'sync to stay disconnected');

    // ------------------------------------------------------------------------
    // 3a · WEEK — copy-last-week, two-step add, batch hint, eaters, lens.
    // ------------------------------------------------------------------------
    final household = await db.get('SELECT id FROM household LIMIT 1');
    final recipe = await db.get(
      "SELECT id FROM recipe WHERE title = 'Chicken Curry'",
    );
    final members = await db.getAll(
      'SELECT id, display_name FROM household_member ORDER BY sort_order',
    );
    final adaId = members.first['id'] as String;
    final junId = members.last['id'] as String;
    final currentKey = _isoDate(mondayOf(DateTime.now()));

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
      [lastWeekId, household['id'], _isoDate(lastMonday), now, now],
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
        recipe['id'],
        jsonEncode([adaId, junId]),
        null,
        0,
        now,
        now,
      ],
    );

    // Week tab → blank current week, with the copy affordance.
    await tester.tap(find.byIcon(FLucideIcons.calendarDays));
    await pumpUntilFound(tester, find.text('A blank week'));
    await pumpUntilFound(tester, find.text('Copy last week'));
    expect(find.text('Last week, for reference'), findsOneWidget);
    await tester.tap(find.text('Copy last week'));
    await pumpUntilFound(tester, find.text('Chicken Curry'));
    await pumpUntilFound(tester, find.text('DINNER'));
    await waitForDb(
      tester,
      () async => (await currentEntries()).length == 1,
      'the copied entry in the current week',
    );

    // Remove the copied meal through its row menu → back to the blank week.
    // (The seeded entry sits on Thursday; target that card's menu — a bare
    // `.last` on the icon can hit a closed popover's off-screen portal copy.)
    await scrollTo(tester, find.text('Thursday'));
    await tester.tap(
      find.descendant(
        of: dayCard('Thursday'),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await pumpUntilFound(tester, find.text('Plan a meal'));
    await waitForDb(
      tester,
      () async => (await currentEntries()).isEmpty,
      'the copied entry to be tombstoned',
    );

    // Two-step add flow (Monday): picker → confirm → portions override.
    await tester.tap(find.text('Plan a meal'));
    await tester.pumpAndSettle();
    expect(find.text('Add a meal'), findsOneWidget); // picker header
    expect(find.textContaining('Monday, Dinner'), findsOneWidget); // context
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
    expect(find.textContaining('same batch as Monday'), findsOneWidget);
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

    // Edit who's eating on the Wednesday meal: drop Jun.
    await tester.tap(
      find.descendant(
        of: dayCard('Wednesday'),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("Edit who's eating"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jun'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final rows = await currentEntries();
      final eaters =
          jsonDecode(rows.last['eaters']! as String) as List<dynamic>;
      return eaters.length == 1 && eaters.single == adaId;
    }, "Wednesday's eaters to be just Ada");

    // Per-person lens: under Jun only the shared Monday meal remains.
    await scrollTo(tester, find.text('Shared'), delta: -150);
    await tester.tap(find.text('Per-person'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Curry'), findsNWidgets(2)); // Ada eats both
    await tester.tap(find.text('Jun'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Curry'), findsOneWidget); // Wed filtered out
    expect(find.text('shared'), findsOneWidget); // Monday is a shared meal
    await tester.tap(find.text('Shared'));
    await tester.pumpAndSettle();
    expect(find.text('Chicken Curry'), findsNWidgets(2));

    // ------------------------------------------------------------------------
    // 3b · COOK — the derived batch plan reacts to the Week (tracker: plan two
    // far-apart meals → two session cards).
    // ------------------------------------------------------------------------
    // Mon + Wed sit inside the 2-day window → ONE session covers both.
    await tester.tap(find.byIcon(FLucideIcons.cookingPot));
    await pumpUntilFound(tester, find.text('Batch cook plan'));
    await pumpUntilFound(tester, find.text('Cook Mon'));
    expect(find.textContaining('Cook '), findsOneWidget);
    // Monday's override (3) + Wednesday's single eater after the edit (1).
    expect(find.text('covers Mon + Wed dinner · 4 portions'), findsOneWidget);
    expect(find.text('4 portions across the week · keeps 2 d'), findsOneWidget);

    // Plan a third meal on Saturday — beyond the fridge window from Monday.
    await tester.tap(find.byIcon(FLucideIcons.calendarDays));
    await pumpUntilFound(tester, find.text('Shared'));
    await addMealOn(tester, 'Saturday', 'Chicken Curry');

    // The cook plan re-derives: two sessions, flagged as a split.
    await tester.tap(find.byIcon(FLucideIcons.cookingPot));
    await pumpUntilFound(tester, find.text('Cook Sat'));
    expect(find.text('Cook Mon'), findsOneWidget);
    expect(find.textContaining('Cook '), findsNWidgets(2));
    expect(find.textContaining('cook it again, fresh'), findsOneWidget);

    final count = await db.get(
      'SELECT COUNT(*) AS c FROM plan_entry pe '
      'JOIN week_plan wp ON wp.id = pe.week_plan_id '
      'WHERE wp.week_start_date = ? AND pe.deleted_at IS NULL',
      [_isoDate(mondayOf(DateTime.now()))],
    );
    expect(count['c'], 3);

    // ------------------------------------------------------------------------
    // 3c · SHOP — provenance roll-up, a manual top-up, and check-off.
    // ------------------------------------------------------------------------
    await tester.tap(find.byIcon(FLucideIcons.shoppingBasket));
    await pumpUntilFound(tester, find.text('Shopping list'));
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
    await tester.tap(
      find
          .descendant(of: find.byType(FItem), matching: find.text('Garlic'))
          .first,
    );
    await tester.pumpAndSettle();
    // `.first`: the qty field leads the row — the unit FSelect after it embeds
    // its own EditableText, so `.last` would type into the closed select.
    await tester.enterText(find.byType(EditableText).first, '2');
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
  });
}

/// 'YYYY-MM-DD' — the key `week_plan.week_start_date` is addressed by.
String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// -----------------------------------------------------------------------------
// Provisioning — plain HTTP against the local Supabase (mirrors
// scripts/smoke_auth.sh). In-app sign-up is not used: see the library doc.
// -----------------------------------------------------------------------------

/// Creates a fresh two-person household ("Ada" + "Jun") and returns Ada's
/// email. `ensure_onboarded` joins ANY household with room before creating one,
/// so stray one-member households left by earlier runs are filled with plug
/// users until a sign-up lands in a genuinely fresh (and therefore clean)
/// household; the partner then deterministically joins it.
Future<String> _provisionHousehold() async {
  for (var attempt = 0; attempt < 8; attempt++) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // NOTE: example.com is on the cloud blocklist — use the app's own domain.
    final email = 'smoke$stamp.ada@mise.app';
    final token = await _signUp(email, fullName: 'Ada');
    final household = await _ensureOnboarded(token);
    if (await _memberCount(token, household) > 1) continue; // filled a stray
    final partnerToken = await _signUp(
      'smoke$stamp.jun@mise.app',
      fullName: 'Jun',
    );
    final partnerHousehold = await _ensureOnboarded(partnerToken);
    if (partnerHousehold != household) {
      throw StateError(
        'partner landed in $partnerHousehold, not $household — '
        'another client raced the provisioning?',
      );
    }
    return email;
  }
  throw StateError('no fresh household after 8 sign-ups — too many strays?');
}

Future<String> _signUp(String email, {required String fullName}) async {
  final body = await _post('/auth/v1/signup', {
    'email': email,
    'password': _password,
    'data': {'full_name': fullName},
  });
  final token = (body as Map)['access_token'] as String?;
  if (token == null) {
    throw StateError(
      'sign-up returned no access token (email confirmations on?): $body',
    );
  }
  return token;
}

Future<String> _ensureOnboarded(String token) async =>
    await _post('/rest/v1/rpc/ensure_onboarded', {}, bearer: token) as String;

Future<int> _memberCount(String token, String householdId) async {
  final body = await _get(
    '/rest/v1/household_member?select=id'
    '&household_id=eq.$householdId&deleted_at=is.null',
    bearer: token,
  );
  return (body as List).length;
}

Future<dynamic> _post(
  String path,
  Map<String, dynamic> body, {
  String? bearer,
}) => _request('POST', path, body: body, bearer: bearer);

Future<dynamic> _get(String path, {String? bearer}) =>
    _request('GET', path, bearer: bearer);

Future<dynamic> _request(
  String method,
  String path, {
  Map<String, dynamic>? body,
  String? bearer,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('${Env.supabaseUrl}$path'),
    );
    req.headers
      ..set('apikey', Env.supabaseAnonKey)
      ..contentType = ContentType.json;
    if (bearer != null) req.headers.set('Authorization', 'Bearer $bearer');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    if (res.statusCode >= 400) {
      throw StateError('$method $path → ${res.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  } finally {
    client.close();
  }
}
