/// Sim smoke — INGREDIENTS MANAGER: the Library's Ingredients shelf → the stub
/// band over the real vocab → open a stub, rename it, and prove the
/// `match_text` rewrite in the local db → then, on the SAME form, the four
/// legs that only a real stack proves:
///
/// - **density entry both ways** — "1 tbsp weighs N g", then the same
///   sentence against `ml`, which is a g/ml — one stored fact, with ADR-0009's
///   unlock of the other family asserted on the ROUND-TRIPPED `allowed_units`
///   as a jsonb array (the connector decodes before upload);
/// - **macros from a per-serving label** — the four figures typed as printed,
///   the stored-per-100 preview, and the spoon opt-in landing the density in
///   the same Save;
/// - **the piece weight** (ADR-0015) — `piece` picked as the default strands
///   the row and Save refuses; "1 piece weighs 30 g" lands through the same
///   Save, unions `piece` into the explicit list, and survives the server as
///   a number the reopened form folds to a headline;
/// - **the USDA match, asked for and said out loud** — nothing matches a row
///   on its own any more, so the leg drives the form's own *Look up in USDA*
///   against the real reference set, picks the food, and proves the pick was
///   a draft until Save; then the provenance line naming the food and how much
///   of the name it answers — never the FDC id — all read off the row so it
///   prints offline; then *Not this food*, which clears the density, its
///   unlocked
///   units, the macros and the score in ONE write and leaves the label behind
///   so the form can still name what was refused.
///
/// Then add-new by BARCODE: the scan sheet's camera pane degrades to its
/// designed notice (there is no camera in the Simulator), the typed field
/// carries the code, and the lookup returns the committed Open Food Facts
/// fixture through an overridden `offLookupProvider` — no network. It asserts
/// the prefilled draft, then the saved row's `off:<barcode>` provenance, its
/// macros and its `stub` status surviving the sync round trip, and the "needs
/// completing" hint.
///
/// The stubs this file works on are SEEDED through the app's own ingredient
/// repository — the same `saveForm(null, …)` the form's one Save calls — and
/// round-tripped through sync before the manager opens. The import file drives
/// the UI that creates the same row.
///
/// Scanning from the camera is not exercised: `mobile_scanner` refuses
/// still-image analysis on the iOS Simulator at compile time, and there is no
/// camera to point at a pack, so the typed field is the Simulator's path to
/// the identical downstream handler.
///
/// Local gate only (`make test-sim FILE=ingredients`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/core/units/macros.dart' show MacrosBasis;
import 'package:ansi/core/units/units.dart'
    show densityFromVolumeWeight, g, tbsp;
import 'package:ansi/features/ingredients/barcode/barcode_scan_sheet.dart'
    show BarcodeScanSheet;
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart'
    show defaultAllowedUnitSet;
import 'package:ansi/features/ingredients/domain/ingredient.dart'
    show Ingredient, IngredientStatus, usdaDeclinedSource;
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart'
    show IngredientEdit, IngredientFormEdit;
import 'package:ansi/features/ingredients/domain/normalize.dart'
    show normalizeMatchText;
import 'package:ansi/features/ingredients/domain/usda_probe.dart'
    show UsdaMatchFit;
import 'package:ansi/features/ingredients/presentation/density_entry.dart'
    show AnsiModeChip, DensityEntry;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show IngredientDetailView, kFormSaveKey;
