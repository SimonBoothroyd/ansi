import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/import/data/import_repository_impl.dart';
import 'package:mise/features/import/domain/import_repository.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/ingredients/domain/normalize.dart';
import 'package:mise/features/ingredients/domain/search_query.dart';
import 'package:mise/features/recipes/data/recipe_repository_impl.dart';
import 'package:mise/features/recipes/domain/method_step.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

Future<void> _seedIngredient(
  PowerSyncDatabase db,
  String id,
  String name,
) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  "status, source, match_text) VALUES (?, 'h', ?, 'g', 'complete', 'seed', ?)",
  [id, name, name.toLowerCase()],
);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;
  late SqliteImportRepository repo;

  setUp(() async {
    (db, dir) = await openTestDb();
    repo = SqliteImportRepository(db, householdId: 'h');
    await _seedIngredient(db, 'ing-onion', 'Onion');
    await _seedIngredient(db, 'ing-spaghetti', 'Spaghetti');
    await _seedIngredient(db, 'ing-tomatoes', 'Chopped tomatoes');
  });

  tearDown(() => closeTestDb(db, dir));

  // A small payload: an auto onion, two identical no-match "mystery" lines, and
  // a no-match "yellow onion" the user corrects onto the real onion. One step
  // references lines 0 (onion) and 1 (mystery).
  const payload = ReconciliationPayload(
    title: 'Test Recipe',
    servingsBase: 2,
    groups: [
      ReconGroup(
        lines: [
          ReconLine(
            raw: RawLineItem(
              ingredientText: 'onion, diced',
              qty: 1,
              unit: 'piece',
            ),
            band: MatchBand.auto,
            candidates: [
              MatchCandidate(ingredientId: 'ing-onion', canonicalName: 'Onion'),
            ],
          ),
          ReconLine(
            raw: RawLineItem(ingredientText: 'mystery spice', unit: 'tsp'),
            band: MatchBand.none,
          ),
          ReconLine(
            raw: RawLineItem(ingredientText: 'mystery spice', unit: 'tsp'),
            band: MatchBand.none,
          ),
          ReconLine(
            raw: RawLineItem(ingredientText: 'yellow onion', qty: 1),
            band: MatchBand.none,
          ),
        ],
      ),
    ],
    steps: [
      Step(
        tokens: [
          TextToken(s: 'Soften the '),
          RefToken(refs: [0], label: 'onion'),
          TextToken(s: ' with the '),
          RefToken(refs: [1], label: 'spice'),
          TextToken(s: '.'),
        ],
      ),
    ],
  );

  CommitPayloadResult resolvedCommit() {
    const p = payload;
    final resolutions = [
      initialResolution(0, p.flatLines[0]), // accept auto onion
      initialResolution(1, p.flatLines[1]).resolveToNewStub('Mystery Spice'),
      initialResolution(2, p.flatLines[2]).resolveToNewStub('Mystery Spice'),
      initialResolution(
        3,
        p.flatLines[3],
      ).resolveToIngredient('ing-onion', 'Onion', correction: true),
    ];
    return (payload: p, resolutions: resolutions);
  }

  test('commit writes the recipe, groups, and non-null line items', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 3,
        issuesByLine: null,
      ),
    );

    final recipe = await db.getOptional('SELECT * FROM recipe WHERE id = ?', [
      recipeId,
    ]);
    expect(recipe, isNotNull);
    expect(recipe!['title'], 'Test Recipe');
    expect((recipe['servings_base'] as num).toDouble(), 3);

    final lines = await db.getAll(
      'SELECT li.* FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? ORDER BY li.sort_order',
      [recipeId],
    );
    expect(lines, hasLength(4));
    // recipe_line_item.ingredient_id is NOT NULL — every line resolved.
    expect(lines.every((r) => r['ingredient_id'] != null), isTrue);
  });

  test('a resolved measure persists as measure_id + piece', () async {
    // The onion carries a "clove" measure; a line resolved to it and quantified
    // by that measure must persist the FK (not degrade to a bare "clove"/piece).
    await db.execute(
      'INSERT INTO ingredient_measure (id, household_id, ingredient_id, label, '
      'basis_amount, sort_order, source) VALUES '
      "('m-clove', 'h', 'ing-onion', 'clove', 3, 0, 'manual')",
    );
    const p = ReconciliationPayload(
      title: 'Measured',
      servingsBase: 1,
      groups: [
        ReconGroup(
          lines: [
            ReconLine(
              raw: RawLineItem(
                ingredientText: 'garlic clove',
                qty: 2,
                unit: 'clove', // the measure label rides on the line's unit
              ),
              band: MatchBand.auto,
              candidates: [
                MatchCandidate(
                  ingredientId: 'ing-onion',
                  canonicalName: 'Onion',
                ),
              ],
            ),
          ],
        ),
      ],
    );
    final recipeId = await repo.commit(
      buildCommit(
        p,
        [initialResolution(0, p.flatLines[0])],
        servingsBase: 1,
        issuesByLine: null,
      ),
    );
    final line = await db.getAll(
      'SELECT li.unit, li.measure_id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id WHERE g.recipe_id = ?',
      [recipeId],
    );
    expect(line.single['measure_id'], 'm-clove');
    expect(line.single['unit'], 'piece'); // measure rows store unit='piece'
  });

  test('the committed recipe is FILED into the default book', () async {
    // The Library renders books and skips book-less recipes, so a null book_id
    // saves the recipe where nothing can show it. Import files it exactly like
    // the new-recipe path (`RecipeEditor.build` → `ensureDefaultBook`).
    await db.execute(
      'INSERT INTO book (id, household_id, name, sort_order, created_at, '
      "updated_at) VALUES ('bk-1', 'h', 'Our Cookbook', 0, '', '')",
    );
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final row = await db.get('SELECT book_id FROM recipe WHERE id = ?', [
      recipeId,
    ]);
    expect(row['book_id'], 'bk-1');
  });

  test('with no book yet, the commit creates the default one', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final books = await db.getAll('SELECT id, name FROM book');
    expect(books, hasLength(1));
    expect(books.single['name'], 'Our Cookbook');
    final row = await db.get('SELECT book_id FROM recipe WHERE id = ?', [
      recipeId,
    ]);
    expect(row['book_id'], books.single['id']);
  });

  test('identical no-match lines coalesce onto one created stub', () async {
    final c = resolvedCommit();
    await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final stubs = await db.getAll(
      "SELECT * FROM ingredient WHERE source = 'import_stub'",
    );
    expect(stubs, hasLength(1));
    expect(stubs.single['canonical_name'], 'Mystery Spice');
    expect(stubs.single['status'], 'stub');

    // Both mystery lines point at that one stub.
    final lines = await db.getAll(
      'SELECT ingredient_id FROM recipe_line_item ORDER BY sort_order',
    );
    expect(lines[1]['ingredient_id'], stubs.single['id']);
    expect(lines[2]['ingredient_id'], stubs.single['id']);
  });

  test('a correction writes an import_correction alias', () async {
    final c = resolvedCommit();
    await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final aliases = await db.getAll(
      "SELECT * FROM ingredient_alias WHERE source = 'import_correction'",
    );
    expect(aliases, hasLength(1));
    expect(aliases.single['alias_text'], 'yellow onion');
    expect(aliases.single['ingredient_id'], 'ing-onion');
  });

  test('D6: a committed stub and a correction alias carry the SERVER phrase '
      'rules, not the character-level search normalizer', () async {
    // The last D6 residual: import's commit was still writing `match_text`
    // with `normalizeSearchQuery`, so a stub it created carried text the
    // server's cascade would never search for — the exact silent matching
    // regression D6 closed on every other writer.
    const p = ReconciliationPayload(
      title: 'Test Recipe',
      servingsBase: 2,
      groups: [
        ReconGroup(
          lines: [
            ReconLine(
              raw: RawLineItem(ingredientText: 'chicken thighs', unit: 'g'),
              band: MatchBand.none,
            ),
            ReconLine(
              raw: RawLineItem(ingredientText: 'ripe tomatoes, chopped'),
              band: MatchBand.none,
            ),
          ],
        ),
      ],
    );
    final resolutions = [
      initialResolution(
        0,
        p.flatLines[0],
      ).resolveToNewStub('Chicken thighs, boneless'),
      initialResolution(1, p.flatLines[1]).resolveToIngredient(
        'ing-tomatoes',
        'Chopped tomatoes',
        correction: true,
      ),
    ];
    await repo.commit(
      buildCommit(p, resolutions, servingsBase: 2, issuesByLine: null),
    );

    const stubName = 'Chicken thighs, boneless';
    final stub = await db.get(
      "SELECT match_text FROM ingredient WHERE source = 'import_stub'",
    );
    // The server singularizes and re-orders; the search normalizer only
    // folds characters. Both halves matter: the value is what the server
    // would have written, and it is NOT what the old call site wrote.
    expect(stub['match_text'], 'chicken thigh boneless');
    expect(stub['match_text'], normalizeMatchText(stubName));
    expect(stub['match_text'], isNot(normalizeSearchQuery(stubName)));

    const aliasText = 'ripe tomatoes, chopped';
    final alias = await db.get(
      'SELECT alias_text, match_text FROM ingredient_alias '
      "WHERE source = 'import_correction'",
    );
    expect(alias['alias_text'], aliasText);
    expect(alias['match_text'], normalizeMatchText(aliasText));
    expect(alias['match_text'], isNot(normalizeSearchQuery(aliasText)));
  });

  test('step line_index refs are remapped to real line_item_ids', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final lines = await db.getAll(
      'SELECT li.id FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? ORDER BY li.sort_order',
      [recipeId],
    );
    final idByIndex = [for (final r in lines) r['id'] as String];

    final row = await db.getOptional('SELECT steps FROM recipe WHERE id = ?', [
      recipeId,
    ]);
    final steps = jsonDecode(row!['steps'] as String) as List;
    final tokens = (steps.single as Map)['tokens'] as List;
    final refs = tokens
        .where((t) => (t as Map)['t'] == 'ref')
        .map((t) => ((t as Map)['refs'] as List).cast<String>())
        .toList();
    // ref[0] → line 0's id, ref[1] → line 1's id (no line_index survives).
    expect(refs[0], [idByIndex[0]]);
    expect(refs[1], [idByIndex[1]]);
  });

  test(
    'a chip pointing at a DROPPED line demotes to its label as text',
    () async {
      // The never-dangling-line invariant's other half: the line is not
      // written, and the step that named it keeps the word instead of losing
      // it (or pointing at whatever line inherited the index).
      const p = payload;
      final resolutions = [
        initialResolution(0, p.flatLines[0]), // onion, kept
        initialResolution(1, p.flatLines[1]).resolveToNewStub('Mystery').drop(),
        initialResolution(2, p.flatLines[2]).resolveToNewStub('Mystery'),
        initialResolution(
          3,
          p.flatLines[3],
        ).resolveToIngredient('ing-onion', 'Onion'),
      ];

      final recipeId = await repo.commit(
        buildCommit(p, resolutions, servingsBase: 2, issuesByLine: null),
      );
      final lines = await db.getAll(
        'SELECT li.id FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY li.sort_order',
        [recipeId],
      );
      expect(lines, hasLength(3)); // the dropped line was never written

      final row = await db.getOptional(
        'SELECT steps FROM recipe WHERE id = ?',
        [recipeId],
      );
      final steps = jsonDecode(row!['steps'] as String) as List;
      final tokens = ((steps.single as Map)['tokens'] as List)
          .cast<Map<String, Object?>>();
      // The onion chip survives; the spice chip is now prose reading "spice".
      expect(tokens.where((t) => t['t'] == 'ref'), hasLength(1));
      expect(
        tokens.where((t) => t['t'] == 'text').map((t) => t['s']),
        containsAllInOrder(<String>['Soften the ', ' with the ', 'spice', '.']),
      );
    },
  );

  test('the committed recipe reloads with tokenized method steps', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        servingsBase: 2,
        issuesByLine: null,
      ),
    );

    final recipeRepo = SqliteRecipeRepository(db, householdId: 'h');
    final recipe = await recipeRepo.watchRecipe(recipeId).first;
    expect(recipe, isNotNull);
    expect(recipe!.methodSteps, isNotNull);
    expect(recipe.steps, isEmpty); // tokenized shape, no legacy plain text

    // The fold resolves the onion chip's live quantity off the real line item.
    final lineById = {
      for (final g in recipe.groups)
        for (final i in g.items) i.id: i,
    };
    final spans = foldMethod(recipe.methodSteps!.single, lineById: lineById);
    final chips = spans.whereType<MethodChipSpan>().toList();
    expect(chips.first.label, 'onion');
    expect(chips.first.amount, '1'); // 1 piece → bare count
  });

  test(
    'startImport resolves canned candidates against the local vocab',
    () async {
      final result = await repo.startImport(const ImportFromUrl('x'));
      final flat = result.flatLines;
      // Spaghetti + Chopped tomatoes are seeded → they stay matched with a real
      // candidate id; unseeded lines degrade to none.
      final spaghetti = flat.firstWhere(
        (l) => l.raw.ingredientText == 'spaghetti',
      );
      expect(spaghetti.band, MatchBand.auto);
      expect(spaghetti.candidates.single.ingredientId, 'ing-spaghetti');

      final basil = flat.firstWhere(
        (l) => l.raw.ingredientText == 'fresh basil leaves',
      );
      expect(basil.band, MatchBand.none);
      expect(basil.candidates, isEmpty);
    },
  );

  test('a candidate resolves by token match, not only exact name (so a '
      'suggestion still surfaces when the vocab name differs)', () async {
    // Vocab holds "Parmesan cheese"; the canned candidate is bare
    // "Parmesan". Round-1 bug: only exact names resolved, so this line
    // silently degraded to `none` and showed no suggestion.
    await _seedIngredient(db, 'ing-parm', 'Parmesan cheese');
    final result = await repo.startImport(const ImportFromUrl('x'));
    final parm = result.flatLines.firstWhere(
      (l) => l.raw.ingredientText == 'Parmesan, grated',
    );
    expect(parm.band, MatchBand.suggest);
    expect(parm.candidates.single.ingredientId, 'ing-parm');
  });
}

typedef CommitPayloadResult = ({
  ReconciliationPayload payload,
  List<LineResolution> resolutions,
});
