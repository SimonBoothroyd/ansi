/// Sim smoke — IMPORT: paste a link → the review screen → resolve every line
/// → Save, over LIVE sync.
///
/// The lines cover the four shapes a review has to answer: an auto match
/// confirmed, a printed RANGE picked, a counted-produce line that arrives
/// UNFLAGGED on its curated default measure, and an unmatched line taken
/// through the create-new chain onto a row of its own. The saved recipe lands
/// FILED in a book, with tokenized steps whose refs are real `line_item` ids
/// and the defaulted line carrying a real `measure_id`.
///
/// The import repository is overridden to the local one, so NO edge function
/// and NO LLM is called — see `SmokeStack.openLibraryWithLocalImport`.
///
/// The nested-recipes leg (the "↪ your recipe" suggestion chip on a review
/// card) is not driven here: the canned payload carries no recipe candidates,
/// and reaching the real matcher would mean the edge function and an LLM. It
/// is host-tested instead.
///
/// Local gate only (`make test-sim FILE=import`), never CI. Needs the local
/// backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'dart:convert';

import 'package:ansi/features/import/presentation/import_view.dart'
    show ImportView;
import 'package:ansi/features/import/presentation/recon_amount.dart'
    show AmountEditor;
import 'package:ansi/features/ingredients/presentation/ingredient_detail_view.dart'
    show kFormSaveKey;
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart'
    show IngredientResultList;
import 'package:ansi/shared/picker_shell.dart' show PickerShell;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/stack.dart';

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