import 'package:ansi/features/ingredients/presentation/piece_weight_entry.dart';
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
/// so "not refilled" is a claim about the server, not about a miss.
const renamedDeclined = 'Watercress';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  /// Enters the form from wherever a tap on a row landed. A row opens as its
  /// fact sheet, and the form is behind the header's ⋯ ▸ Edit; the stub band's
  /// rows open the form directly, and then there is nothing to do.
  Future<void> enterForm(WidgetTester tester) async {
    await pumpUntilFound(tester, find.byType(IngredientDetailView));
    await tester.pumpAndSettle();
    if (find.text('CANONICAL NAME').evaluate().isNotEmpty) return;
    final more = find.descendant(
      of: find.byType(FHeaderAction),
      matching: find.byIcon(FLucideIcons.ellipsis),
    );
    await pumpUntilFound(tester, more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await pumpUntilFound(tester, find.text('CANONICAL NAME'));
  }

  /// Walks back to the Ingredients list from either posture of the page.
  /// Back from the form puts the page down into its fact sheet first — it
  /// leaves the mode, not the page — so from there it is one more back.
  Future<void> leaveToList(WidgetTester tester) async {
    final list = find.text('Search your vocabulary');
    for (var i = 0; i < 2 && list.evaluate().isEmpty; i++) {
      await tester.tap(find.byType(FHeaderAction).first);
      await tester.pumpAndSettle();
    }
    await pumpUntilFound(tester, list);
  }

  /// Taps the form's own docked Save, then re-enters the form.
  ///
  /// The dock is **pinned**, so the Save needs no scrolling — and it is
  /// **keyed** ([kFormSaveKey]), because the density entry and the measures
  /// editor each carry their own small green Save and `find.text('Save').last`
  /// was picking between three of them by position. Save puts the page down
  /// into its fact sheet, which names the row as [name]; working the same row
  /// again is ⋯ ▸ Edit from there.
  Future<void> saveFormAndReopen(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(kFormSaveKey));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text(name));
    await enterForm(tester);
  }

  testWidgets(
    'ingredients: flesh out a stub (rename · density · a label per serving · '
    'a piece weight), decline a USDA match, then add one by barcode',
    (tester) async {
      ignoreForuiSemanticsAssertion();
      final db = stack.db;
      await stack.openLibraryWithOffFixture(tester);

      // Seed the stub the way the add form's one Save leaves it: a bare
      // `manual` stub carrying the raw name. Through the real repository,
      // then up and back down through sync, so the server has seen the row
      // before the manager renders it.
      final ingredients = SqliteIngredientRepository(
        db,
        householdId: stack.householdId,
      );
      const stubName = 'Aleppo chilli flakes';
      final chilli = (await ingredients.saveForm(null, _bareStub(stubName)))!;
      // A second bare stub whose name the reference set matches (checked
      // against the local stack's `usda_food`: "Radicchio, raw", with a
      // density AND macros, so the fill exercises the unlock too) and the
      // household vocab does not carry. Nothing fills it on its own — the
      // USDA leg below looks it up by hand, which is the only way a row is
      // matched now.
      const usdaName = 'Radicchio';
      // What the reference set calls it — the row the search offers back.
      const usdaFood = 'Radicchio, raw';
      final radicchio = (await ingredients.saveForm(
        null,
        _bareStub(usdaName),
      ))!;
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

      // --- nothing matches on its own (0029) -------------------------------
      // The server used to fill a bare stub from the reference set inside the
      // upload transaction. That trigger is gone and nothing replaced it:
      // matching is a human act now, so a stub nobody looked up comes back
      // from a full round trip exactly as bare as it went up. The name it
      // carries is one the reference set DOES match, which is what makes the
      // silence a statement rather than a miss.
      final afterUpload = await db.get(
        'SELECT source, source_label, source_score, density_g_per_ml, macros '
        'FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      expect(afterUpload['source'], 'manual');
      expect(afterUpload['source_label'], isNull);
      expect(afterUpload['source_score'], isNull);
      expect(afterUpload['density_g_per_ml'], isNull);
      expect(afterUpload['macros'], isNull);

      // --- Library ▸ the Ingredients shelf ---------------------------------
      // The vocabulary is a shelf at the foot of the library, carrying its own
      // counts — not a row in a menu, and no longer drawn as a book: a rule and
      // a row. It sits below the books, so scroll to it the way a person would.
      await scrollTo(tester, ingredientsShelf);
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
      await enterForm(tester);

      // The rename hazard (D6): the stored name and its match_text are
      // written together, or the next import's cascade searches for a name
      // nothing carries. The canonical-name field is the form's first text
      // field.
      // Typed lowercase on purpose: Save is the backstop that tidies a name
      // never left, so the row is stored in Title Case and every later check
      // reads the tidied name.
      const typed = 'gochugaru flakes';
      const renamed = 'Gochugaru Flakes';
      await tester.enterText(fieldIn(find.byType(IngredientDetailView)), typed);
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
      // ml-per-spoon and becomes the one stored number — in the DRAFT, which
      // the form's own Save lands together with everything else it holds. The
      // save extends the explicit `allowed_units` with the volume family
      // (ADR-0009), which the round trip below proves survived the server as
      // a jsonb ARRAY.
      Future<double?> storedDensity() async =>
          ((await db.get(
                    'SELECT density_g_per_ml AS d FROM ingredient WHERE id = ?',
                    [stubId],
                  ))['d']
                  as num?)
              ?.toDouble();
      expect(await storedDensity(), isNull, reason: 'the leg starts bare');

      // The sentence has two fields now — an amount on the left and the
      // weight on the right — so the weight is found by its own key.
      final densityField = find.descendant(
        of: find.byKey(const ValueKey('density-grams')),
        matching: find.byType(EditableText),
      );
      // `Add`, not `Save`: the entry puts the number in the form's draft and
      // writes nothing of its own.
      final densityAdd = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.widgetWithText(FButton, 'Add'),
      );
      // One sentence since the v2 pass — "1 [tbsp] weighs [__] g" —
      // so there is no phrasing mode to enter. `tbsp` is the standing pick.
      await scrollTo(tester, find.text('weighs'));
      await centerOn(tester, find.text('weighs'));
      await tester.enterText(densityField, '15');
      await tester.pumpAndSettle();
      // The live equivalence: both phrasings are the same fact.
      final spoonDensity = densityFromVolumeWeight(tbsp, 15)!;
      expect(find.textContaining('= 1.01 g/ml'), findsOneWidget);
      await centerOn(tester, densityAdd);
      await tester.tap(densityAdd);
      await tester.pumpAndSettle();
      // The headline follows the DRAFT, and the row is still bare: one write,
      // and it has not happened yet.
      await pumpUntilFound(tester, find.text('1.01 g/ml'));
      expect(
        await storedDensity(),
        isNull,
        reason: 'the entry fills the draft; the form’s Save writes it',
      );

      await saveFormAndReopen(tester, renamed);
      await waitForDb(
        tester,
        () async => (await storedDensity() ?? 0) > 1,
        'the spoon-phrased density to land',
      );
      expect(await storedDensity(), closeTo(spoonDensity, 1e-9));

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

      // The other phrasing, the same number — the same sentence with a
      // different pick. `ml`'s ratio to base is 1, so "1 ml weighs
      // 1.2 g" IS 1.2 g/ml: that equivalence is what let the separate g/ml
      // field be deleted rather than merely hidden. The re-opened form drew
      // the entry afresh, so the chip is centred and picked explicitly rather
      // than assumed. The row now HAS a density, so the block is folded to
      // `1.01 g/ml · change` (C-D3) and the sentence is one tap away.
      await scrollTo(tester, find.text('· change'));
      await centerOn(tester, find.text('· change'));
      await tester.tap(find.text('· change'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('weighs'));
      final mlChip = find.descendant(
        of: find.byType(DensityEntry),
        matching: find.widgetWithText(AnsiModeChip, 'ml'),
      );
      await centerOn(tester, mlChip);
      await tester.tap(mlChip);
      await tester.pumpAndSettle();
      await tester.enterText(densityField, '1.2');
      await tester.pumpAndSettle();
      await centerOn(tester, densityAdd);
      await tester.tap(densityAdd);
      await tester.pumpAndSettle();
      await saveFormAndReopen(tester, renamed);
      await waitForDb(
        tester,
        () async => await storedDensity() == 1.2,
        'the g/ml-phrased density to land',
      );

      // --- macros from a per-serving label --------
      // The label as printed — "14 g · 100 kcal · 0 P · 0 C · 11 F" — and the
      // row stores per 100 g, unrounded, previewed before Save. The serving
      // states no density: that is the density section's subject alone, so
      // the 1.2 typed above survives this save untouched.
      await scrollTo(tester, find.text('per serving'));
      await centerOn(tester, find.text('per serving'));
      await tester.tap(find.text('per serving'));
      await tester.pumpAndSettle();
      await pumpUntilFound(tester, find.text('One serving is'));
      await tester.enterText(keyedField('serving-amount'), '14');
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
      expect(
        find.textContaining('stored per 100 g · 714 kcal'),
        findsOneWidget,
      );
      // And the serving row carries no free text at all any more.
      expect(find.byKey(const ValueKey('serving-name')), findsNothing);

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
      // A label fills fields; confirming stays a human act.
      expect(labelled['status'], 'stub');
      // The density is the one typed in the density section, untouched: a
      // serving says nothing about it.
      expect((labelled['density_g_per_ml'] as num).toDouble(), 1.2);
      // The serving IS kept — as the row's one named measure, which is what
      // lets the reading posture print the label's own line back.
      final servingRow = await db.get(
        'SELECT label, basis_amount FROM ingredient_measure '
        "WHERE ingredient_id = ? AND label LIKE 'serving · %' "
        'AND deleted_at IS NULL',
        [stubId],
      );
      expect(servingRow['label'], 'serving · 14 g');
      expect((servingRow['basis_amount'] as num).toDouble(), 14);

      // --- the piece weight (ADR-0015) ------------------------------------
      // A count default is not saveable without what one of these weighs.
      // Pick `piece`: the sentence appears under the chips, the stranded
      // line names the gap, and Save refuses until the number is in. Then it
      // lands through the form's one Save, unions `piece` into the explicit
      // list, and comes back from the server as a number.
      await scrollTo(tester, find.text('DEFAULT UNIT'));
      final pieceDefault = find.descendant(
        of: find.byKey(const ValueKey('default-unit-row')),
        matching: find.widgetWithText(AnsiModeChip, 'piece'),
      );
      await centerOn(tester, pieceDefault);
      await tester.tap(pieceDefault);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('piece needs a weight on this row'),
        findsOneWidget,
        reason: 'a piece default with no weight is a stranded default',
      );
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Piece can’t be the default unit'),
        findsOneWidget,
        reason: 'Save refuses a piece default nothing weighs',
      );
      expect(
        (await db.get('SELECT default_unit FROM ingredient WHERE id = ?', [
          stubId,
        ]))['default_unit'],
        'g',
        reason: 'the refusal wrote nothing',
      );
      final pieceField = find.descendant(
        of: find.byType(PieceWeightEntry),
        matching: find.byType(EditableText),
      );
      final pieceAdd = find.descendant(
        of: find.byType(PieceWeightEntry),
        matching: find.widgetWithText(FButton, 'Add'),
      );
      await scrollTo(tester, find.text('1 piece weighs'));
      await centerOn(tester, pieceField);
      await tester.enterText(pieceField, '30');
      await tester.pumpAndSettle();
      await centerOn(tester, pieceAdd);
      await tester.tap(pieceAdd);
      await tester.pumpAndSettle();
      // The headline follows the DRAFT and the flag clears; nothing is
      // written yet.
      await pumpUntilFound(tester, find.text('30 g'));
      expect(find.textContaining('piece needs a weight'), findsNothing);
      expect(
        (await db.get(
          'SELECT piece_basis_amount AS p FROM ingredient WHERE id = ?',
          [stubId],
        ))['p'],
        isNull,
        reason: 'the entry fills the draft; the form’s Save writes it',
      );
      await saveFormAndReopen(tester, renamed);
      await waitForDb(
        tester,
        () async =>
            ((await db.get(
                      'SELECT piece_basis_amount AS p FROM ingredient '
                      'WHERE id = ?',
                      [stubId],
                    ))['p']
                    as num?)
                ?.toDouble() ==
            30,
        'the piece weight to land',
      );
      await stack.waitForSyncRoundTrip(tester);
      final weighed = await db.get(
        'SELECT default_unit, piece_basis_amount, piece_source, allowed_units '
        'FROM ingredient WHERE id = ?',
        [stubId],
      );
      expect(weighed['default_unit'], 'piece');
      expect((weighed['piece_basis_amount'] as num).toDouble(), 30);
      expect(weighed['piece_source'], 'manual');
      expect(
        jsonDecode(weighed['allowed_units'] as String) as List,
        contains('piece'),
        reason: 'the weight unions piece into the explicit list (ADR-0015)',
      );
      // The reopened form folds a stated weight to its headline.
      await scrollTo(tester, find.text('PIECE WEIGHT'));
      expect(find.text('30 g'), findsOneWidget);
      expect(find.text('· change'), findsWidgets);
      await leaveToList(tester);

      // --- the USDA match, asked for and said out loud ---------------------
      await scrollTo(tester, find.text(usdaName));
      await tester.tap(find.text(usdaName).first);
      await enterForm(tester);

      // A row nothing has matched carries no provenance line at all — it
      // carries the door instead.
      expect(find.textContaining('from USDA'), findsNothing);
      await scrollTo(tester, find.text('Look up in USDA'));
      await tester.tap(find.text('Look up in USDA'));
      // The sheet asks the REAL server about the name in the field, and the
      // answer comes back over the same session the app syncs on — there is
      // no reference set on the phone to answer from.
      await pumpUntilFound(tester, find.text('USDA · for “$usdaName”'));
      await pumpUntilFound(tester, find.text(usdaFood));
      expect(
        find.text('all words'),
        findsOneWidget,
        reason: 'the band word says how much of the name the food answers',
      );
      await tester.tap(find.text(usdaFood));
      await tester.pumpAndSettle();

      // The pick fills the DRAFT: the numbers are on the form and nothing is
      // written until Save says so.
      expect(
        find.textContaining('Filled from “$usdaFood”'),
        findsOneWidget,
        reason: 'the message line says the pick is not saved yet',
      );
      expect(
        (await db.get('SELECT source FROM ingredient WHERE id = ?', [
          radicchio.id,
        ]))['source'],
        'manual',
        reason: 'looking something up writes nothing',
      );
      await saveFormAndReopen(tester, usdaName);
      await waitForDb(
        tester,
        () async =>
            (await db.get('SELECT source FROM ingredient WHERE id = ?', [
              radicchio.id,
            ]))['source'] !=
            'manual',
        'the pick to land on the row',
      );
      final filled = await db.get(
        'SELECT source, source_label, source_score, density_g_per_ml, macros, '
        'status FROM ingredient WHERE id = ?',
        [radicchio.id],
      );
      final filledSource = filled['source'] as String;
      final filledLabel = filled['source_label'] as String;
      expect(filledSource, startsWith('usda_fdc:'));
      expect(filledLabel, usdaFood);
      // The label and the score are stored beside the stamp, so the form can
      // print the band offline; the food's own numbers come with it.
      expect(filled['source_score'], isNotNull);
      expect(filled['density_g_per_ml'], isNotNull);
      expect(filled['macros'], isNotNull);
      // Filled, never completed: confirming is a human act.
      expect(filled['status'], 'stub');

      // The provenance line at the head of the macros section names the food
      // and how much of the name it answers — read off the row, printable
      // offline, and never the FDC id the stamp files it under.
      await scrollTo(tester, find.text('Filled from USDA · not confirmed'));
      final fit = UsdaMatchFit.of(
        (filled['source_score'] as num).toDouble(),
      ).phraseFor(usdaName);
      expect(find.text('$filledLabel · $fit'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Not this food'), findsOneWidget);
      expect(find.widgetWithText(FButton, 'Choose another ›'), findsOneWidget);
      // The lookup door has no job on a row USDA already filled: the two
      // buttons above are how the match changes now.
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

      // The guarantee, end to end: renaming a row to a name the reference set
      // matches ("Watercress, raw" — checked on the local stack) refills
      // nothing. It is the rename that used to re-fire the server's prefill,
      // which is why this is the name the leg renames to.
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
      // A silence is only a guarantee if a fill had time to arrive: the round
      // trip above already proved the rename reached the server and came
      // back, and this is the margin on top of it.
      final silence = Stopwatch()..start();
      while (silence.elapsed < const Duration(seconds: 4)) {
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
            'a rename refilled the row — something on the server is '
            'matching on its own again, or the decline never uploaded',
      );
      expect(afterRename['macros'], isNull);
      expect(afterRename['density_g_per_ml'], isNull);
      // The refused food is still named — "you said no once" needs a noun.
      expect(afterRename['source_label'], filledLabel);

      await leaveToList(tester);

      // --- add new, by barcode ---------------------------------------------
      // The list's `＋` opens the FORM — it writes on Save, so it can be the
      // create surface, and the scan is one of the two doors the form offers
      // a row with nothing in it yet.
      await tester.tap(
        find
            .descendant(
              of: find.byType(FHeaderAction),
              matching: find.byIcon(FLucideIcons.plus),
            )
            .first,
      );
      await pumpUntilFound(tester, find.text('FILL IT IN FROM'));
      await tester.tap(find.text('Scan a barcode'));
      await pumpUntilFound(tester, find.byType(BarcodeScanSheet));

      // The sheet's stable chrome. On the Simulator the plugin's start
      // neither succeeds nor ERRORS — no camera means it waits forever, so
      // the designed "Ansi can't open the camera" notice never renders
      // (errorBuilder never fires; observed round 12). The notice's on-screen
      // verification moves to the physical-device slice with the rest of the
      // camera legs; what this scenario proves is that the TYPED field stays
      // live regardless — the whole reason D3 made it a permanent sibling
      // rather than a fallback.
      await pumpUntilFound(tester, find.text('OR TYPE THE NUMBER'));

      // Type the digits — the Simulator-walkable path. Downstream of `run`
      // this is the SAME handler the live detector calls.
      //
      // Scoped, not positional: both the scan sheet and the form are in the
      // tree while the scanner is open, and the form's autofocused NAME field
      // is an EditableText too.
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

      // The draft is on the FORM, not in a row: the sheet handed it back and
      // the form's one Save is what writes it — provenance, macros and the
      // name it supplied for a row that had none, together.
      expect(find.textContaining('filled in, not saved'), findsOneWidget);
      expect(
        await db.getAll(
          'SELECT id FROM ingredient WHERE source = ? AND deleted_at IS NULL',
          ['off:$offFixtureBarcode'],
        ),
        isEmpty,
        reason: 'a scan writes nothing on its own',
      );
      await tester.tap(find.byKey(kFormSaveKey));
      await tester.pumpAndSettle();

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
      // D1: a lookup PREFILLS and never completes — but this is a NEW row,
      // and a new row saves complete or not at all: the label's macros made
      // its Save live, and the person pressing it is the human act.
      expect(scannedRow['status'], 'complete');
      expect(scannedRow['macros_basis'], 'g');
      final macros = jsonDecode(scannedRow['macros'] as String) as Map;
      expect(macros['kcal'], 539);
      expect(macros['protein'], 6.3);
      expect(macros['carb'], 57.5);
      expect(macros['fat'], 30.9);

      // The Open Food Facts provenance is the row's, and nothing on the
      // server replaces it with an FDC id on the way through — proven end to
      // end, after the round trip.
      await stack.waitForSyncRoundTrip(tester);
      final afterSync = await db.get(
        'SELECT source, status FROM ingredient WHERE id = ?',
        [scannedRow['id']],
      );
      expect(
        afterSync['source'],
        'off:$offFixtureBarcode',
        reason:
            'something overwrote a barcode row’s provenance — a server '
            'that matches on its own is back',
      );
      expect(afterSync['status'], 'complete');

      // --- back on the list, the G4 hint -----------------------------------
      // The Save ended the form, so the list is already underneath — parked
      // at its restored offset below the band, where a programmatic drag does
      // not move it. So the band is reached the way the first leg reached it:
      // back to the Library, and into the shelf afresh, which mounts the list
      // at its top with the band in view.
      await pumpUntilFound(tester, find.text('Search your vocabulary'));
      await tester.tap(find.byType(FHeaderAction).first);
      await pumpUntilFound(tester, ingredientsShelf);
      await scrollTo(tester, ingredientsShelf);
      await openIngredientsShelf(tester);
      // A new row saves complete or not at all, so the scanned Nutella is not
      // fleshing-out work: it sits in the vocabulary itself, and no row
      // carrying its name asks for anything.
      await scrollTo(tester, find.text('Nutella'));
      final nutellaRow = find
          .ancestor(of: find.text('Nutella').first, matching: find.byType(Row))
          .first;
      expect(
        find.descendant(
          of: nutellaRow,
          matching: find.textContaining('needs completing'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: nutellaRow,
          matching: find.textContaining('needs macros'),
        ),
        findsNothing,
      );
    },
  );
}

/// A bare manual stub as the add form's one Save creates it (ADR-0011): the
/// name, its server-rule `match_text`, and the admission set the form itself
/// opens on — nothing else. No density, no macros, no label, so anything of
/// those on the row afterwards came from the server.
IngredientFormEdit _bareStub(String name) => IngredientFormEdit(
  row: IngredientEdit(
    canonicalName: name,
    defaultUnit: g,
    macrosBasis: MacrosBasis.perG,
    allowedUnits: defaultAllowedUnitSet(
      Ingredient(
        id: '',
        canonicalName: name,
        defaultUnit: g,
        status: IngredientStatus.stub,
      ),
    ),
    source: 'manual',
  ),
);
