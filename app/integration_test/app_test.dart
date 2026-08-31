/// End-to-end smoke on a real device/simulator: the whole app over the real
/// step-7 stack — Supabase auth, PowerSync sync, and the derived Week → Cook →
/// Shop pipeline — driven through the UI. Local gate only (`make test-sim`),
/// never CI. Needs the local backend running (`make db-up`) and the usual
/// `--dart-define`s (the Makefile passes them from `.env.local`).
///
/// The suite is self-provisioning: `setUpAll` creates a throwaway two-person
/// household over plain HTTP (sign-up + `ensure_onboarded`, the same calls as
/// `scripts/smoke_auth.sh`) so the app can SIGN IN to an already-onboarded
/// account. In-app sign-UP is not exercised here — the session controller's
/// post-onboarding `refreshSession()` makes it work now (verified manually on
/// device, 7.4 sweep), but provisioning over HTTP keeps each run's users
/// deterministic and the scenarios focused on the signed-in app.
///
/// Scenarios (each `testWidgets` builds on the previous one's data, in order):
///   1 auth        sign-in gate → /connecting → Library with the synced
///                 household
///   2 library     new section → new recipe through the 7.7 pickers (picker
///                 v2 search → quantity + unit-chip sheet; a manual measure
///                 authored in the manage state, the seeded clove chip on
///                 the line; shelf life, method steps, filed under book +
///                 section) → breadcrumb + rendered title + local-db rows;
///                 favorite via the header menu; then re-open and edit the
///                 saved recipe and assert its children survive the server
///                 round-trip (the connector jsonb + diffing-save fixes)
///   3 week→cook→shop  copy-last-week, remove, the two-step add flow
///                 (recipe picker v2 — Favorites tab included → confirm v2
///                 with the full batch prose → portions), edit-eaters,
///                 per-person lens; one cook session covering two close
///                 meals and a split for a far one; the rolled-up shopping
///                 list with provenance, a manual top-up through the shared
///                 quantity sheet, and check-off. Runs with LIVE sync —
///                 `plan_entry.eaters` must survive the jsonb round-trip as
///                 a real array.
///   4 import      paste a link → the review screen → resolve every line
///                 (an auto match confirmed, a printed RANGE picked, a
///                 `suggest` pill taken onto a real vocab row, `none` lines
///                 created as stubs that coalesce) → Save → the recipe lands
///                 FILED in a book with tokenized steps whose refs are real
///                 line_item ids, over LIVE sync. The import repository is
///                 overridden to the local one, so NO edge function and NO
///                 LLM is called — see `openLibraryWithLocalImport`.
library;

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
import 'package:mise/core/sync/session.dart' show currentHouseholdIdProvider;
import 'package:mise/features/import/data/import_providers.dart';
import 'package:mise/features/import/data/import_repository_impl.dart';
import 'package:mise/features/import/presentation/recon_line_card.dart'
    show AmountEditor;