/// Resolves an unmatched (`none`) line to a NEW ingredient the way the review
/// does: open the seeded search sheet, take its create-new footer, walk the
/// ingredient form it pushes over the review, and back out — the line then
/// resolves to that row as an ordinary match. A second line printing the SAME
/// thing finds the row the first one made in the search instead, so nothing is
/// created
/// twice (the commit-time coalescing that used to do this is gone).
Future<void> createIngredientForLine(
  WidgetTester tester,
  int i, {
  required String name,
}) async {
  await expandLine(tester, i);
  final open = find.descendant(
    of: reviewCard(i),
    matching: find.text('Find or create ingredient'),
  );
  await tester.ensureVisible(open);
  await tester.pumpAndSettle();
  await tester.tap(open);
  await pumpUntilFound(tester, find.byType(PickerShell));
  // Search first: a previous line may already have made this row.
  await tester.enterText(
    find.descendant(
      of: find.byType(PickerShell),
      matching: find.byType(EditableText),
    ),
    name,
  );
  await tester.pumpAndSettle();
  final existing = find.descendant(
    of: find.byType(IngredientResultList),
    matching: find.text(name),
  );
  if (existing.evaluate().isNotEmpty) {
    await tester.tap(existing.first);
    await tester.pumpAndSettle();
    return;
  }
  // The footer is seeded with the typed name (else the raw line text).
  final create = find.textContaining('as a new ingredient');
  expect(create, findsOneWidget, reason: 'the create-new footer for line $i');
  await tester.tap(create);
  // ONE push: the form IS the create surface, and it lands OVER the review's
  // sheet. Its Save is the pop the sheet is awaiting — it writes the row and
  // the sheet resolves the line with it. Backing out would write nothing.
  await pumpUntilFound(tester, find.text('CANONICAL NAME'));
  await tester.tap(find.byKey(kFormSaveKey));
  await pumpUntilFound(
    tester,
    find.descendant(of: reviewCard(i), matching: find.text(name)),
  );
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  // NO LLM AND NO NETWORK on the import path: `importRepositoryProvider` is
  // overridden to `SqliteImportRepository`, the same local repository the app
  // uses when Supabase is unconfigured. That is the fake edge function — it
  // returns the canned payload and RE-RESOLVES its candidates against the
  // household's really-synced vocab, so the auto/suggest/none bands below
  // are produced by real data, not by the fixture. Only the extract+match
  // hop is stubbed; the reconciliation UI, the commit write path, PowerSync
  // and the Library are all the real thing.
  //
  // The payload also carries a counted-produce line — "2 red peppers",
  // printed as `piece`, which a measured row refuses under ADR-0010. It
  // arrives on the row's CURATED DEFAULT measure, unflagged, and commits
  // as a `measure_id`; this is the one
  // place that runs end to end, because the default comes off a really
  // synced `ingredient.default_measure_id` (migration 0023's clone leg)
  // rather than a fixture.
  testWidgets('import: link → review → resolve → saved recipe in the Library', (
    tester,
  ) async {
    ignoreForuiSemanticsAssertion();
    final db = stack.db;
    await stack.openLibraryWithLocalImport(tester);

    // The canned payload's `suggest` line only lands in the suggest band if the
    // household vocab actually holds a Parmesan row for it to re-point at.
    // Assert that up front so a vocab change fails HERE, with a clear reason,
    // rather than as a mystery finder miss further down. (After the Library
    // renders: the vocab is what the first sync delivered.)
    final parmesanRows = await db.getAll(
      'SELECT canonical_name FROM ingredient '
      "WHERE canonical_name LIKE '%armesan%' AND deleted_at IS NULL",
    );
    expect(
      parmesanRows,
      hasLength(1),
      reason:
          'the import file needs exactly one %armesan% vocab row: the suggest '
          'line re-points at it and the "did you mean" pill carries its name',
    );

    // The bare default book's own empty shelf carries the two doors — the
    // Library header has no `＋`, because a door that makes a recipe is the
    // one that knows the shelf it goes on.
    await tester.tap(find.text('import one'));
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
    // The shared six-section header now sits above the list's
    // section label, and the review list is lazy — scroll to it.
    await scrollTo(tester, find.text('INGREDIENTS'));
    expect(find.text('INGREDIENTS'), findsOneWidget);
    // The named group sits under the first group's cards; with the seam's
    // extra "2 red peppers" line the review list (lazy) no longer builds it
    // on arrival — scroll to it rather than wait for it, then come back up.
    await scrollTo(tester, find.text('To finish'));
    expect(find.text('To finish'), findsOneWidget); // the named group
    await scrollTo(tester, find.text('INGREDIENTS'), delta: -300);
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

    // Everything still unmatched (`none`) becomes a new ingredient through the
    // one add flow — sheet → form → back. The two identical
    // chilli lines print the same name, so the second finds the row the first
    // made: ONE created ingredient, with nothing minted at commit.
    const rawNames = {
      2: 'tinned chopped tomatoes',
      3: 'Aleppo chilli flakes',
      4: 'Aleppo chilli flakes',
      7: 'fresh basil leaves',
    };
    for (final i in [2, 3, 4, 7]) {
      // Expand FIRST: a below-the-fold ListView child isn't built at all, so
      // probing its labels before scrolling to it always reads "clean" and the
      // loop would silently skip the line (exactly how the gate stayed locked
      // on the first on-sim run of this tail).
      await expandLine(tester, i);
      if (lineShows(i, 'Match an ingredient') ||
          lineShows(i, 'Find or create ingredient')) {
        await createIngredientForLine(tester, i, name: rawNames[i]!);
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

    // the two lines the extractor flagged optional (the chilli
    // pair) committed AS optional. The flag used to stop at the review card.
    final optionalLines = await db.get(
      'SELECT COUNT(*) AS c FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.optional = 1 AND li.deleted_at IS NULL',
      [recipeId],
    );
    expect(optionalLines['c'] as int, 2);

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

    // Every line resolved to a real ingredient; the second chilli line found
    // the row the first one made (nothing created twice), and the commit
    // minted nothing — the `import_stub` leg is retired.
    final unresolved = await db.get(
      'SELECT COUNT(*) AS c FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? AND li.ingredient_id IS NULL',
      [recipeId],
    );
    expect(unresolved['c'] as int, 0);
    final chilliRows = await db.getAll(
      'SELECT id FROM ingredient '
      "WHERE canonical_name LIKE '%chilli flakes%' AND deleted_at IS NULL",
    );
    expect(chilliRows, hasLength(1));
    expect(
      await db.getAll("SELECT id FROM ingredient WHERE source = 'import_stub'"),
      isEmpty,
      reason: 'no path mints a stub as a side effect any more',
    );

    // It SYNCED — the whole point of running this on a device.
    await stack.waitForSyncRoundTrip(tester);

    // …and it is visible in the Library, filed under a book. The recipe page
    // sits OUTSIDE the tab shell (no bottom nav here); the commit REPLACED the
    // spent import flow with it, so the Library tab is still underneath and
    // the header's back action pops straight onto it.
    await tapBack(tester);
    await pumpUntilFound(tester, find.text('Our Cookbook'));
    await tester.pumpAndSettle();
    expect(
      find.text('Weeknight Tomato Pasta'),
      findsWidgets,
      reason: 'the imported recipe never appeared in the Library',
    );
  });
}
