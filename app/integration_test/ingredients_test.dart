/// Sim smoke — INGREDIENTS MANAGER: Library ▸ the Ingredients shelf → the
/// stub band
/// over the real vocab → open a stub, rename it, and prove the D6 match_text
/// rewrite in the local db → on the SAME form, the four legs that only a real
/// stack proves:
///
/// - the 7.8 **density entry both ways** — "1 tbsp of this weighs N g", then
///   the same sentence against `ml`, which is a g/ml —
///   one stored fact, and ADR-0009's unlock of the other family asserted on
///   the ROUND-TRIPPED `allowed_units` (as a jsonb array: the connector's
///   decode-before-upload, 0028's repair);
/// - **macros from a per-serving label** (plan 0027 M-D1/D3): the four typed
///   as printed, the stored-per-100 preview, and the M-D2 spoon opt-in landing
///   the density in the same Save;
/// - **Counts as** on a measured stub (seam D1) — set, back, reopened, stuck,
///   and accepted by the server's own-measure trigger (0023);
/// - **the USDA match, said out loud** (plan 0027 U-D1/U-D2): a bare stub the
///   SERVER's prefill trigger filled and NAMED on upload (the phone holds no
///   `usda_food`), the provenance line on the form, *Not this food* clearing
///   the numbers in one write, and — the D2 guarantee — a rename to another
///   reference-set name that the trigger does NOT refill;
///
/// then add-new by BARCODE: the scan sheet's camera pane degrades to its
/// designed notice (there is no camera in the Simulator), the typed field
/// carries the code, and the lookup returns the committed Open Food Facts
/// fixture through an overridden `offLookupProvider` — no network. Asserts the
/// prefilled draft, then the saved row's `off:<barcode>` provenance, macros
/// and `stub` status SURVIVING the sync round trip (D7b excludes barcode
/// rows), and the G4 "needs completing" hint.
///
/// The stubs this file works on are SEEDED through the app's own ingredient
/// repository — the same `createStub` the add flow's "Create & flesh out"
/// calls (a `manual` stub with the raw name and a server-rule `match_text`)
/// — and round-tripped through sync before the manager opens. The import
/// file drives the UI that creates the same row. The USDA stub is seeded that
/// way ON PURPOSE rather than through the manager's ＋: the sheet's Manual and
/// USDA legs run the client's own birth probe over the same RPC, which would
/// fill the row before it ever uploaded and leave nothing for the trigger to
/// prove. Through `createStub` the only writer of `source_label` on the local
/// row is the server.
///
/// Scanning from the camera is not exercised: `mobile_scanner` refuses
/// still-image analysis on the iOS Simulator at compile time, and there is
/// no camera to point at a pack, so the typed field is the Simulator's path
/// to the identical downstream handler (plan 0020 D3 + the option-A ruling).
///
/// Local gate only (`make test-sim FILE=ingredients`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/core/units/units.dart' show densityFromVolumeWeight, tbsp;
import 'package:ansi/features/ingredients/barcode/barcode_scan_sheet.dart'
    show BarcodeScanSheet;
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/data/measure_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart'
    show usdaDeclinedSource, usdaFdcId;
import 'package:ansi/features/ingredients/domain/normalize.dart'
    show normalizeMatchText;
import 'package:ansi/features/ingredients/domain/usda_probe.dart' show UsdaBand;
import 'package:ansi/features/ingredients/presentation/density_entry.dart'
    show AnsiModeChip, DensityEntry;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show IngredientDetailView, kFormSaveKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'off_fixture.dart';
import 'support/drive.dart';
import 'support/library.dart';
import 'support/stack.dart';

/// The text field inside a keyed form control (`macro-kcal`,
/// `serving-amount`, …): the keys sit on the `FTextField` wrappers, so the
/// editable is a descendant.
Finder keyedField(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(EditableText),
);

