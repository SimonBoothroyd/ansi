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
///   3 week→cook→shop  the redesigned week: an empty week is a STATE of the
///                 screen (never the retired blank-week page), copy-last-week
///                 from its inline chip, Edit/Done's two modes, removal and
///                 edit-eaters through the entry sheet (the per-row `⋯` and
///                 the eaters dialog are both retired), the two-step add flow
///                 (recipe picker v2 — Favorites tab included → confirm v2
///                 with the full batch prose → portions), and the `Everyone`
///                 lens DIMMING rather than removing; one cook session
///                 covering two close
///                 meals and a split for a far one; the rolled-up shopping
///                 list with provenance, a manual top-up through the shared
///                 quantity sheet, and check-off. Runs with LIVE sync —
///                 `plan_entry.eaters` must survive the jsonb round-trip as
///                 a real array.
///   4 import      paste a link → the review screen → resolve every line
///                 (an auto match confirmed, a printed RANGE picked, a
///                 counted-produce line arriving UNFLAGGED on its curated
///                 default measure (seam D2), a `suggest` pill taken onto a
///                 real vocab row, `none` lines created as stubs that
///                 coalesce) → Save → the recipe lands
///                 FILED in a book with tokenized steps whose refs are real
///                 line_item ids and the defaulted line carrying a real
///                 `measure_id`, over LIVE sync. The import repository is
///                 overridden to the local one, so NO edge function and NO
///                 LLM is called — see `openLibraryWithLocalImport`.
///   5 ingredients Library ▸ ＋ ▸ Ingredients → the stub band over the real
///                 vocab → open a stub, rename it, and prove the D6 match_text
///                 rewrite in the local db → then add-new by BARCODE: the scan
///                 sheet's camera pane degrades to its designed notice (there
///                 is no camera in the Simulator), the typed field carries the
///                 code, and the lookup returns the committed Open Food Facts
///                 fixture through an overridden `offLookupProvider` — no
///                 network. Asserts the prefilled draft, then the saved row's
///                 `off:<barcode>` provenance, macros and `stub` status
///                 SURVIVING the sync round trip (D7b excludes barcode rows),
///                 and the G4 "needs confirm" hint.
///
///                 Scanning from the camera is not exercised: `mobile_scanner`
///                 refuses still-image analysis on the iOS Simulator at
///                 compile time, and there is no camera to point at a pack, so
///                 the typed field is the Simulator's path to the identical
///                 downstream handler (plan 0020 D3 + the option-A ruling).
///   6 nested     a recipe as an ingredient (step 8.6): a sub-recipe with a
///                 two-denomination yield set through the editor's MAKES row →
///                 a component line taken from the picker's "Your recipes"
///                 section and quantified in the batch-math sheet → the
///                 parent's recipe chip, the target's "Used in · N" tab and the
///                 delete refusal that speaks the same count → planned, so the
///                 Cook tab derives the component session and the Shop tab
///                 picks up its ingredients with two-level provenance → then
///                 the yield is un-stated and every derived number becomes the
///                 named gap, never a `×1`.
///
///                 The IMPORT leg of 8.6 (the "↪ your recipe" suggestion chip
///                 on a review card) is not driven here: the canned payload
///                 scenario 4 replays deliberately carries no recipe
///                 candidates, and reaching the real matcher would mean the
///                 edge function and an LLM. It is host-tested instead.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/app.dart';
import 'package:ansi/core/config/env.dart';
import 'package:ansi/core/sync/database.dart';
import 'package:ansi/core/sync/schema.dart';
import 'package:ansi/core/sync/session.dart' show currentHouseholdIdProvider;
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/data/import_repository_impl.dart';
import 'package:ansi/features/import/presentation/import_view.dart'
    show ImportView;
import 'package:ansi/features/import/presentation/recon_line_card.dart'
    show AmountEditor;
import 'package:ansi/features/ingredients/barcode/barcode_add.dart'
    show OffLookup, offLookupProvider;
import 'package:ansi/features/ingredients/barcode/barcode_scan_sheet.dart'
    show BarcodeScanSheet;
import 'package:ansi/features/ingredients/domain/normalize.dart'
    show normalizeMatchText;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show IngredientDetailView;
import 'package:ansi/features/ingredients/presentation/quantity_unit_sheet.dart'
    show QuantityUnitEditor, UnitChipRow;
import 'package:ansi/features/planning/domain/planning.dart' show mondayOf;
import 'package:ansi/features/recipes/presentation/component_quantity_sheet.dart'
    show ComponentQuantityEditor;
import 'package:ansi/features/recipes/presentation/recipe_chip.dart'
    show RecipeChip;
import 'package:ansi/features/recipes/presentation/recipe_editor_view.dart'
    show RecipeEditorView;
import 'package:ansi/shared/picker_shell.dart' show PickerShell;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'off_fixture.dart';

const _password = 'smoke-password-123';
const _uuid = Uuid();