import 'package:mise/features/ingredients/presentation/quantity_unit_sheet.dart'
    show QuantityUnitEditor, UnitChipRow;
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

  /// Filters one known, benign error report; everything else still fails the
  /// test. Installed at the top of every scenario.
  ///
  /// Opening a Forui dialog while the accessibility tree is live trips a
  /// semantics assertion inside the framework — it reproduces in a plain
  /// widget test with `ensureSemantics()`, and forui is already pinned at
  /// the newest 0.22.x (tech-debt tracker, 2026-08-27).
  /// (7.7) A dismissed sheet whose text field held focus can fire one last
  /// `EditableText` periodic post-frame callback after deactivation —
  /// "Looking up a deactivated widget's ancestor is unsafe" out of
  /// `_updateSelectionRects`. Debug-only framework noise on teardown of the
  /// autofocused picker/quantity sheets; filtered narrowly by its stack.
  void ignoreForuiSemanticsAssertion() {
    final reportError = FlutterError.onError!;
    FlutterError.onError = (details) {
      final text = '${details.exception}';
      if (text.contains('semantics.dart')) return;
      if (text.contains("Looking up a deactivated widget's ancestor") &&
          '${details.stack}'.contains('_updateSelectionRects')) {
        return;
      }
      reportError(details);
    };
    addTearDown(() => FlutterError.onError = reportError);
  }

  /// Builds the app over the suite's throwaway PowerSync database.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [powerSyncDatabaseProvider.overrideWithValue(db)],
        child: const MiseApp(),
      ),
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

  /// Waits until every queued local write has uploaded, then pumps a little
  /// real time so the server's round-trip streams back down over the local
  /// rows. Asserts made after this run against round-tripped data — exactly
  /// where the old connector jsonb/tombstone bugs corrupted rows (within ~a
  /// second of the save).
  Future<void> waitForSyncRoundTrip(WidgetTester tester) async {
    await waitForDb(
      tester,
      () async => (await db.getUploadQueueStats()).count == 0,
      'the upload queue to drain',
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
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

  /// [openLibrary], but with the import repository swapped for the LOCAL one —
  /// `SqliteImportRepository`, exactly what `importRepositoryProvider` builds
  /// when Supabase is unconfigured. It is the fake edge function: it returns
  /// the canned payload and re-resolves its candidates against the household's
  /// really-synced vocab. Nothing on the import path touches the network or a
  /// provider key; every other collaborator stays real.
  Future<void> openLibraryWithLocalImport(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerSyncDatabaseProvider.overrideWithValue(db),
          importRepositoryProvider.overrideWith(
            (Ref ref) => SqliteImportRepository(
              ref.watch(databaseProvider),
              householdId: ref.watch(currentHouseholdIdProvider),
            ),
          ),
        ],
        child: const MiseApp(),
      ),
    );
    await tester.pump();
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
    // The FIRST Scrollable is not always the screen's list: an expanded
    // review card puts horizontal chip rows earlier in the tree, and scrolling
    // one of those never reveals anything below the fold. Scroll the first
    // VERTICAL scrollable instead — downward first, and if the target never
    // appears (it may be ABOVE the viewport when a flow revisits an earlier
    // card), retry upward.
    final vertical = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    for (final d in [delta, -delta]) {
      for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
        await tester.drag(vertical, Offset(0, -d));
        await tester.pumpAndSettle();
      }
      if (finder.evaluate().isNotEmpty) break;
    }
    expect(
      finder,
      findsWidgets,
      reason: 'scrollTo exhausted both directions without finding the target',
    );
    await tester.ensureVisible(finder.first);
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

  /// Adds one vocab ingredient through the 7.7 two-step chain: picker v2
  /// (search the synced vocab) → the quantity + unit-chip sheet (type the
  /// quantity, optionally tap a measure/unit [chip], Done). Asserts the
  /// picker actually searched the synced vocab.
  Future<void> addIngredient(
    WidgetTester tester,
    String name,
    String qty, {
    String? chip,
  }) async {
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    // The picker sheet's search field is the last EditableText (overlay).
    await tester.enterText(find.byType(EditableText).last, name.toLowerCase());
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
    // The quantity sheet: its qty field is the overlay's last EditableText.
    await tester.enterText(find.byType(EditableText).last, qty);
    await tester.pump();
    if (chip != null) {
      await tester.tap(find.text(chip).last);
      await tester.pump();
    }
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  // ---------------------------------------------------------------------------
  // 1 · AUTH — sign in through the gate, out the other side of /connecting.
  // ---------------------------------------------------------------------------
  testWidgets('1 auth: signs in and reaches the synced Library', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
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
    // …and the starter measures cloned with it (step 7.6): "clove (3 g)" on
    // Garlic is what scenario 2 picks in the editor's unit dropdown.
    final measures = await db.get(
      'SELECT COUNT(*) AS c FROM ingredient_measure',
    );
    expect(measures['c'] as int, greaterThan(10));
  });

  // ---------------------------------------------------------------------------
  // 2 · LIBRARY — the pre-auth filing smoke, now behind the gate.
  // ---------------------------------------------------------------------------
  testWidgets('2 library: files a new recipe under a new section', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
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

    // Garlic through the 7.7 chain, quantified in its synced measure: the
    // chip row offers the vocab measures cloned at onboarding — but first,
    // author a manual measure through the sheet's manage state (the 7.7
    // measure editor) and prove it lands with source 'manual'.
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'garlic');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Garlic').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '3');
    await tester.pump();
    // Manage measures: add "big clove = 5 g" (saved as yours), which lands
    // selected as the line's chip. The manage chip (a plus ICON — the glyph
    // rule bans raw ＋ text) trails the row, so scroll the (horizontal,
    // lazy) chip row until it builds.
    final manageChip = find.descendant(
      of: find.byType(UnitChipRow),
      matching: find.byIcon(FLucideIcons.plus),
    );
    await tester.dragUntilVisible(
      manageChip,
      find.descendant(
        of: find.byType(UnitChipRow),
        matching: find.byType(Scrollable),
      ),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(manageChip);
    await tester.pumpAndSettle();
    // The manage state holds the add form (label + amount) and the density
    // entry's field (7.8). Scope everything to the sheet: the editor behind
    // it still holds its own fields and Save button — within the sheet the
    // add form's fields lead and its Save comes before the density one.
    final sheetFields = find.descendant(
      of: find.byType(QuantityUnitEditor),
      matching: find.byType(EditableText),
    );
    await tester.enterText(sheetFields.at(0), 'big clove');
    await tester.enterText(sheetFields.at(1), '5');
    await tester.pump();
    await tester.tap(
      find
          .descendant(
            of: find.byType(QuantityUnitEditor),
            matching: find.text('Save'),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final manualMeasure = await db.getOptional(
      'SELECT source, basis_amount FROM ingredient_measure '
      "WHERE label = 'big clove' AND deleted_at IS NULL",
    );
    expect(manualMeasure, isNotNull, reason: 'the manual measure synced row');
    expect(manualMeasure!['source'], 'manual');
    expect(manualMeasure['basis_amount'], 5);
    // …then pick the seeded "clove" chip for the recipe's own line.
    await tester.tap(find.text('clove').last);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await addIngredient(tester, 'Onion', '1');

    // Two method steps — `recipe.steps` is a jsonb column, so these must
    // survive the upload round-trip as a real array (the sweep's connector
    // fix; the old double-encoding crashed the recipe view within a second).
    await scrollTo(tester, find.text('METHOD'));
    await tester.enterText(
      find.byType(EditableText).last,
      'Brown the aromatics.\nSimmer until thick.',
    );
    await tester.pump();

    await scrollTo(tester, find.text('Save'), delta: -150);
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK · WEEKNIGHT'));
    expect(find.text('Chicken Curry'), findsOneWidget); // the rendered title

    // The write reached the local database, fully filed.
    final recipe = await db.get(
      'SELECT id, keeps_for_days, book_id, section_id FROM recipe '
      "WHERE title = 'Chicken Curry' AND deleted_at IS NULL",
    );
    expect(recipe['keeps_for_days'], 2);
    expect(recipe['book_id'], isNotNull);
    expect(recipe['section_id'], isNotNull);
    final items = await db.getAll(
      'SELECT li.quantity, li.unit, li.measure_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    );
    expect(items, hasLength(2));
    expect(items.first['quantity'], 3);
    // The Garlic line persisted its measure FK, with the honest count unit as
    // the stored fallback ("3 clove" degrades to "3 piece", never invented
    // grams — step 7.6).
    expect(items.first['measure_id'], isNotNull);
    expect(items.first['unit'], 'piece');
    expect(items.last['quantity'], 1);
    expect(items.last['measure_id'], isNull);

    // After the server round-trip the view still stands and the steps are
    // still a real JSON array (not a double-encoded string).
    await waitForSyncRoundTrip(tester);
    expect(find.text('Chicken Curry'), findsOneWidget);
    final steps =
        jsonDecode(
              (await db.get('SELECT steps FROM recipe WHERE id = ?', [
                    recipe['id'],
                  ]))['steps']!
                  as String,
            )
            as List<dynamic>;
    expect(steps, ['Brown the aromatics.', 'Simmer until thick.']);
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();
    expect(find.text('Brown the aromatics.'), findsOneWidget);
    expect(find.text('Simmer until thick.'), findsOneWidget);

    // Favorite the recipe from its header menu (the 7.7 Favorites
    // affordance) — the picker's Favorites tab reads this flag in scenario 3.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();
    await waitForDb(tester, () async {
      final row = await db.get('SELECT favorite FROM recipe WHERE id = ?', [
        recipe['id'],
      ]);
      return row['favorite'] == 1;
    }, 'the favorite flag to persist');
    // Dismiss the still-open popover with an outside tap.
    await tester.tapAt(const Offset(40, 300));
    await tester.pumpAndSettle();

    // Re-open and edit the saved recipe (tweak Garlic 3 → 4). The diffing
    // `saveRecipe` must leave every kept child live — the old delete-reinsert
    // tombstoned the children server-side on any edit.
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.text('Edit recipe'));
    await scrollTo(tester, find.text('Garlic'));
    // The line's quantity control ("3 clove") re-opens the quantity sheet.
    await tester.tap(find.text('3 clove'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, '4');
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK · WEEKNIGHT'));

    // Ingredients survive the edit's server round-trip: rendered and live in
    // the local db, with the one tweaked quantity. (Back to the Ingredients
    // tab first — `context.go` after save keeps the same route element, so
    // the Method tab chosen above is still selected.)
    await waitForSyncRoundTrip(tester);
    await tester.tap(find.text('Ingredients'));
    await tester.pumpAndSettle();
    expect(find.text('Garlic'), findsOneWidget);
    expect(find.text('Onion'), findsOneWidget);
    final editedItems = await db.getAll(
      'SELECT li.quantity FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    );
    expect(editedItems.map((r) => r['quantity']).toList(), [4, 1]);
  });

  // ---------------------------------------------------------------------------
  // 3 · WEEK — copy-last-week, the two-step add flow, eaters, per-person lens.
  // ---------------------------------------------------------------------------
  testWidgets('3 week → cook → shop over the real local db', (tester) async {
    ignoreForuiSemanticsAssertion();
    await openLibrary(tester);

    // Runs with LIVE sync: every planned entry below round-trips through the
    // server, so `plan_entry.eaters` (a jsonb column) must come back down as
    // a real array — the explicit round-trip check after the edit-eaters step
    // pins that. (Kept as one testWidgets: 3a–3c build on each other's data,
    // and one launch keeps the suite fast; live-sync coverage is what
    // mattered, not the split.)

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
    // The Favorites tab (7.7) holds the recipe starred in scenario 2.
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

    // The jsonb round-trip check: after the server echoes the edit back down,
    // `eaters` must still parse as an array of member ids (the old connector
    // double-encoded it into a string, crashing every parser).
    await waitForSyncRoundTrip(tester);
    final roundTripped = await currentEntries();
    expect(jsonDecode(roundTripped.last['eaters']! as String), [
      adaId,
    ], reason: 'plan_entry.eaters must survive live sync as a real JSON array');

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
  });

  // ---------------------------------------------------------------------------
  // 4 · IMPORT — paste a link → review → resolve every line → Save, over live
  //     sync. NO LLM AND NO NETWORK on the import path:
  //     `importRepositoryProvider` is overridden to `SqliteImportRepository`,
  //     the same local repository the app uses when Supabase is unconfigured.
  //     That is the fake edge function — it returns the canned payload and
  //     RE-RESOLVES its candidates against the household's really-synced
  //     vocab, so the auto/suggest/none bands below are produced by real data,
  //     not by the fixture. Only the extract+match hop is stubbed; the
  //     reconciliation UI, the commit write path, PowerSync and the Library are
  //     all the real thing.
  // ---------------------------------------------------------------------------

  /// The review card for flattened line [i] (`ValueKey('review-line-$i')`).
  Finder reviewCard(int i) => find.byKey(ValueKey('review-line-$i'));

  /// Expands card [i] if it is still compact. The collapsed card has exactly
  /// one pencil; once expanded the AMOUNT chip carries one too, so guard on
  /// the 'AMOUNT' label instead.
  Future<void> expandLine(WidgetTester tester, int i) async {
    await scrollTo(tester, reviewCard(i));
    final expanded = find.descendant(
      of: reviewCard(i),
      matching: find.text('AMOUNT'),
    );
    if (expanded.evaluate().isNotEmpty) return;
    final pencil = find.descendant(
      of: reviewCard(i),
      matching: find.byIcon(FLucideIcons.pencil),
    );
    await tester.ensureVisible(pencil.first);
    await tester.pumpAndSettle();
    await tester.tap(pencil.first);
    await tester.pumpAndSettle();
  }

  /// Whether card [i] currently shows [text].
  bool lineShows(int i, String text) => find
      .descendant(of: reviewCard(i), matching: find.text(text))
      .evaluate()
      .isNotEmpty;

  /// Resolves an unmatched (`none`) line by creating a new ingredient stub:
  /// open the seeded search sheet, then take its create-new footer.
  Future<void> createStubForLine(WidgetTester tester, int i) async {
    await expandLine(tester, i);
    final open = find.descendant(
      of: reviewCard(i),
      matching: find.text('Find or create ingredient'),
    );
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    await tester.tap(open);
    await tester.pumpAndSettle();
    // The sheet seeds create-new with the raw line text, so the two identical
    // "Aleppo chilli flakes" lines default to the same name and coalesce.
    final create = find.textContaining('as a new ingredient');
    expect(create, findsOneWidget, reason: 'the create-new footer for line $i');
    await tester.tap(create);
    await tester.pumpAndSettle();
  }

  /// Picks a printed range's number by confirming the amount sheet, which opens
  /// on the printed low endpoint (a real value, never an invented one).
  Future<void> pickRangeAmountForLine(WidgetTester tester, int i) async {
    await expandLine(tester, i);
    final chip = find.descendant(
      of: reviewCard(i),
      matching: find.byType(AmountEditor),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  testWidgets('4 import: link → review → resolve → saved recipe in the '
      'Library', (tester) async {
    ignoreForuiSemanticsAssertion();

    // The canned payload's `suggest` line only lands in the suggest band if the
    // household vocab actually holds a Parmesan row for it to re-point at.
    // Assert that up front so a vocab change fails HERE, with a clear reason,
    // rather than as a mystery finder miss further down.
    final parmesanRows = await db.getAll(
      'SELECT canonical_name FROM ingredient '
      "WHERE canonical_name LIKE '%armesan%' AND deleted_at IS NULL",
    );
    expect(
      parmesanRows,
      hasLength(1),
      reason:
          'scenario 4 needs exactly one %armesan% vocab row: the suggest '
          'line re-points at it and the "did you mean" pill carries its name',
    );

    await openLibraryWithLocalImport(tester);

    // The Library's header ＋ menu → Import a recipe.
    await tester.tap(
      find
          .descendant(
            of: find.byType(FHeaderAction),
            matching: find.byIcon(FLucideIcons.plus),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import a recipe'));
    await tester.pumpAndSettle();

    expect(find.text('Import a recipe'), findsWidgets); // the header
    await tester.enterText(
      find.byType(EditableText).first,
      'https://example.com/weeknight-tomato-pasta',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from link'));
    await pumpUntilFound(tester, find.text('Review recipe'));

    // The extraction arrived, grouped, with every line surfaced for review.
    expect(find.text('Weeknight Tomato Pasta'), findsOneWidget);
    expect(find.text('To finish'), findsOneWidget); // the named group
    expect(find.text('INGREDIENTS'), findsOneWidget);
    // Nothing is auto-committed: the header counts what still wants a look.
    expect(find.textContaining('to review'), findsOneWidget);

    // MATCHING really ran against the synced vocab: line 0 (spaghetti) arrived
    // auto-matched, so it needs nothing from the user.
    await expandLine(tester, 0);
    expect(lineShows(0, 'Match an ingredient'), isFalse);
    expect(lineShows(0, 'Spaghetti'), isTrue);

    // Line 1 — an auto match whose amount is a printed RANGE ("2–3 cloves").
    // The ingredient is locked; only the number is outstanding.
    await expandLine(tester, 1);
    expect(lineShows(1, 'Set the amount'), isTrue);
    await pickRangeAmountForLine(tester, 1);
    expect(lineShows(1, 'Set the amount'), isFalse);

    // Line 5 — the `suggest` band: confirm the "did you mean" pill onto an
    // EXISTING vocab row rather than creating a stub.
    //
    // The fake repository re-points the candidate at whatever the household
    // vocab really holds AND takes that row's canonical name, so the pill is
    // labelled with the vocab row's name (e.g. "Vegan Parmesan"), not the
    // canned payload's "Parmesan". Derive the expected label from the vocab
    // (queried by the precondition at the top of this test) so a reseed fails
    // loudly rather than as a mystery finder miss.
    final pillLabel = parmesanRows.single['canonical_name'] as String;
    await expandLine(tester, 5);
    expect(lineShows(5, 'Did you mean'), isTrue);
    final pill = find.descendant(
      of: reviewCard(5),
      matching: find.text(pillLabel),
    );
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(lineShows(5, 'Did you mean'), isFalse);

    // Everything still unmatched (`none`) becomes a new ingredient stub. The
    // two identical chilli lines seed the same name, so they must coalesce onto
    // ONE created ingredient at commit.
    for (final i in [2, 3, 4, 6]) {
      // Expand FIRST: a below-the-fold ListView child isn't built at all, so
      // probing its labels before scrolling to it always reads "clean" and the
      // loop would silently skip the line (exactly how the gate stayed locked
      // on the first on-sim run of this tail).
      await expandLine(tester, i);
      if (lineShows(i, 'Match an ingredient') ||
          lineShows(i, 'Find or create ingredient')) {
        await createStubForLine(tester, i);
      }
    }

    // Every line is clean → the header count flips and Save unlocks. Scroll to
    // the footer button in EITHER state so a still-locked gate fails with the
    // button's own message ("N line(s) need you") rather than a finder miss.
    final footer = find.textContaining(RegExp('Save recipe|need you'));
    await scrollTo(tester, footer);
    expect(
      find.text('Save recipe'),
      findsOneWidget,
      reason:
          'the Save gate is still locked: '
          '${tester.widget<Text>(footer.first).data}',
    );
    expect(find.text('looks good'), findsOneWidget);
    await tester.tap(find.text('Save recipe'));

    // The commit routes to the saved recipe's page.
    await pumpUntilFound(tester, find.text('Weeknight Tomato Pasta'));
    await tester.pumpAndSettle();

    // --- what actually landed in the local database --------------------------
    final recipe = await db.get(
      "SELECT id, book_id, steps FROM recipe WHERE title = 'Weeknight Tomato "
      "Pasta' AND deleted_at IS NULL",
    );
    final recipeId = recipe['id'] as String;

    // FILED: the Library renders books and skips book-less recipes, so an
    // imported recipe with a null book_id would save into a place nothing
    // shows it.
    expect(recipe['book_id'], isNotNull);

    // Tokenized method steps, with refs remapped from line_index to real
    // line_item ids (§4.6) — never a plain-text step list.
    final steps = jsonDecode(recipe['steps'] as String) as List;
    expect(steps, hasLength(3));
    final lineIds = (await db.getAll(
      'SELECT li.id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.deleted_at IS NULL',
      [recipeId],
    )).map((r) => r['id'] as String).toSet();
    expect(lineIds, hasLength(7));
    final refs = [
      for (final s in steps)
        for (final t in (s as Map)['tokens'] as List)
          if ((t as Map)['t'] == 'ref') ...(t['refs'] as List).cast<String>(),
    ];
    expect(refs, isNotEmpty);
    for (final ref in refs) {
      expect(
        lineIds,
        contains(ref),
        reason: 'a step ref still points at a line_index, not a line_item_id',
      );
    }

    // Every line resolved to a real ingredient, and the duplicate no-match
    // lines coalesced onto ONE created stub.
    final unresolved = await db.get(
      'SELECT COUNT(*) AS c FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.ingredient_id IS NULL',
      [recipeId],
    );
    expect(unresolved['c'] as int, 0);
    final chilliStubs = await db.getAll(
      "SELECT id FROM ingredient WHERE source = 'import_stub' "
      "AND canonical_name LIKE '%chilli flakes%' AND deleted_at IS NULL",
    );
    expect(chilliStubs, hasLength(1));

    // It SYNCED — the whole point of running this on a device.
    await waitForSyncRoundTrip(tester);

    // …and it is visible in the Library, filed under a book. The recipe page
    // sits OUTSIDE the tab shell (no bottom nav here); its header back action
    // pops — or, after the commit's `context.go`, falls back to `/` — either
    // way landing on the Library.
    await tester.tap(find.byType(FHeaderAction).first);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await tester.pumpAndSettle();
    expect(
      find.text('Weeknight Tomato Pasta'),
      findsWidgets,
      reason: 'the imported recipe never appeared in the Library',
    );
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