/// The name a stub ends up with after the USDA leg's rename — a word the
/// reference set matches (`Watercress, raw`) and the household vocab lacks,
/// so "not refilled" is a claim about the trigger, not about a miss.
const renamedDeclined = 'Watercress';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  /// Taps the form's own docked Save, then walks back into [name]'s row.
  ///
  /// Two things changed under this helper. The dock is **pinned**, so the
  /// Save needs no scrolling — and it is **keyed** ([kFormSaveKey]), because
  /// the density entry and the measures editor each carry their own small
  /// green Save and `find.text('Save').last` was picking between three of
  /// them by position. And Save **ends the page**, so anything that goes on
  /// working the same row re-enters it from the list.
  Future<void> saveFormAndReopen(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(kFormSaveKey));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(name));
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('CANONICAL NAME'));
  }

  testWidgets(
    'ingredients: flesh out a stub (rename · density · a label per serving · '
    'counts as), decline a USDA match, then add one by barcode',
    (tester) async {
      ignoreForuiSemanticsAssertion();
      final db = stack.db;
      await stack.openLibraryWithOffFixture(tester);

      // Seed the stub the way the import review's create-new leaves it (plan
      // 0025 D3, detail 7): a bare `manual` stub carrying the raw name, its
      // form backed out of unconfirmed. Through the real repository, then up
      // and back down through sync, so the server has seen the row (its USDA
      // prefill trigger included) before the manager renders it.
      final ingredients = SqliteIngredientRepository(
        db,
        householdId: stack.householdId,
      );
      const stubName = 'Aleppo chilli flakes';
      final chilli = await ingredients.createStub(stubName);
      // A measure on it, so the form draws its Counts-as row (hidden on a row
      // with none — there is nothing to choose). Not a volume word: those
      // are a density in disguise and the repository refuses them.
      final sachet = await SqliteMeasureRepository(
        db,
        householdId: stack.householdId,
      ).addMeasure(ingredientId: chilli.id, label: 'sachet', amount: 30);
      // A second bare stub whose name the reference set matches (checked
      // against the local stack's `usda_food`: "Radicchio, raw", with a
      // density AND macros, so the fill exercises 0014's unlock too) and the
      // household vocab does not carry. Before the upload it is provably
      // bare: the phone holds no reference set (ADR-0004/0005) and
      // `createStub` writes no label, so a label on this row after the round
      // trip can only be the server trigger's.
      const usdaName = 'Radicchio';
      final radicchio = await ingredients.createStub(usdaName);
      expect(
        (await db.get(
          "SELECT count(*) AS c FROM sqlite_master WHERE name = 'usda_food'",
        ))['c'],
        0,
        reason: 'the reference set must never reach the phone (ADR-0004)',
      );
      final bare = await db.get(
        'SELECT source, source_label, macros FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      expect(bare['source'], 'manual');
      expect(bare['source_label'], isNull);
      expect(bare['macros'], isNull);

      final fillTimer = Stopwatch()..start();
      await stack.waitForSyncRoundTrip(tester);
      // Assert the seeded state up front so a vocab change (a template row
      // that already prints "chilli flakes") fails HERE, with a reason, rather
      // than as a mystery finder miss inside the form below.
      final chilliRows = await db.getAll(
        'SELECT id, canonical_name, match_text FROM ingredient '
        "WHERE status = 'stub' "
        "AND canonical_name LIKE '%chilli flakes%' AND deleted_at IS NULL",
      );
      expect(
        chilliRows,
        hasLength(1),
        reason:
            'this file fleshes out the one stub it seeded — exactly one '
            "'%chilli flakes%' stub row",
      );
      expect(chilliRows.single['canonical_name'], stubName);
      final stubId = chilliRows.single['id'] as String;
      expect(stubId, chilli.id);
      final stubMatchText = chilliRows.single['match_text'] as String;
      expect(stubMatchText, normalizeMatchText(stubName));

      // --- the server's prefill, streamed back (U-D1, the trigger leg) ------
      // The 0015 trigger fires inside the upload transaction; its write
      // streams back down over the local row. Polled rather than assumed,
      // and timed — the "not refilled" assertion at the end of the USDA leg
      // waits at least this long before it calls a silence a guarantee.
      await waitForDb(
        tester,
        () async =>
            (await db.get('SELECT source_label FROM ingredient WHERE id = ?', [
              radicchio.id,
            ]))['source_label'] !=
            null,
        "the server's USDA prefill to name the radicchio stub",
      );
      final fillTook = fillTimer.elapsed;
      final filled = await db.get(
        'SELECT source, source_label, source_score, density_g_per_ml, macros, '
        'status FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      final filledSource = filled['source'] as String;
      final filledLabel = filled['source_label'] as String;
      expect(filledSource, startsWith('usda_fdc:'));
      expect(filledLabel, startsWith('Radicchio'));
      // U-D1 + the lane's extra column: the label and the score land in the
      // same statement as the stamp, so the form can print the band offline.
      expect(filled['source_score'], isNotNull);
      expect(filled['density_g_per_ml'], isNotNull);
      expect(filled['macros'], isNotNull);
      // Filled, never completed: confirming is a human act (plan 0020 D5).
      expect(filled['status'], 'stub');

      // --- Library ▸ the Ingredients shelf ---------------------------------
      // 0028 E5: the vocabulary is a shelf at the foot of the library, drawn
      // like a book and carrying its own counts — not a row in a menu. It
      // sits below the books, so scroll to it the way a person would.
      await scrollTo(tester, find.text('Ingredients'));
      await openIngredientsShelf(tester);
      await pumpUntilFound(tester, find.text('Needs fleshing out'));

      // The band and the header count what the local database really holds.
      // Both counts are read HERE rather than before the navigation: the list
      // is a watched stream, so a row arriving over sync mid-transition would
      // move the rendered number out from under a figure captured earlier.
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
      // The header sits BELOW the whole stub band in a virtualized list — it
      // is not built until scrolled to (the import review's lesson, one
      // screen later).
      await scrollTo(tester, find.text('All ingredients · $vocabSize'));

      // --- open the stub and flesh it out ----------------------------------
      // The row is in the band AND in the all-ingredients list below; scroll
      // back up to it first — the header check left us at the band's end.
      await scrollTo(tester, find.text(stubName));
      await tester.tap(find.text(stubName).first);
      await pumpUntilFound(tester, find.text('CANONICAL NAME'));

      // The rename hazard (D6): the stored name and its match_text are
      // written together, or the next import's cascade searches for a name
      // nothing carries. The canonical-name field is the form's first text
      // field.
      const renamed = 'Gochugaru flakes';
      await tester.enterText(
        fieldIn(find.byType(IngredientDetailView)),
        renamed,
      );
      await tester.pumpAndSettle();

      // Save ENDS the page since the v2 pass (the picker that pushes this
      // form awaits its pop), so a leg that goes on working the same row
      // walks back in through the list, the way a person would.
      await saveFormAndReopen(tester, renamed);

      await waitForDb(
        tester,
        () async =>
            (await db.get(
              'SELECT canonical_name FROM ingredient WHERE id = ?',
              [stubId],
            ))['canonical_name'] ==
            renamed,
        'the rename to land in the local database',
      );
      final renamedRow = await db.get(
        'SELECT canonical_name, match_text, status FROM ingredient '
        'WHERE id = ?',
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
      // Filling a form in never promotes a row — confirming is a human act
      // (D5).
      expect(renamedRow['status'], 'stub');

      // --- density, both phrasings (7.8 / ADR-0008) ------------------------
      // The same form, two more taps. "1 tbsp weighs 15 g" converts through
      // ml-per-spoon and writes the one stored number; the write extends the
      // explicit `allowed_units` with the volume family in the same
      // transaction (ADR-0009), which the round trip below proves survived
      // the server as a jsonb ARRAY.
      Future<double?> storedDensity() async =>
          ((await db.get(
                    'SELECT density_g_per_ml AS d FROM ingredient WHERE id = ?',
                    [stubId],
                  ))['d']
                  as num?)
              ?.toDouble();
      expect(await storedDensity(), isNull, reason: 'the leg starts bare');

      final densityField = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.byType(EditableText),
      );
      final densitySave = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.widgetWithText(FButton, 'Save'),
      );
      // One sentence since the v2 pass — "1 [tbsp] of this weighs [__] g" —
      // so there is no phrasing mode to enter. `tbsp` is the standing pick.
      await scrollTo(tester, find.text('of this weighs'));
      await centerOn(tester, find.text('of this weighs'));
      await tester.enterText(densityField, '15');
      await tester.pumpAndSettle();
      // The live equivalence: both phrasings are the same fact.
      final spoonDensity = densityFromVolumeWeight(tbsp, 15)!;
      expect(find.textContaining('= 1.01 g/ml'), findsOneWidget);
      await centerOn(tester, densitySave);
      await tester.tap(densitySave);
      await tester.pumpAndSettle();
      await waitForDb(
        tester,
        () async => (await storedDensity() ?? 0) > 1,
        'the spoon-phrased density to land',
      );
      expect(await storedDensity(), closeTo(spoonDensity, 1e-9));
      // The headline follows the row: the entry re-reads what it wrote.
      await pumpUntilFound(tester, find.text('1.01 g/ml'));

      await stack.waitForSyncRoundTrip(tester);
      final unlocked = await db.get(
        'SELECT density_g_per_ml, allowed_units, '
        'json_type(allowed_units) AS shape FROM ingredient WHERE id = ?',
        [stubId],
      );
      expect((unlocked['density_g_per_ml'] as num).toDouble(), spoonDensity);
      expect(
        unlocked['shape'],
        'array',
        reason:
            'allowed_units must come back from the server as a jsonb ARRAY — '
            'a string here means the connector uploaded the local TEXT as-is '
            '(the 0028 repair’s cause) and every server-side `? unit` check '
            'answers false',
      );
      final unlockedUnits =
          (jsonDecode(unlocked['allowed_units'] as String) as List)
              .cast<String>();
      expect(
        unlockedUnits,
        containsAll(['g', 'tsp', 'tbsp', 'cup', 'ml']),
        reason:
            'ADR-0009: a density on a mass-basis row admits the volume family',
      );

      // The other phrasing, the same number — now the same sentence with a
      // different pick. `ml`'s ratio to base is 1, so "1 ml of this weighs
      // 1.2 g" IS 1.2 g/ml: that equivalence is what let the separate g/ml
      // field be deleted rather than merely hidden. The entry re-rendered
      // after its save (and slid up under the header), so the chip is centred
      // and picked explicitly rather than assumed.
      final mlChip = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.widgetWithText(AnsiModeChip, 'ml'),
      );
      await centerOn(tester, mlChip);
      await tester.tap(mlChip);
      await tester.pumpAndSettle();
      await tester.enterText(densityField, '1.2');
      await tester.pumpAndSettle();
      await centerOn(tester, densitySave);
      await tester.tap(densitySave);
      await tester.pumpAndSettle();
      await waitForDb(
        tester,
        () async => await storedDensity() == 1.2,
        'the g/ml-phrased density to land',
      );

      // --- macros from a per-serving label (plan 0027 M-D1/D3, M-D2) --------
      // The label as printed — "14 g · 100 kcal · 0 P · 0 C · 11 F" — and the
      // row stores per 100 g, unrounded, previewed before Save. The serving
      // is a spoon, so M-D2 offers it as the density; ticked, it lands in the
      // same Save through `setDensity` and REPLACES the 1.2 above — the
      // number is distinct, so the round trip below says which save wrote it.
      await scrollTo(tester, find.text('per serving'));
      await centerOn(tester, find.text('per serving'));
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await pumpUntilFound(tester, find.text('One serving is'));
      await tester.enterText(keyedField('serving-amount'), '14');
      await tester.pumpAndSettle();
      await tester.enterText(keyedField('serving-name'), '1 tbsp');
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('kcal', '100'),
        ('protein', '0'),
        ('carb', '0'),
        ('fat', '11'),
      ]) {
        await tester.enterText(keyedField('macro-$label'), value);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      // The derivation, before Save, in the person's sight (invariant 3).
      expect(find.textContaining('stored per 100 g: 714 kcal'), findsOneWidget);
      expect(
        find.textContaining(
          'from a 14 g serving — the label’s rounding scales with it',
        ),
        findsOneWidget,
      );
      // M-D2: the offer, drawn and unticked; one tap takes it.
      await scrollTo(tester, find.text('1 tbsp weighs 14 g — set as density'));
      final tick = find.byKey(const ValueKey('serving-offer'));
      await centerOn(tester, tick);
      expect(tester.widget<FCheckbox>(tick).value, isFalse);
      await tester.tap(tick);
      await tester.pumpAndSettle();
      expect(tester.widget<FCheckbox>(tick).value, isTrue);

      await saveFormAndReopen(tester, renamed);
      await waitForDb(
        tester,
        () async =>
            (await db.get('SELECT macros FROM ingredient WHERE id = ?', [
              stubId,
            ]))['macros'] !=
            null,
        'the per-serving macros to land',
      );
      await stack.waitForSyncRoundTrip(tester);
      final labelled = await db.get(
        'SELECT macros, macros_basis, density_g_per_ml, status FROM ingredient '
        'WHERE id = ?',
        [stubId],
      );
      final per100 = jsonDecode(labelled['macros'] as String) as Map;
      // Per 100, unrounded (M-D3); the printed four are nowhere on the row.
      expect(per100['kcal'], closeTo(100 / 14 * 100, 1e-6));
      expect(per100['fat'], closeTo(11 / 14 * 100, 1e-6));
      expect(per100['protein'], 0);
      expect(per100['carb'], 0);
      expect(labelled['macros_basis'], 'g');
      // A label fills fields; confirming stays a human act (plan 0020 D5).
      expect(labelled['status'], 'stub');
      // The M-D2 tick: the density entry's own spoon arithmetic (ADR-0008
      // §2), landed by the form's Save — and it is the tick's number, not
      // the g/ml leg's.
      expect(
        (labelled['density_g_per_ml'] as num).toDouble(),
        closeTo(densityFromVolumeWeight(tbsp, 14)!, 1e-9),
      );

      // --- Counts as (seam D1): a stated fact, saved on pick ----------------
      const countsAsLabel = 'COUNTS AS';
      const sachetItem = 'sachet · 30 g';
      await scrollTo(tester, find.text(countsAsLabel));
      expect(find.text('One ${renamed.toLowerCase()} is'), findsOneWidget);
      await centerOn(tester, find.text('— not set'));
      await tester.tap(find.text('— not set'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(sachetItem).last);
      await tester.pumpAndSettle();
      await waitForDb(
        tester,
        () async =>
            (await db.get(
              'SELECT default_measure_id FROM ingredient WHERE id = ?',
              [stubId],
            ))['default_measure_id'] ==
            sachet.id,
        'the Counts-as pick to land',
      );

      // Back to the list. It RESTORES its scroll offset from before the
      // detail push, which can leave the band header just above the viewport
      // — settle on the always-present search bar, then scroll to what the
      // next step needs.
      await tester.tap(find.byType(FHeaderAction).first);
      await pumpUntilFound(tester, find.text('Search your vocabulary'));
      // We are back on the list (header + search prove it). The stub BAND is
      // deliberately not re-asserted here: on-device the returned list parks
      // its viewport past the band and resists programmatic re-scroll (11
      // sim rounds of forensics; the band's round-trip logic is host-guarded
      // by the J4 widget test). The renamed stub's presence is asserted via
      // the DB below instead; the on-device scroll-restoration quirk is
      // tracked.
      final stillStub = await db.get(
        "SELECT count(*) AS c FROM ingredient WHERE status = 'stub' "
        'AND deleted_at IS NULL',
      );
      expect(stillStub['c'] as int, greaterThan(0));

      // Reopen the row: the pick is the ROW's, read back from the store, not
      // a state the form held. And it went up and came back: the 0023
      // own-measure trigger accepted a default that names this row's own
      // measure.
      await scrollTo(tester, find.text(renamed));
      await tester.tap(find.text(renamed).first);
      await pumpUntilFound(tester, find.text('CANONICAL NAME'));
      await scrollTo(tester, find.text(countsAsLabel));
      expect(find.text(sachetItem), findsOneWidget);
      expect(find.text('— not set'), findsNothing);
      await stack.waitForSyncRoundTrip(tester);
      expect(
        (await db.get(
          'SELECT default_measure_id FROM ingredient WHERE id = ?',
          [stubId],
        ))['default_measure_id'],
        sachet.id,
        reason: 'the default must survive the server (0023 accepts its own)',
      );
      await tester.tap(find.byType(FHeaderAction).first);
      await pumpUntilFound(tester, find.text('Search your vocabulary'));

      // --- the USDA match, said out loud (plan 0027 U-D1 / U-D2) -----------
      await scrollTo(tester, find.text(usdaName));
      await tester.tap(find.text(usdaName).first);
      await pumpUntilFound(tester, find.text('CANONICAL NAME'));

      // U-D1: the provenance line at the head of the macros section names
      // the food, its FDC id and the band word — all read off the row the
      // trigger stamped, printable offline.
      await scrollTo(tester, find.text('Filled from USDA · not confirmed'));
      final band = UsdaBand.of((filled['source_score'] as num).toDouble()).word;
      expect(
        find.text(
          '$filledLabel · FDC ${usdaFdcId(filledSource)} · $band for '
          '“$usdaName”',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      // The old lookup button has no job on a row USDA already filled.
      expect(find.text('Look up in USDA'), findsNothing);

      // U-D2: one write — the density (and the units it alone admitted,
      // D4b), the macros, the score go; the stamp becomes `usda_declined`;
      // the label stays so the form can name what was refused.
      await centerOn(tester, find.widgetWithText(FButton, 'Not this food'));
      await tester.tap(find.widgetWithText(FButton, 'Not this food'));
      await pumpUntilFound(tester, find.text('USDA · declined'));
      await waitForDb(
        tester,
        () async =>
            (await db.get('SELECT source FROM ingredient WHERE id = ?', [
              radicchio.id,
            ]))['source'] ==
            usdaDeclinedSource,
        'the decline to land',
      );
      final declined = await db.get(
        'SELECT source_label, source_score, density_g_per_ml, macros, '
        'allowed_units, status FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      expect(declined['density_g_per_ml'], isNull);
      expect(declined['macros'], isNull);
      expect(declined['source_score'], isNull);
      expect(declined['source_label'], filledLabel);
      expect(declined['status'], 'stub');
      final stripped = (jsonDecode(declined['allowed_units'] as String) as List)
          .cast<String>();
      expect(stripped, contains('g'));
      expect(
        stripped,
        isNot(contains('cup')),
        reason: 'D4b: the volume family the density alone admitted is out',
      );
      expect(
        find.text(
          '$filledLabel — not this food · the filled numbers were '
          'cleared',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FButton, 'Not this food'), findsNothing);
      expect(
        find.text('renaming this row will not refill it — you said no once'),
        findsOneWidget,
      );

      // The D2 guarantee, end to end: a rename is exactly what re-fires the
      // 0015 trigger on a bare manual stub, and the new name is one the
      // reference set matches ("Watercress, raw" — checked on the local
      // stack). Its WHEN clause does not list `usda_declined`, so the row
      // must come back from the server as bare as it went up.
      await tester.enterText(
        fieldIn(find.byType(IngredientDetailView)),
        renamedDeclined,
      );
      await tester.pumpAndSettle();
      await saveFormAndReopen(tester, renamedDeclined);
      await waitForDb(
        tester,
        () async =>
            (await db.get(
              'SELECT canonical_name FROM ingredient WHERE id = ?',
              [radicchio.id],
            ))['canonical_name'] ==
            renamedDeclined,
        'the rename to land',
      );
      await stack.waitForSyncRoundTrip(tester);
      // A silence is only a guarantee if a fill had time to arrive: give it
      // what the first fill actually took, plus a margin.
      final silence = Stopwatch()..start();
      while (silence.elapsed < fillTook + const Duration(seconds: 2)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final afterRename = await db.get(
        'SELECT source, source_label, density_g_per_ml, macros, match_text '
        'FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      expect(afterRename['match_text'], normalizeMatchText(renamedDeclined));
      expect(
        afterRename['source'],
        usdaDeclinedSource,
        reason:
            'U-D2: the rename trigger refilled a DECLINED row — its WHEN '
            'clause has grown `usda_declined`, or the decline never uploaded',
      );
      expect(afterRename['macros'], isNull);
      expect(afterRename['density_g_per_ml'], isNull);
      // The refused food is still named — "you said no once" needs a noun.
      expect(afterRename['source_label'], filledLabel);

      await tester.tap(find.byType(FHeaderAction).first);
      await pumpUntilFound(tester, find.text('Search your vocabulary'));

      // --- add new, by barcode ---------------------------------------------
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

      // The sheet's stable chrome. On the Simulator the plugin's start
      // neither succeeds nor ERRORS — no camera means it waits forever, so
      // the designed "Ansi can't open the camera" notice never renders
      // (errorBuilder never fires; observed round 12). The notice's on-screen
      // verification moves to the physical-device slice with the rest of the
      // camera legs; what this scenario proves is that the TYPED field stays
      // live regardless — the whole reason D3 made it a permanent sibling
      // rather than a fallback.
      await pumpUntilFound(tester, find.text('OR TYPE THE NUMBER'));

      // Type the digits — the Simulator-walkable path (plan 0020 D3, and the
      // scenario-5 option-A ruling). Downstream of `run()` this is the SAME
      // handler the live detector calls.
      //
      // Scoped, not positional: BOTH sheets are in the tree while the scanner
      // is open, and the add sheet's autofocused NAME field is an EditableText
      // too.
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
      // for, rather than the fixture being handed back for any request at
      // all.
      final offRequestUrl = stack.offRequestUrl;
      expect(offRequestUrl, isNotNull, reason: 'no lookup was attempted');
      expect(offRequestUrl!.host, 'world.openfoodfacts.org');
      expect(offRequestUrl.path, contains(offFixtureBarcode));

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

      // --- what landed in the local database -------------------------------
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
      // D1: a lookup PREFILLS and never completes. The macros are there and
      // the row is still a stub waiting for a human.
      expect(scannedRow['status'], 'stub');
      expect(scannedRow['macros_basis'], 'g');
      final macros = jsonDecode(scannedRow['macros'] as String) as Map;
      expect(macros['kcal'], 539);
      expect(macros['protein'], 6.3);
      expect(macros['carb'], 57.5);
      expect(macros['fat'], 30.9);

      // D7b: the birth probe is EXCLUDED for a barcode row — a USDA stamp
      // would replace the Open Food Facts provenance with an FDC id. Proven
      // end to end: after the round trip the server's own trigger (whose WHEN
      // clause makes the same exclusion) has seen the row too.
      await stack.waitForSyncRoundTrip(tester);
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

      // --- back on the list, the G4 hint -----------------------------------
      // The returned list parks its viewport at the restored offset, below
      // the band — pumpUntilFound never scrolls, so anchor on the search bar
      // and SCROLL to the band (edge-detected).
      await tester.tap(find.byType(FHeaderAction).first);
      await pumpUntilFound(tester, find.text('Search your vocabulary'));
      await scrollTo(tester, find.text('Needs fleshing out'));

      // G4: a stub that HAS macros stops being asked for macros. The one
      // thing still missing is a human standing behind them, which is D5's
      // own word.
      final bandColumn = find
          .ancestor(
            of: find.text('Needs fleshing out'),
            matching: find.byType(Column),
          )
          .first;
      final bandRow = find
          .ancestor(
            of: find.descendant(of: bandColumn, matching: find.text('Nutella')),
            matching: find.byType(Row),
          )
          .first;
      expect(
        find.descendant(of: bandRow, matching: find.text('needs completing')),
        findsOneWidget,
        reason:
            'a prefilled stub must read "needs completing", not "needs '
            'macros" — '
            'it is not missing the numbers, it is missing the human',
      );
      // …and it is NOT flagged as a USDA prefill: this row came from a
      // barcode.
      expect(
        find.descendant(
          of: bandRow,
          matching: find.textContaining('usda prefilled'),
        ),
        findsNothing,
      );
    },
  );
}