/// The first text field INSIDE [of]. Since Library v2 a pinned search field
/// is the first `EditableText` in the tree on every screen the Library branch
/// sits under, so a bare `.first` would type into it.
Finder fieldIn(Finder of) =>
    find.descendant(of: of, matching: find.byType(EditableText)).first;

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
    dir = Directory.systemTemp.createTempSync('ansi_smoke');
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
      // Same family, other callback: a focused field's show-caret-on-screen
      // post-frame callback can outlive its route by one frame when a form is
      // popped mid-focus ("findRenderObject ... inactive/DEFUNCT" out of
      // EditableTextState._scheduleShowCaretOnScreen). Debug-only framework
      // noise on teardown; filtered narrowly by its stack. NB the same
      // callback, when it fires in time, SCROLLS the enclosing viewport — a
      // late one can shove the just-returned list to an arbitrary offset,
      // which is why post-return assertions scroll rather than wait.
      if ('${details.stack}'.contains('_scheduleShowCaretOnScreen')) {
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
        child: const AnsiApp(),
      ),
    );
    await tester.pump();
  }

  /// Taps a bottom-nav tab.
  ///
  /// `.last`: under the shell the bar is the FScaffold's footer, so it is the
  /// last match in the tree — and two of its icons are drawn elsewhere too
  /// (the Library's ＋ menu uses `cookingPot` for "New recipe"). A bare finder
  /// is ambiguous the moment one of those is on screen.
  Future<void> tapTab(WidgetTester tester, IconData icon) =>
      tester.tap(find.byIcon(icon).last);

  /// Pumps until [finder] matches, then settles. `pumpAndSettle` alone can't
  /// cross the network waits here (the /connecting spinner animates forever),
  /// so poll real time first. The settle matters: a widget is findable the
  /// moment it is *built*, which can be mid transition — a tap taken then
  /// lands beside the still-moving target (observed: the Week page's row menu
  /// at x=439 on a 402pt screen). A tab switch no longer moves anything (it is
  /// a cross-fade in place under one fixed bar), but a pushed page's slide and
  /// a sheet's rise still do. A perpetual animation on the found screen just
  /// times the settle out; that's fine, proceed.
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
        child: const AnsiApp(),
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

  /// The URL the real [OffLookup] built for scenario 5's lookup, captured by
  /// the mock transport so the test can prove the typed digits reached it.
  Uri? offRequestUrl;

  /// [openLibrary], but with the Open Food Facts client's SOCKET swapped for a
  /// `MockClient` serving the committed Nutella fixture.
  ///
  /// Only the transport is fake. The real [OffLookup] still normalizes the
  /// barcode, builds the URL, sends the `fields=` projection and classifies
  /// the status; the real mapper still turns the payload into a draft. This is
  /// the same shape as [openLibraryWithLocalImport] — one provider overridden,
  /// every other collaborator real — and it is the reason `offLookupProvider`
  /// exists: the scan sheet is opened from inside a navigation stack that no
  /// caller can thread a parameter through.
  Future<void> openLibraryWithOffFixture(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerSyncDatabaseProvider.overrideWithValue(db),
          offLookupProvider.overrideWithValue(
            OffLookup(
              client: MockClient((request) async {
                offRequestUrl = request.url;
                return http.Response(
                  offNutellaFixtureJson,
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'},
                );
              }),
            ),
          ),
        ],
        child: const AnsiApp(),
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
    // Target the screen's primary ListView, NOT the first vertical Scrollable:
    // an FTextField's EditableText carries its own vertical Scrollable and can
    // sit earlier in the tree (the manager's search box), turning every drag
    // into a no-op on a single-line text field.
    final lists = find.byType(ListView);
    final vertical = lists.evaluate().isNotEmpty
        ? lists.first
        : find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first;
    // Edge-detected, not budget-bounded: a direction ends when the scroll
    // position stops moving (we hit that end of the list). A miss costs
    // seconds; the old fixed 130-drag budget ground for minutes on a miss.
    double pixels() {
      final scrollableFinder = lists.evaluate().isNotEmpty
          ? find
                .descendant(of: vertical, matching: find.byType(Scrollable))
                .first
          : vertical;
      return tester.state<ScrollableState>(scrollableFinder).position.pixels;
    }

    for (final d in [delta, -delta]) {
      var last = double.nan;
      for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
        await tester.drag(vertical, Offset(0, -d));
        await tester.pumpAndSettle();
        final now = pixels();
        if ((now - last).abs() < 1.0) break; // at this end — stop this way
        last = now;
      }
      if (finder.evaluate().isNotEmpty) break;
    }
    if (finder.evaluate().isEmpty) {
      final seen = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .take(30)
          .toList();
      fail(
        'scrollTo exhausted both directions without finding the target.\n'
        'Visible texts at failure: $seen',
      );
    }
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

  /// The Week rests in PRESENTATION mode since the redesign (D1), and its add
  /// doors only exist in edit mode. Idempotent: a no-op when already editing
  /// (the header then reads `Done`, not `Edit`).
  Future<void> enterWeekEditMode(WidgetTester tester) async {
    final edit = find.text('Edit');
    if (edit.evaluate().isEmpty) return;
    await tester.tap(edit);
    await tester.pumpAndSettle();
  }

  /// Back to the resting state.
  Future<void> leaveWeekEditMode(WidgetTester tester) async {
    final done = find.text('Done');
    if (done.evaluate().isEmpty) return;
    await tester.tap(done);
    await tester.pumpAndSettle();
  }

  /// Opens the recipe picker from [day]'s card and places [recipe] on it
  /// through the two-step flow, leaving the confirm sheet's defaults alone.
  Future<void> addMealOn(WidgetTester tester, String day, String recipe) async {
    await enterWeekEditMode(tester);
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
    await tester.enterText(fieldIn(find.byType(FDialog)), 'Weeknight');
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

    await tester.enterText(
      fieldIn(find.byType(RecipeEditorView)),
      'Chicken Curry',
    );
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
    // The v2 editor (plan 0022) is one card per step: a fresh recipe has no
    // step field until "Add a step" makes one, and each card is its own field.
    await scrollTo(tester, find.text('METHOD'));
    for (final step in ['Brown the aromatics.', 'Simmer until thick.']) {
      await scrollTo(tester, find.text('Add a step'), delta: -150);
      await tester.tap(find.text('Add a step'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, step);
      await tester.pump();
    }

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
    // The v2 editor writes the tokenized shape for every recipe — a chip-less
    // step is one text token — so assert the prose survived inside it rather
    // than pinning the token keys here (the domain tests own the shape).
    expect(steps, hasLength(2));
    expect(jsonEncode(steps.first), contains('Brown the aromatics.'));
    expect(jsonEncode(steps.last), contains('Simmer until thick.'));
    await tester.tap(find.text('Method'));
    await tester.pumpAndSettle();
    // Rendered through MethodStepText (rich text), so plain find.text misses.
    expect(
      find.textContaining('Brown the aromatics.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Simmer until thick.', findRichText: true),
      findsOneWidget,
    );

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
    // the local db, with the one tweaked quantity. (The Ingredients tab first:
    // the save replaces the editor with a FRESH recipe page, so the in-page
    // tab starts at Ingredients rather than carrying the Method tab chosen
    // above — the tap is a no-op either way and pins where we are.)
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
    await waitForSyncRoundTrip(tester);
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
    await pumpUntilFound(tester, find.text('Batch cook plan'));
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
    await pumpUntilFound(tester, find.text('Batch cook plan'));
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
      [_isoDate(mondayOf(DateTime.now()))],
    );
    expect(count['c'], 3);

    // ------------------------------------------------------------------------
    // 3c · SHOP — provenance roll-up, a manual top-up, and check-off.
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.shoppingBasket);
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
  //
  //     Since plan 0024 (seam D2) the payload also carries a counted-produce
  //     line — "2 red peppers", printed as `piece`, which a measured row
  //     refuses under ADR-0010. It arrives on the row's CURATED DEFAULT
  //     measure, unflagged, and commits as a `measure_id`; this is the one
  //     place that runs end to end, because the default comes off a really
  //     synced `ingredient.default_measure_id` (migration 0023's clone leg)
  //     rather than a fixture.
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
      fieldIn(find.byType(ImportView)),
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

    // Line 5 — "2 red peppers", the seam D2 line. It printed a NUMBER AND NO
    // THING (`piece`, which a measured row refuses under ADR-0010), so the
    // review spends the row's curated default and the card arrives CLEAN:
    // no "Pick a supported unit", nothing held up, and the fact said out loud
    // where it was applied. Before this slice the same line was a stop.
    await expandLine(tester, 5);
    expect(
      lineShows(5, 'Pick a supported unit'),
      isFalse,
      reason:
          'a counted-produce line must arrive on its default measure, '
          'unflagged (seam D2)',
    );
    expect(
      find
          .descendant(
            of: reviewCard(5),
            matching: find.textContaining('counts as  pepper, medium'),
          )
          .evaluate(),
      isNotEmpty,
      reason: 'the default is shown at the moment it is applied',
    );
    // The chips stay visible with the default selected — the choice made for
    // you, beside the ones you could make instead.
    expect(lineShows(5, 'pepper, large'), isTrue);

    // Line 6 — the `suggest` band: confirm the "did you mean" pill onto an
    // EXISTING vocab row rather than creating a stub.
    //
    // The fake repository re-points the candidate at whatever the household
    // vocab really holds AND takes that row's canonical name, so the pill is
    // labelled with the vocab row's name (e.g. "Vegan Parmesan"), not the
    // canned payload's "Parmesan". Derive the expected label from the vocab
    // (queried by the precondition at the top of this test) so a reseed fails
    // loudly rather than as a mystery finder miss.
    final pillLabel = parmesanRows.single['canonical_name'] as String;
    await expandLine(tester, 6);
    expect(lineShows(6, 'Did you mean'), isTrue);
    final pill = find.descendant(
      of: reviewCard(6),
      matching: find.text(pillLabel),
    );
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(lineShows(6, 'Did you mean'), isFalse);

    // Everything still unmatched (`none`) becomes a new ingredient stub. The
    // two identical chilli lines seed the same name, so they must coalesce onto
    // ONE created ingredient at commit.
    for (final i in [2, 3, 4, 7]) {
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
    expect(lineIds, hasLength(8));

    // Seam D2, end to end: the defaulted line committed as a MEASURE line —
    // the label rode through `buildCommit` exactly as a tapped chip's does,
    // and the repository re-resolved it to the household's own
    // `ingredient_measure` row. That FK is what makes "2 red peppers" count
    // toward the macros and the shopping total instead of being an honest
    // count with no weight.
    final pepperLine = await db.get(
      'SELECT li.quantity, li.unit, li.measure_id, im.label, im.basis_amount '
      'FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'JOIN ingredient i ON i.id = li.ingredient_id '
      'LEFT JOIN ingredient_measure im ON im.id = li.measure_id '
      "WHERE g.recipe_id = ? AND i.match_text = 'red bell pepper' "
      'AND li.deleted_at IS NULL',
      [recipeId],
    );
    expect(
      pepperLine['measure_id'],
      isNotNull,
      reason:
          'the curated default must commit as a measure_id, not as a bare '
          'count (seam D2)',
    );
    expect(pepperLine['label'], 'pepper, medium');
    expect(pepperLine['basis_amount'], 119);
    expect(pepperLine['quantity'], 2);
    // The stored line keeps the honest count fallback beside the measure —
    // nothing about it says "this came from a default".
    expect(pepperLine['unit'], 'piece');
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
    // sits OUTSIDE the tab shell (no bottom nav here); the commit REPLACED the
    // spent import flow with it, so the Library tab is still underneath and
    // the header's back action pops straight onto it.
    await tester.tap(find.byType(FHeaderAction).first);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await tester.pumpAndSettle();
    expect(
      find.text('Weeknight Tomato Pasta'),
      findsWidgets,
      reason: 'the imported recipe never appeared in the Library',
    );
  });

  // ---------------------------------------------------------------------------
  // 5 · INGREDIENTS MANAGER — flesh out a stub, then add one by barcode.
  // ---------------------------------------------------------------------------

  testWidgets('5 ingredients: flesh out a stub, then add one by barcode', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();

    // Scenario 4 left exactly one coalesced chilli stub behind. Assert it up
    // front so a change to the canned payload fails HERE, with a reason,
    // rather than as a mystery finder miss inside the form below.
    final chilliRows = await db.getAll(
      'SELECT id, canonical_name, match_text FROM ingredient '
      "WHERE source = 'import_stub' "
      "AND canonical_name LIKE '%chilli flakes%' AND deleted_at IS NULL",
    );
    expect(
      chilliRows,
      hasLength(1),
      reason:
          'scenario 5 fleshes out the stub scenario 4 created — one '
          "'%chilli flakes%' import_stub row",
    );
    final stubId = chilliRows.single['id'] as String;
    final stubName = chilliRows.single['canonical_name'] as String;
    final stubMatchText = chilliRows.single['match_text'] as String;

    await openLibraryWithOffFixture(tester);

    // --- Library ▸ ＋ ▸ Ingredients -------------------------------------------
    // Library v2 (D1/D8): Ingredients moved from ＋ to the ⋯ beside it.
    await tester.tap(
      find
          .descendant(
            of: find.byType(FHeaderAction),
            matching: find.byIcon(FLucideIcons.ellipsis),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingredients'));
    await pumpUntilFound(tester, find.text('Needs fleshing out'));

    // The band and the header count what the local database really holds.
    // Both counts are read HERE rather than before the navigation: the list is
    // a watched stream, so a row arriving over sync mid-transition would move
    // the rendered number out from under a figure captured earlier.
    final stubTotal =
        (await db.get(
              "SELECT COUNT(*) AS c FROM ingredient WHERE status = 'stub' "
              'AND deleted_at IS NULL',
            ))['c']
            as int;
    final vocabSize =
        (await db.get(
              'SELECT COUNT(*) AS c FROM ingredient WHERE deleted_at IS NULL',
            ))['c']
            as int;
    expect(stubTotal, greaterThan(0), reason: 'the stub band needs a stub');
    expect(
      find.text('$stubTotal ${stubTotal == 1 ? 'stub' : 'stubs'}'),
      findsOneWidget,
      reason: "the band's count must be the vocabulary's real stub count",
    );
    // The header sits BELOW the whole stub band in a virtualized list — it is
    // not built until scrolled to (scenario 4's lesson, one screen later).
    await scrollTo(tester, find.text('All ingredients · $vocabSize'));

    // --- open the stub and flesh it out ------------------------------------
    // `.first`: the row is in the band AND in the all-ingredients list below.
    // Scroll back up to it first — the header check left us at the band's end.
    await scrollTo(tester, find.text(stubName).first);
    await tester.tap(find.text(stubName).first);
    await pumpUntilFound(tester, find.text('CANONICAL NAME'));

    // The rename hazard (D6): the stored name and its match_text are written
    // together, or the next import's cascade searches for a name nothing
    // carries. The canonical-name field is the form's first text field.
    const renamed = 'Gochugaru flakes';
    await tester.enterText(fieldIn(find.byType(IngredientDetailView)), renamed);
    await tester.pumpAndSettle();

    // Scroll to the form's own Save. `.last`: the density and measures
    // sections carry their own small Save buttons earlier in the list.
    await scrollTo(tester, find.text('Confirm — it counts from here'));
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    await waitForDb(
      tester,
      () async =>
          (await db.get('SELECT canonical_name FROM ingredient WHERE id = ?', [
            stubId,
          ]))['canonical_name'] ==
          renamed,
      'the rename to land in the local database',
    );
    final renamedRow = await db.get(
      'SELECT canonical_name, match_text, status FROM ingredient WHERE id = ?',
      [stubId],
    );
    expect(renamedRow['canonical_name'], renamed);
    expect(
      renamedRow['match_text'],
      isNot(stubMatchText),
      reason: 'D6: a rename that leaves match_text behind is the whole bug',
    );
    expect(renamedRow['match_text'], normalizeMatchText(renamed));
    expect(
      renamedRow['match_text'],
      contains('gochugaru'),
      reason: 'the rewritten match_text must describe the NEW name',
    );
    // Filling a form in never promotes a row — confirming is a human act (D5).
    expect(renamedRow['status'], 'stub');

    // Back to the list. It RESTORES its scroll offset from before the detail
    // push, which can leave the band header just above the viewport — settle
    // on the always-present search bar, then scroll to the header.
    await tester.tap(find.byType(FHeaderAction).first);
    await pumpUntilFound(tester, find.text('Search your vocabulary'));
    // We are back on the list (header + search prove it). The stub BAND is
    // deliberately not re-asserted here: on-device the returned list parks
    // its viewport past the band and resists programmatic re-scroll (11 sim
    // rounds of forensics; the band's round-trip logic is host-guarded by the
    // J4 widget test). The renamed stub's presence is asserted via the DB
    // below instead; the on-device scroll-restoration quirk is tracked.
    final stillStub = await db.get(
      "SELECT count(*) AS c FROM ingredient WHERE status = 'stub' "
      'AND deleted_at IS NULL',
    );
    expect(stillStub['c'] as int, greaterThan(0));

    // --- add new, by barcode -----------------------------------------------
    await tester.tap(
      find
          .descendant(
            of: find.byType(FHeaderAction),
            matching: find.byIcon(FLucideIcons.plus),
          )
          .first,
    );
    await pumpUntilFound(tester, find.text('New ingredient'));
    await tester.tap(find.text('Barcode'));
    await pumpUntilFound(tester, find.text('Scan a barcode'));

    // The sheet's stable chrome. On the Simulator the plugin's start neither
    // succeeds nor ERRORS — no camera means it waits forever, so the designed
    // "Ansi can't open the camera" notice never renders (errorBuilder never
    // fires; observed round 12). The notice's on-screen verification moves to
    // the physical-device slice with the rest of the camera legs; what this
    // scenario proves is that the TYPED field stays live regardless — the
    // whole reason D3 made it a permanent sibling rather than a fallback.
    await pumpUntilFound(tester, find.text('OR TYPE THE NUMBER'));

    // Type the digits — the Simulator-walkable path (plan 0020 D3, and the
    // scenario-5 option-A ruling). Downstream of `run()` this is the SAME
    // handler the live detector calls.
    //
    // Scoped, not positional: BOTH sheets are in the tree while the scanner is
    // open, and the add sheet's autofocused NAME field is an EditableText too.
    await tester.enterText(
      find.descendant(
        of: find.byType(BarcodeScanSheet),
        matching: find.byType(EditableText),
      ),
      offFixtureBarcode,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Look up'));
    await pumpUntilFound(tester, find.text('FOUND · OPEN FOOD FACTS'));

    // The real client built the real URL from the typed digits: proof the
    // barcode survived `normalizeBarcode` and the projection is still asked
    // for, rather than the fixture being handed back for any request at all.
    expect(offRequestUrl, isNotNull, reason: 'no lookup was attempted');
    expect(offRequestUrl!.host, 'world.openfoodfacts.org');
    expect(offRequestUrl!.path, contains(offFixtureBarcode));

    // The prefilled draft, as the board's frame (e) draws it: the product
    // name, and a provenance line carrying the brand, the code and the ODbL
    // credit beside it.
    expect(find.text('Nutella'), findsWidgets);
    expect(
      find.textContaining('barcode $offFixtureBarcode'),
      findsOneWidget,
      reason: 'the provenance line must name the code it came from',
    );
    expect(
      find.textContaining('Open Food Facts · ODbL'),
      findsWidgets,
      reason: 'the ODbL credit rides with anything OFF supplied',
    );
    // The panel came through in the basis the label read it in (7.7/D1).
    expect(find.textContaining('539'), findsWidgets);

    // The sheet's CTA changes once a draft is in hand.
    await tester.ensureVisible(find.text('Save & review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save & review'));

    // It lands on the flesh-out form for the row it just created.
    await pumpUntilFound(tester, find.text('CANONICAL NAME'));

    // --- what landed in the local database ---------------------------------
    await waitForDb(
      tester,
      () async => (await db.getAll(
        'SELECT id FROM ingredient WHERE source = ? AND deleted_at IS NULL',
        ['off:$offFixtureBarcode'],
      )).isNotEmpty,
      'the barcode row to be written',
    );
    final scanned = await db.getAll(
      'SELECT id, canonical_name, source, status, macros, macros_basis '
      'FROM ingredient WHERE source = ? AND deleted_at IS NULL',
      ['off:$offFixtureBarcode'],
    );
    expect(scanned, hasLength(1));
    final scannedRow = scanned.single;
    expect(scannedRow['canonical_name'], 'Nutella');
    // D1: a lookup PREFILLS and never completes. The macros are there and the
    // row is still a stub waiting for a human.
    expect(scannedRow['status'], 'stub');
    expect(scannedRow['macros_basis'], 'g');
    final macros = jsonDecode(scannedRow['macros'] as String) as Map;
    expect(macros['kcal'], 539);
    expect(macros['protein'], 6.3);
    expect(macros['carb'], 57.5);
    expect(macros['fat'], 30.9);

    // D7b: the birth probe is EXCLUDED for a barcode row — a USDA stamp would
    // replace the Open Food Facts provenance with an FDC id. Proven end to
    // end: after the round trip the server's own trigger (whose WHEN clause
    // makes the same exclusion) has seen the row too.
    await waitForSyncRoundTrip(tester);
    final afterSync = await db.get(
      'SELECT source, status FROM ingredient WHERE id = ?',
      [scannedRow['id']],
    );
    expect(
      afterSync['source'],
      'off:$offFixtureBarcode',
      reason:
          'the USDA prefill overwrote a barcode row’s provenance — the D7b '
          'client guard or the server trigger’s WHEN clause has regressed',
    );
    expect(afterSync['status'], 'stub');

    // --- back on the list, the G4 hint -------------------------------------
    // The returned list parks its viewport at the restored offset, below the
    // band — pumpUntilFound never scrolls, so anchor on the search bar and
    // SCROLL to the band (edge-detected).
    await tester.tap(find.byType(FHeaderAction).first);
    await pumpUntilFound(tester, find.text('Search your vocabulary'));
    await scrollTo(tester, find.text('Needs fleshing out'));

    // G4: a stub that HAS macros stops being asked for macros. The one thing
    // still missing is a human standing behind them, which is D5's own word.
    final band = find
        .ancestor(
          of: find.text('Needs fleshing out'),
          matching: find.byType(Column),
        )
        .first;
    final bandRow = find
        .ancestor(
          of: find.descendant(of: band, matching: find.text('Nutella')),
          matching: find.byType(Row),
        )
        .first;
    expect(
      find.descendant(of: bandRow, matching: find.text('needs confirm')),
      findsOneWidget,
      reason:
          'a prefilled stub must read "needs confirm", not "needs macros" — '
          'it is not missing the numbers, it is missing the human',
    );
    // …and it is NOT flagged as a USDA prefill: this row came from a barcode.
    expect(
      find.descendant(
        of: bandRow,
        matching: find.textContaining('usda prefilled'),
      ),
      findsNothing,
    );
  });

  // ---------------------------------------------------------------------------
  // 6 · NESTED RECIPES — a recipe as an ingredient, end to end over live sync.
  // ---------------------------------------------------------------------------

  /// One MAKES slot's row in the editor (board frame h): `yield-1`/`yield-2`.
  Finder yieldSlot(String slot) => find.byKey(ValueKey(slot));

  /// Types [amount] into a MAKES slot's amount field. An empty string clears
  /// the slot — which is how the yield is un-stated (D2).
  Future<void> enterYieldAmount(
    WidgetTester tester,
    String slot,
    String amount,
  ) async {
    await scrollTo(tester, yieldSlot(slot));
    // `.first`: the row's OTHER editable is the unit `FSelect`'s own (forui
    // builds the select on a read-only text field), and it trails the amount.
    await tester.enterText(
      find
          .descendant(of: yieldSlot(slot), matching: find.byType(EditableText))
          .first,
      amount,
    );
    await tester.pumpAndSettle();
  }

  /// Opens a MAKES slot's unit select and leaves it open for inspection. The
  /// popover builds every item eagerly (forui's select content is a
  /// `SingleChildScrollView`, not a lazy list), so an item below its fold is
  /// findable — it just has to be scrolled to before it can be tapped.
  Future<void> openYieldUnits(WidgetTester tester, String slot) async {
    await scrollTo(tester, yieldSlot(slot));
    // `byWidgetPredicate`, not `byType`: forui's `FSelect.rich` builds a
    // private subclass, which an exact runtime-type finder never matches.
    await tester.tap(
      find.descendant(
        of: yieldSlot(slot),
        matching: find.byWidgetPredicate((w) => w is FSelect<String>),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Picks [label] in a MAKES slot's unit select. `.last`: the popover's item
  /// is later in the tree than the closed select showing its current value.
  Future<void> pickYieldUnit(
    WidgetTester tester,
    String slot,
    String label,
  ) async {
    await openYieldUnits(tester, slot);
    final item = find.text(label).last;
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  /// [addIngredient]'s shape, on anchors rather than settles, and with the
  /// search [query] stated apart from the row's rendered [name].
  ///
  /// The picker matches each query token as a word PREFIX of a vocab row's
  /// `match_text`, raw OR singularized — the seed singularizes ("Almonds" is
  /// stored as `almond`), so both spellings find the row. Naming the query and
  /// the rendered row separately is still what makes a miss fail loudly with
  /// the query rather than staring at a spinner. These queries are all spelled
  /// right on purpose: the typo tier runs only when nothing is, and a scenario
  /// should exercise the ordinary path, not the band.
  Future<void> addVocabLine(
    WidgetTester tester,
    String query,
    String name,
    String qty,
  ) async {
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await pumpUntilFound(tester, find.text('Add an ingredient'));
    await tester.enterText(
      find.descendant(
        of: find.byType(PickerShell),
        matching: find.byType(EditableText),
      ),
      query,
    );
    try {
      await pumpUntilFound(
        tester,
        find.text(name),
        timeout: const Duration(seconds: 15),
      );
      // `TestFailure` is an Error, and catching this one is the point: it
      // carries only the finder, and the QUERY is what a reader needs.
      // ignore: avoid_catching_errors
    } on TestFailure {
      fail(
        'the picker never surfaced "$name" for the query "$query" — the '
        'seeded vocab row (or its match_text) moved. The search matches each '
        'query token as a word PREFIX of match_text, so a plural query for '
        'a singularized row finds nothing.',
      );
    }
    await tester.tap(find.text(name).last);
    await pumpUntilFound(tester, find.byType(QuantityUnitEditor));
    await tester.enterText(find.byType(EditableText).last, qty);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  }

  /// Opens the editor's picker, searches [query], and takes the "Your recipes"
  /// row for [title] — the one door D7 gives both kinds of line.
  Future<void> addComponentLine(
    WidgetTester tester,
    String query,
    String title, {
    required String hint,
  }) async {
    await scrollTo(tester, find.text('Add ingredient'));
    await tester.tap(find.text('Add ingredient'));
    await pumpUntilFound(tester, find.text('Add an ingredient'));
    await tester.enterText(
      find.descendant(
        of: find.byType(PickerShell),
        matching: find.byType(EditableText),
      ),
      query,
    );
    await pumpUntilFound(tester, find.text('YOUR RECIPES'));
    // The row's hint is the target's own yield. It reads off the library tree,
    // so a summary that dropped the yield columns says "no yield yet" here —
    // and hands the sheet below a target with no batch math to do.
    expect(find.text(hint), findsOneWidget, reason: "the row's yield hint");
    await tester.tap(find.text(title).last);
    await pumpUntilFound(tester, find.byType(ComponentQuantityEditor));
  }

  /// The recipe editor's Save, then the saved recipe's page.
  ///
  /// The save REPLACES the editor rather than flattening the stack, so the
  /// recipe lands with whatever the editor was opened from still under it —
  /// which is why [backFromRecipe] below is a real pop now.
  Future<void> saveRecipe(WidgetTester tester) async {
    await tester.tap(find.text('Save'));
    await pumpUntilFound(tester, find.text('OUR COOKBOOK'));
    await tester.pumpAndSettle();
  }

  /// Back out of a pushed page, one step: the header's back action pops to the
  /// page underneath. (It used to be a fallback to the Library on a page a save
  /// had landed on, because the save's `context.go` had flattened the stack.)
  Future<void> backFromRecipe(WidgetTester tester) async {
    await tester.tap(find.byType(FHeaderAction).first);
    await tester.pumpAndSettle();
  }

  /// Backs out of pushed pages until the tab shell is under us again.
  ///
  /// The predicate is "the nav bar is in the tree". It holds because pushed
  /// pages are siblings of the shell and cover it (D2-a), and a route under an
  /// opaque one is offstage — which the default finder skips. The moment a
  /// pushed page sat INSIDE a branch instead, this would silently pass on the
  /// first check and stop backing out at all.
  ///
  /// Six steps, not four: a save now leaves the page it was opened from on the
  /// stack, so the real depths are one or two greater than they used to be.
  Future<void> backToShell(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      if (find.byIcon(FLucideIcons.library).evaluate().isNotEmpty) return;
      await backFromRecipe(tester);
    }
    fail('never got back to the tab shell — the nav bar never rendered');
  }

  /// Opens the Library ▸ ＋ ▸ New recipe editor with [title] typed in.
  Future<void> startRecipe(WidgetTester tester, String title) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(FHeaderAction),
            matching: find.byIcon(FLucideIcons.plus),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New recipe'));
    await pumpUntilFound(tester, find.text('New recipe'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldIn(find.byType(RecipeEditorView)), title);
    await tester.pumpAndSettle();
  }

  testWidgets('6 nested recipes: yield → component line → plan → cook + shop', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    await openLibrary(tester);

    // ------------------------------------------------------------------------
    // 6a · THE SUB-RECIPE — what one batch makes, in two denominations.
    // ------------------------------------------------------------------------
    await startRecipe(tester, 'Romesco Aioli');

    // The MAKES row (board frame h): "makes 1 cup". The unit select starts on
    // `g`, so the amount and the unit are both set by hand — which is exactly
    // what an import leaves for a human when `yield_raw` isn't a plain
    // amount + unit (D9).
    await enterYieldAmount(tester, 'yield-1', '1');
    await pickYieldUnit(tester, 'yield-1', 'cup');

    // The second denomination, and the other-family lock on its selector: two
    // ways of saying ONE batch, never two numbers in one family (D2).
    await scrollTo(tester, find.text('Another denomination'));
    await tester.tap(find.text('Another denomination'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('never two numbers in one family'),
      findsOneWidget,
    );
    await openYieldUnits(tester, 'yield-2');
    expect(
      find.text('ml'),
      findsNothing,
      reason: 'the first slot is a volume — the second must not offer volumes',
    );
    expect(find.text('tbsp'), findsNothing);
    expect(
      find.text('kg'),
      findsWidgets,
      reason: 'the other families are open',
    );
    await tester.tap(find.text('g').last); // keep `g`, close the popover
    await tester.pumpAndSettle();
    await enterYieldAmount(tester, 'yield-2', '250');

    // A few real lines off the synced vocab. Olive Oil is deliberately shared
    // with the parent below: one shopping item, two levels of provenance.
    await addVocabLine(tester, 'almond', 'Almonds', '100');
    await addVocabLine(tester, 'red bell', 'Red Bell Pepper', '2');
    await addVocabLine(tester, 'olive oil', 'Olive Oil', '60');

    await saveRecipe(tester);
    // The hero meta row reads as one sentence in two pills (board frame b).
    expect(find.text('makes 1 cup'), findsOneWidget);
    expect(find.text('· 250 g'), findsOneWidget);

    // Both denominations survive the server round-trip — the migration's
    // "different family" CHECK accepts the pair, so the upload queue drains.
    await waitForSyncRoundTrip(tester);
    final aioli = await db.get(
      'SELECT id, yield_qty, yield_unit, yield_qty_2, yield_unit_2 '
      "FROM recipe WHERE title = 'Romesco Aioli' AND deleted_at IS NULL",
    );
    expect(aioli['yield_qty'], 1);
    expect(aioli['yield_unit'], 'cup');
    expect(aioli['yield_qty_2'], 250);
    expect(aioli['yield_unit_2'], 'g');

    // ------------------------------------------------------------------------
    // 6b · THE PARENT — a component line through the picker's "Your recipes".
    // ------------------------------------------------------------------------
    await backFromRecipe(tester);
    await startRecipe(tester, 'Sausage Sliders');
    await addVocabLine(tester, 'olive oil', 'Olive Oil', '2');

    await addComponentLine(
      tester,
      'romesco',
      'Romesco Aioli',
      hint: 'makes 1 cup',
    );
    // The picker row carried the yield as its hint, and the sheet that opened
    // is the batch-math one: the target's chip, its yields, and the live
    // conversion line (board frame d).
    expect(find.textContaining('your recipe'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(ComponentQuantityEditor),
        matching: find.byType(EditableText),
      ),
      '0.25',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('0.25 cup = 0.25 of a batch · makes 1 cup'),
      findsOneWidget,
      reason: 'the conversion line must read the batch math, live',
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await saveRecipe(tester);

    // The saved line is a component in the D1 sense: the sub-recipe identity,
    // no ingredient, no measure — and it stays that way after the round trip
    // (the server's XOR + measure CHECKs accepted the write).
    final sliders = await db.get(
      "SELECT id FROM recipe WHERE title = 'Sausage Sliders' "
      'AND deleted_at IS NULL',
    );
    await waitForSyncRoundTrip(tester);
    final component = await db.get(
      'SELECT li.quantity, li.unit, li.ingredient_id, li.sub_recipe_id, '
      'li.measure_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.sub_recipe_id IS NOT NULL '
      'AND li.deleted_at IS NULL',
      [sliders['id']],
    );
    expect(component['sub_recipe_id'], aioli['id']);
    expect(component['ingredient_id'], isNull);
    expect(component['measure_id'], isNull, reason: 'measures are ingredients');
    expect(component['quantity'], 0.25);
    expect(component['unit'], 'cup');

    // ------------------------------------------------------------------------
    // 6c · THE TWO FACES — the parent's chip, the target's "Used in" tab, and
    //      the delete refusal that speaks the same count (D5 · D7 · D9).
    // ------------------------------------------------------------------------
    // The v3 grammar is untouched; only the identity cell changed.
    expect(find.text('0.25 cup'), findsOneWidget);
    expect(find.byType(RecipeChip), findsOneWidget);
    await tester.tap(find.byType(RecipeChip));
    await pumpUntilFound(tester, find.text('makes 1 cup'));

    // The aioli's own page, with the conditional third tab carrying its count.
    await tester.tap(find.text('Used in · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Sausage Sliders'), findsOneWidget);
    expect(
      find.text('0.25 cup · 0.25 of a batch'),
      findsOneWidget,
      reason: 'a "used in" row states the printed amount AND its share',
    );
    // The rows are real: this one pushes the parent.
    await tester.tap(find.text('Sausage Sliders'));
    await pumpUntilFound(tester, find.byType(RecipeChip));
    await backFromRecipe(tester);
    await pumpUntilFound(tester, find.text('makes 1 cup'));

    // Deleting a recipe something points at is refused, with the count (D5).
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await pumpUntilFound(tester, find.text('Can’t delete this recipe'));
    expect(
      find.text('Used in 1 recipe (1 line). Change those lines first.'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(40, 300)); // dismiss the popover
    await tester.pumpAndSettle();
    final stillThere = await db.get(
      'SELECT deleted_at FROM recipe WHERE id = ?',
      [aioli['id']],
    );
    expect(stillThere['deleted_at'], isNull, reason: 'the refusal must hold');

    // ------------------------------------------------------------------------
    // 6d · THE PLAN — a component is a real derived session, and its
    //      ingredients flow into the list with two-level provenance (D3 · D4).
    // ------------------------------------------------------------------------
    await backToShell(tester);
    await tapTab(tester, FLucideIcons.calendarDays);
    // The lens's `Shared` became `Everyone` (D8); `addMealOn` puts the Week
    // into edit mode itself, because the add doors only exist there (D1).
    await pumpUntilFound(tester, find.text('Everyone'));
    await addMealOn(tester, 'Friday', 'Sausage Sliders');

    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(
      tester,
      find.text('Romesco Aioli · for Sausage Sliders'),
    );
    await scrollTo(tester, find.text('Romesco Aioli · for Sausage Sliders'));
    expect(find.text('derived from a component line'), findsOneWidget);
    // Ready BY the demanding parent's cook day, denominated in batches.
    expect(find.text('Cook by Fri'), findsOneWidget);
    expect(find.text('×0.25 batch'), findsOneWidget);
    expect(
      find.text(
        'covers Sausage Sliders · cook Fri — makes 1 cup, you need '
        '0.25',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nothing here tracks the leftover'),
      findsOneWidget,
      reason: 'a fractional batch says so out loud (an 8.6 non-goal)',
    );

    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.text('Shopping list'));
    // The component LINE never becomes an item (you buy almonds, not aioli) —
    // the aioli's own lines do, through the derived session.
    await scrollTo(tester, find.text('Almonds'));
    expect(find.text('Romesco Aioli'), findsNothing);
    expect(
      find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      findsWidgets,
      reason: 'the nested contribution names both levels',
    );
    // Olive Oil is on both levels, so its breakdown carries both segments.
    await scrollTo(tester, find.text('Olive Oil'));
    final oilRow = find
        .ancestor(of: find.text('Olive Oil'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(of: oilRow, matching: find.text('Sausage Sliders')),
      findsOneWidget,
      reason: "the parent's own line reads as it always has",
    );
    expect(
      find.descendant(
        of: oilRow,
        matching: find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      ),
      findsOneWidget,
    );

    // ------------------------------------------------------------------------
    // 6e · THE HONEST GAP — un-state the yield and the derived numbers go away
    //      rather than turning into a ×1 (D2 · D3 · D4).
    // ------------------------------------------------------------------------
    await tapTab(tester, FLucideIcons.library);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await scrollTo(tester, find.text('Romesco Aioli'));
    await tester.tap(find.text('Romesco Aioli'));
    await pumpUntilFound(tester, find.text('makes 1 cup'));
    await tester.tap(
      find.descendant(
        of: find.byType(FHeaderAction),
        matching: find.byIcon(FLucideIcons.ellipsis),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.text('Edit recipe'));
    await enterYieldAmount(tester, 'yield-1', '');
    await saveRecipe(tester);

    // Clearing the first denomination drops the second with it — the pair the
    // migration's CHECK pins can never be half-stated.
    expect(find.text('makes 1 cup'), findsNothing);
    expect(find.text('· 250 g'), findsNothing);
    await waitForSyncRoundTrip(tester);
    final cleared = await db.get(
      'SELECT yield_qty, yield_unit, yield_qty_2, yield_unit_2 FROM recipe '
      'WHERE id = ?',
      [aioli['id']],
    );
    expect(cleared['yield_qty'], isNull);
    expect(cleared['yield_unit'], isNull);
    expect(cleared['yield_qty_2'], isNull);
    expect(cleared['yield_unit_2'], isNull);

    // The Cook tab: the session becomes a NAMED GAP. Never a ×1 — assuming one
    // batch is exactly the invented number this app refuses.
    await backToShell(tester);
    await tapTab(tester, FLucideIcons.cookingPot);
    await pumpUntilFound(
      tester,
      find.text('Romesco Aioli doesn’t say how much it makes'),
    );
    await scrollTo(tester, find.text('Romesco Aioli · for Sausage Sliders'));
    expect(
      find.text('derived from a component line · yield not set'),
      findsOneWidget,
    );
    expect(find.text('no scale'), findsOneWidget);
    expect(find.text('Set the yield'), findsOneWidget);
    // The one number a gap CAN state is what the demanding line printed —
    // unscaled, unconverted, quoted from the page (frame f).
    expect(
      find.text(
        'covers Sausage Sliders · cook Fri — the line asks for '
        '0.25 cup',
      ),
      findsOneWidget,
    );
    expect(find.text('×0.25 batch'), findsNothing);
    expect(find.text('×1 batch'), findsNothing);

    // The Shop tab: the unresolved component contributes NOTHING, and the
    // parent says so rather than leaving the list quietly short (D4).
    await tapTab(tester, FLucideIcons.shoppingBasket);
    await pumpUntilFound(tester, find.text('Shopping list'));
    await scrollTo(tester, find.text('1 component unresolved — see Cook'));
    expect(find.text('SAUSAGE SLIDERS'), findsOneWidget);
    expect(
      find.text('Romesco Aioli · for Sausage Sliders · cook Fri'),
      findsNothing,
      reason: 'an unresolved component contributes nothing — never a guess',
    );
    expect(find.text('Almonds'), findsNothing);
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
    final email = 'smoke$stamp.ada@ansi.app';
    final token = await _signUp(email, fullName: 'Ada');
    final household = await _ensureOnboarded(token);
    if (await _memberCount(token, household) > 1) continue; // filled a stray
    final partnerToken = await _signUp(
      'smoke$stamp.jun@ansi.app',
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
