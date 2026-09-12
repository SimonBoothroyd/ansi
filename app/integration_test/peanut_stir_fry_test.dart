/// Sim smoke — IMPORT, the hard page: a recipe written in a British kitchen's
/// words, whose answers are only in the picker's SEARCH.
///
/// `import_test.dart` drives the shapes a review has to answer. This file
/// drives the one the seeded vocabulary actually produces on such a page: with
/// [peanutStirFryPayloadJson] three lines arrive `none` with NO candidates at
/// all and one arrives `suggest` with a single chip that is the wrong jar, so
/// every outstanding line has to be answered by typing. That is the path the
/// owner reported as broken, and nothing else in the suite walks it.
///
/// The import repository is overridden to the local one, so NO edge function
/// and NO LLM is called — see `SmokeStack.openLibraryWithLocalImport`.
///
/// Local gate only (`make test-sim FILE=peanut_stir_fry`), never CI. Needs the
/// local backend running (`make db-up`) and the usual `--dart-define`s.
library;

import 'package:ansi/features/import/data/canned_payload.dart'
    show peanutStirFryPayloadJson;
import 'package:ansi/features/import/presentation/import_view.dart'
    show ImportView;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/drive.dart';
import 'support/review.dart';
import 'support/stack.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late SmokeStack stack;

  setUpAll(() async => stack = await SmokeStack.start());
  tearDownAll(() => stack.dispose());

  testWidgets('import: a suggest line overridden and three none lines found, '
      'all through the search', (tester) async {
    ignoreForuiSemanticsAssertion();
    await stack.openLibraryWithLocalImport(
      tester,
      payloadJson: peanutStirFryPayloadJson,
    );

    await tester.tap(find.text('import one'));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldIn(find.byType(ImportView)),
      'https://example.com/peanut-tofu-stir-fry',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import from link'));
    await pumpUntilFound(tester, find.text('Review recipe'));
    expect(find.text('Peanut Tofu Stir-Fry'), findsOneWidget);

    // Line 3 — `suggest`. The one offered chip is Ground Coriander; the herb
    // the page means is stored as Cilantro, and it is only reachable by
    // typing.
    await searchAndPickForLine(tester, 3, query: 'cilantro', pick: 'Cilantro');
    expect(
      lineShows(3, 'Match an ingredient'),
      isFalse,
      reason: 'the Cilantro pick never landed on the coriander line',
    );
    expect(lineShows(3, 'Cilantro'), isTrue);

    // Line 6 — `none`, with an EMPTY candidate list: the extractor offered
    // nothing for "sugar snap peas", and this cook's answer is the frozen row.
    await searchAndPickForLine(tester, 6, query: 'frozen', pick: 'Frozen Peas');
    expect(lineShows(6, 'Match an ingredient'), isFalse);
    expect(lineShows(6, 'Frozen Peas'), isTrue);

    // The other two `none` lines: the greens this cook has in, and the same
    // oil under its American name.
    await searchAndPickForLine(tester, 0, query: 'napa', pick: 'Napa Cabbage');
    await searchAndPickForLine(
      tester,
      1,
      query: 'peanut oil',
      pick: 'Peanut Oil',
    );

    final footer = find.textContaining(RegExp('Save recipe|need you'));
    await scrollTo(tester, footer);
    expect(
      find.text('Save recipe'),
      findsOneWidget,
      reason:
          'the Save gate is still locked: '
          '${tester.widget<Text>(footer.first).data}',
    );
    await tester.tap(find.text('Save recipe'));
    await pumpUntilFound(tester, find.text('Peanut Tofu Stir-Fry'));
    await tester.pumpAndSettle();

    // Every line committed against the row the human chose — the four searched
    // ones included, in printed order.
    final recipe = await stack.db.get(
      "SELECT id FROM recipe WHERE title = 'Peanut Tofu Stir-Fry' "
      'AND deleted_at IS NULL',
    );
    final names = (await stack.db.getAll(
      'SELECT i.canonical_name FROM recipe_line_item li '
      'JOIN ingredient_group gr ON gr.id = li.group_id '
      'JOIN ingredient i ON i.id = li.ingredient_id '
      'WHERE gr.recipe_id = ? AND li.deleted_at IS NULL '
      'ORDER BY li.sort_order',
      [recipe['id']],
    )).map((r) => r['canonical_name'] as String).toList();
    expect(names, hasLength(10));
    expect(names[0], 'Napa Cabbage');
    expect(names[1], 'Peanut Oil');
    expect(names[3], 'Cilantro');
    expect(names[6], 'Frozen Peas');

    // The learning loop wrote the page's own words back on the rows the human
    // chose, so the next import of this recipe matches them. None of the four
    // is a name the vocabulary already holds, so all four are learnable.
    final aliases = (await stack.db.getAll(
      'SELECT alias_text FROM ingredient_alias '
      "WHERE source = 'import_correction' AND deleted_at IS NULL",
    )).map((r) => r['alias_text'] as String).toSet();
    expect(
      aliases,
      containsAll([
        'pak choi',
        'groundnut oil',
        'coriander',
        'sugar snap peas',
      ]),
    );

    await stack.waitForSyncRoundTrip(tester);
  });
}
