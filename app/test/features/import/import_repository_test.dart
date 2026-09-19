import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/search/search_query.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/data/import_repository_impl.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/domain/review_groups.dart';
import 'package:ansi/features/ingredients/data/ingredient_repository_impl.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/recipes/data/recipe_repository_impl.dart';
import 'package:ansi/features/recipes/domain/component_math.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/test_db.dart';

/// The header draft as the review hands it to `buildCommit` (plan 0025 #4):
/// the page's own title and times, the serving count and yield the test
/// states, and no book — so these commits exercise the default-book filing
/// the repository guarantees on its own.
Recipe _header(
  ReconciliationPayload payload, {
  double servingsBase = 2,
  double? yieldQty,
  Unit? yieldUnit,
}) => Recipe(
  id: 'draft',
  title: payload.title,
  servingsBase: servingsBase,
  yieldQty: yieldQty,
  yieldUnit: yieldUnit,
  cookTimeSeconds: payload.cookTimeSeconds?.lowSeconds,
  totalTimeSeconds: payload.totalTimeSeconds?.lowSeconds,
);

Future<void> _seedIngredient(
  PowerSyncDatabase db,
  String id,
  String name,
) => db.execute(
  'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
  "status, source, match_text) VALUES (?, 'h', ?, 'g', 'complete', 'seed', ?)",
  [id, name, name.toLowerCase()],
);

Future<void> _seedAlias(
  PowerSyncDatabase db,
  String ingredientId,
  String text,
) => db.execute(
  'INSERT INTO ingredient_alias (id, household_id, ingredient_id, alias_text, '
  "match_text, source) VALUES (?, 'h', ?, ?, ?, 'import_correction')",
  ['alias-$text', ingredientId, text, normalizeMatchText(text)],
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
    // The row the review's create-new chain would have made for the two
    // "mystery spice" lines (sheet → form → back) before either resolved.
    await _seedIngredient(db, 'ing-mystery', 'Mystery Spice');
  });

  tearDown(() => closeTestDb(db, dir));

  // A small payload: an auto onion, two identical no-match "mystery" lines
  // (both resolved to the row the first one created), and a no-match "yellow
  // onion" the user corrects onto the real onion. One step references lines 0
  // (onion) and 1 (mystery).
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
      initialResolution(
        1,
        p.flatLines[1],
      ).resolveToIngredient('ing-mystery', 'Mystery Spice'),
      initialResolution(
        2,
        p.flatLines[2],
      ).resolveToIngredient('ing-mystery', 'Mystery Spice'),
      initialResolution(
        3,
        p.flatLines[3],
      ).resolveToIngredient('ing-onion', 'Onion', correction: true),
    ];
    return (payload: p, resolutions: resolutions);
  }

  test('commit writes the optional flag the review carried', () async {
    const p = ReconciliationPayload(
      title: 'Optional Lime',
      servingsBase: 2,
      groups: [
        ReconGroup(
          lines: [
            ReconLine(
              raw: RawLineItem(ingredientText: 'onion', qty: 1, unit: 'piece'),
              band: MatchBand.auto,
              candidates: [
                MatchCandidate(
                  ingredientId: 'ing-onion',
                  canonicalName: 'Onion',
                ),
              ],
            ),
            ReconLine(
              raw: RawLineItem(
                ingredientText: 'lime, to serve',
                optional: true,
              ),
              band: MatchBand.none,
            ),
          ],
        ),
      ],
    );
    final recipeId = await repo.commit(
      buildCommit(
        p,
        [
          initialResolution(0, p.flatLines[0]),
          initialResolution(
            1,
            p.flatLines[1],
          ).resolveToIngredient('ing-onion', 'Onion'),
        ],
        header: _header(p),
        issuesByLine: null,
      ),
    );
    final rows = await db.getAll(
      'SELECT li.optional FROM recipe_line_item li '
      'JOIN ingredient_group g ON g.id = li.group_id '
      'WHERE g.recipe_id = ? ORDER BY li.sort_order',
      [recipeId],
    );
    expect(rows.map((r) => r['optional']), [0, 1]);
  });

  test('commit writes the recipe, groups, and non-null line items', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        header: _header(c.payload, servingsBase: 3),
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
        header: _header(p, servingsBase: 1),
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
        header: _header(c.payload),
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
        header: _header(c.payload),
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

  test(
    'the commit creates no ingredient — two lines on one created row point at '
    'it, and the vocabulary is exactly what it was',
    () async {
      final before = (await db.getAll('SELECT id FROM ingredient')).length;
      final c = resolvedCommit();
      await repo.commit(
        buildCommit(
          c.payload,
          c.resolutions,
          header: _header(c.payload),
          issuesByLine: null,
        ),
      );

      expect((await db.getAll('SELECT id FROM ingredient')).length, before);
      expect(
        await db.getAll(
          "SELECT id FROM ingredient WHERE source = 'import_stub'",
        ),
        isEmpty,
        reason: 'the import_stub leg is retired — nothing mints one',
      );

      // Both mystery lines point at the row the review made.
      final lines = await db.getAll(
        'SELECT ingredient_id FROM recipe_line_item ORDER BY sort_order',
      );
      expect(lines[1]['ingredient_id'], 'ing-mystery');
      expect(lines[2]['ingredient_id'], 'ing-mystery');
    },
  );

  test('a correction writes an import_correction alias', () async {
    final c = resolvedCommit();
    await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        header: _header(c.payload),
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

  test('a correction alias carries the SERVER phrase rules, not the '
      'character-level search normalizer', () async {
    // The last D6 residual: import's commit was still writing `match_text`
    // with `normalizeSearchQuery`, so an alias it wrote carried text the
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
              raw: RawLineItem(ingredientText: 'ripe tomatoes'),
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
      ).resolveToIngredient('ing-onion', 'Onion'),
      initialResolution(1, p.flatLines[1]).resolveToIngredient(
        'ing-tomatoes',
        'Chopped tomatoes',
        correction: true,
      ),
    ];
    await repo.commit(
      buildCommit(p, resolutions, header: _header(p), issuesByLine: null),
    );

    // The server singularizes; the search normalizer only folds characters.
    // Both halves matter: the value is what the server would have written,
    // and it is NOT what the old call site wrote.
    const aliasText = 'ripe tomatoes';
    final alias = await db.get(
      'SELECT alias_text, match_text FROM ingredient_alias '
      "WHERE source = 'import_correction'",
    );
    expect(alias['alias_text'], aliasText);
    expect(alias['match_text'], normalizeMatchText(aliasText));
    expect(alias['match_text'], isNot(normalizeSearchQuery(aliasText)));
  });

  group('the learning loop lands in the ONE namespace', () {
    // A one-line import, resolved onto [ingredientId] as a correction — the
    // shape that learns an alias. Returns the committed recipe's id.
    Future<String> commitCorrection(
      String text, {
      required String ingredientId,
      required String name,
      String title = 'Namespace Recipe',
    }) {
      final p = ReconciliationPayload(
        title: title,
        servingsBase: 2,
        groups: [
          ReconGroup(
            lines: [
              ReconLine(
                raw: RawLineItem(ingredientText: text, qty: 1, unit: 'piece'),
                band: MatchBand.none,
              ),
            ],
          ),
        ],
      );
      return repo.commit(
        buildCommit(
          p,
          [
            initialResolution(
              0,
              p.flatLines[0],
            ).resolveToIngredient(ingredientId, name, correction: true),
          ],
          header: _header(p),
          issuesByLine: null,
        ),
      );
    }

    /// The ingredient each live alias belongs to, keyed by `match_text`.
    Future<Map<String, String>> aliasOwners() async => {
      for (final r in await db.getAll(
        'SELECT match_text, ingredient_id FROM ingredient_alias '
        'WHERE deleted_at IS NULL',
      ))
        r['match_text'] as String: r['ingredient_id'] as String,
    };

    Future<String?> lineIngredient(String recipeId) async {
      final row = await db.get(
        'SELECT li.ingredient_id FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ?',
        [recipeId],
      );
      return row['ingredient_id'] as String?;
    }

    test("raw text that is ANOTHER row's name is not learned, and the line "
        'still commits', () async {
      // The shape the owner's live data shows: "extra-firm tofu" corrected
      // onto Super Firm Tofu normalizes to the text Extra Firm Tofu is
      // *called*.
      await _seedIngredient(db, 'ing-extra', 'Extra Firm Tofu');
      await _seedIngredient(db, 'ing-super', 'Super Firm Tofu');
      expect(normalizeMatchText('extra-firm tofu'), 'extra firm tofu');

      final recipeId = await commitCorrection(
        'extra-firm tofu',
        ingredientId: 'ing-super',
        name: 'Super Firm Tofu',
      );

      expect(
        await aliasOwners(),
        isEmpty,
        reason: 'the name belongs to Extra Firm Tofu; nothing may be learned',
      );
      expect(
        await lineIngredient(recipeId),
        'ing-super',
        reason: 'the line resolves to the row the human picked either way',
      );
    });

    test("raw text that is ANOTHER row's alias is not learned", () async {
      await _seedIngredient(db, 'ing-frozen-peas', 'Frozen Peas');
      // The seed's own alias on a different row — `garden peas` is Onion's
      // here purely so the collision is unambiguous.
      await _seedAlias(db, 'ing-onion', 'garden peas');

      final recipeId = await commitCorrection(
        'garden peas',
        ingredientId: 'ing-frozen-peas',
        name: 'Frozen Peas',
      );

      expect(await aliasOwners(), {'garden pea': 'ing-onion'});
      expect(await lineIngredient(recipeId), 'ing-frozen-peas');
    });

    test(
      'the PICKED row owning the text is a no-op, not a collision',
      () async {
        // The page printed what the row is already called. Nothing to learn,
        // nothing wrong: an alias echoing its own row's name is noise.
        final recipeId = await commitCorrection(
          'Onions',
          ingredientId: 'ing-onion',
          name: 'Onion',
        );

        expect(await aliasOwners(), isEmpty);
        expect(await lineIngredient(recipeId), 'ing-onion');
      },
    );

    test('an alias the picked row already has is not duplicated', () async {
      await _seedAlias(db, 'ing-onion', 'brown onions');

      await commitCorrection(
        'brown onions',
        ingredientId: 'ing-onion',
        name: 'Onion',
      );

      expect(
        await db.getAll(
          'SELECT id FROM ingredient_alias WHERE deleted_at IS NULL',
        ),
        hasLength(1),
        reason: 'find-or-create: one import must not pile up a second row',
      );
    });

    test('an honest new alias is still learned', () async {
      final recipeId = await commitCorrection(
        'brown onions',
        ingredientId: 'ing-onion',
        name: 'Onion',
      );

      expect(await aliasOwners(), {'brown onion': 'ing-onion'});
      expect(await lineIngredient(recipeId), 'ing-onion');
      final alias = await db.get(
        'SELECT alias_text, source FROM ingredient_alias',
      );
      expect(alias['alias_text'], 'brown onions');
      expect(alias['source'], 'import_correction');
    });

    test('a whole printed LINE is not learned, and an honest name beside it '
        'still is', () async {
      // The owner's cloud shows rows like "Olive oil, for frying" — a line,
      // not a name, that no future line will ever print again. It is skipped
      // the way a collision is: silently, with the line still committed
      // against the row the human picked.
      const p = ReconciliationPayload(
        title: 'A Line And A Name',
        servingsBase: 2,
        groups: [
          ReconGroup(
            lines: [
              ReconLine(
                raw: RawLineItem(
                  ingredientText: 'olive oil, for frying',
                  qty: 2,
                ),
                band: MatchBand.none,
              ),
              ReconLine(
                raw: RawLineItem(ingredientText: 'brown onions', qty: 1),
                band: MatchBand.none,
              ),
            ],
          ),
        ],
      );
      final recipeId = await repo.commit(
        buildCommit(
          p,
          [
            initialResolution(0, p.flatLines[0]).resolveToIngredient(
              'ing-spaghetti',
              'Spaghetti',
              correction: true,
            ),
            initialResolution(
              1,
              p.flatLines[1],
            ).resolveToIngredient('ing-onion', 'Onion', correction: true),
          ],
          header: _header(p),
          issuesByLine: null,
        ),
      );

      expect(await aliasOwners(), {
        'brown onion': 'ing-onion',
      }, reason: 'the name is kept; the line is not');
      // Both lines committed against the rows the human picked — refusing to
      // LEARN is not refusing to save.
      final lines = await db.getAll(
        'SELECT li.ingredient_id FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY li.sort_order',
        [recipeId],
      );
      expect(lines.map((r) => r['ingredient_id']), [
        'ing-spaghetti',
        'ing-onion',
      ]);
    });

    test('a phrase that hands the choice to the cook is not learned '
        'either', () async {
      // The bug this test is named after. His "Vegan Mac and Cheese with
      // Silken Tofu Sauce" printed "1 lb your favourite pasta"; the extractor
      // split the amount off, so the loop was handed "your favourite pasta",
      // which carries no comma, no *or*, no slash and no bracket and was
      // learned onto Protein Pasta. The amount already being gone is exactly
      // why the rule cannot be about the printed line — there is no line here
      // to compare against.
      await _seedIngredient(db, 'ing-pasta', 'Protein Pasta');
      const p = ReconciliationPayload(
        title: 'Vegan Mac and Cheese',
        servingsBase: 4,
        groups: [
          ReconGroup(
            lines: [
              ReconLine(
                raw: RawLineItem(
                  ingredientText: 'your favourite pasta',
                  qty: 1,
                  unit: 'lb',
                  rawAmount: '1 lb',
                ),
                band: MatchBand.none,
              ),
              ReconLine(
                raw: RawLineItem(ingredientText: 'brown onions', qty: 1),
                band: MatchBand.none,
              ),
            ],
          ),
        ],
      );
      final recipeId = await repo.commit(
        buildCommit(
          p,
          [
            initialResolution(0, p.flatLines[0]).resolveToIngredient(
              'ing-pasta',
              'Protein Pasta',
              correction: true,
            ),
            initialResolution(
              1,
              p.flatLines[1],
            ).resolveToIngredient('ing-onion', 'Onion', correction: true),
          ],
          header: _header(p),
          issuesByLine: null,
        ),
      );

      expect(await aliasOwners(), {
        'brown onion': 'ing-onion',
      }, reason: 'the name is kept; the decision is not');
      // Refusing to LEARN is never refusing to save: the line still commits
      // against the row he picked, and the review says nothing either way.
      final lines = await db.getAll(
        'SELECT li.ingredient_id FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY li.sort_order',
        [recipeId],
      );
      expect(lines.map((r) => r['ingredient_id']), ['ing-pasta', 'ing-onion']);
    });

    test('a taken name does not stop the corrections beside it', () async {
      await _seedIngredient(db, 'ing-extra', 'Extra Firm Tofu');
      await _seedIngredient(db, 'ing-super', 'Super Firm Tofu');
      const p = ReconciliationPayload(
        title: 'Two Corrections',
        servingsBase: 2,
        groups: [
          ReconGroup(
            lines: [
              ReconLine(
                raw: RawLineItem(ingredientText: 'extra-firm tofu', qty: 200),
                band: MatchBand.none,
              ),
              ReconLine(
                raw: RawLineItem(ingredientText: 'brown onions', qty: 1),
                band: MatchBand.none,
              ),
            ],
          ),
        ],
      );
      await repo.commit(
        buildCommit(
          p,
          [
            initialResolution(0, p.flatLines[0]).resolveToIngredient(
              'ing-super',
              'Super Firm Tofu',
              correction: true,
            ),
            initialResolution(
              1,
              p.flatLines[1],
            ).resolveToIngredient('ing-onion', 'Onion', correction: true),
          ],
          header: _header(p),
          issuesByLine: null,
        ),
      );

      expect(await aliasOwners(), {'brown onion': 'ing-onion'});
    });
  });

  test('step line_index refs are remapped to real line_item_ids', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(
        c.payload,
        c.resolutions,
        header: _header(c.payload),
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

  group('a line the REVIEW minted', () {
    test('inserts like any other, in its section, at the end', () async {
      final c = resolvedCommit();
      var sections = addGroup(initialGroups(c.payload), id: 'g-new-0');
      final index = nextLineIndex(c.payload, sections);
      sections = addLineToGroup(sections, 'g-new-0', index);
      await _seedIngredient(db, 'ing-sugar', 'Granulated Sugar');

      final recipeId = await repo.commit(
        buildCommit(
          c.payload,
          [
            ...c.resolutions,
            LineResolution.added(
              lineIndex: index,
              name: 'Granulated Sugar',
              ingredientId: 'ing-sugar',
              quantity: 1,
              unit: 'tsp',
            ),
          ],
          header: _header(c.payload),
          issuesByLine: null,
          sections: sections,
        ),
      );

      final rows = await db.getAll(
        'SELECT g.name AS gname, li.ingredient_id, li.quantity, li.unit '
        'FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY g.sort_order, li.sort_order',
        [recipeId],
      );
      final minted = rows.last;
      expect(minted['ingredient_id'], 'ing-sugar');
      expect(minted['quantity'], 1);
      expect(minted['unit'], 'tsp');
      // The empty section the payload never had is the one it landed in.
      expect(minted['gname'], isNull);
      expect(rows, hasLength(5));
    });

    test('its minted index remaps to a real line_item_id, and every chip '
        'already written still points where it did', () async {
      final c = resolvedCommit();
      var sections = initialGroups(c.payload);
      final index = nextLineIndex(c.payload, sections);
      sections = addLineToGroup(sections, 'g0', index);
      await _seedIngredient(db, 'ing-sugar', 'Granulated Sugar');

      final commit = buildCommit(
        c.payload,
        [
          ...c.resolutions,
          LineResolution.added(
            lineIndex: index,
            name: 'Granulated Sugar',
            ingredientId: 'ing-sugar',
            quantity: 1,
            unit: 'tsp',
          ),
        ],
        header: _header(c.payload),
        issuesByLine: null,
        sections: sections,
        // The method chips the new line, at the index only the review knows.
        steps: [
          ...c.payload.steps,
          Step(
            tokens: [
              const TextToken(s: 'Finish with the '),
              RefToken(refs: [index], label: 'sugar'),
              const TextToken(s: '.'),
            ],
          ),
        ],
      );
      final recipeId = await repo.commit(commit);

      // In written order, which is the order buildCommit emitted: the four
      // payload lines, then the one the review minted at the end of g0.
      final lines = await db.getAll(
        'SELECT li.id FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY g.sort_order, li.sort_order',
        [recipeId],
      );
      final idAt = [for (final r in lines) r['id'] as String];
      final row = await db.getOptional(
        'SELECT steps FROM recipe WHERE id = ?',
        [recipeId],
      );
      final steps = jsonDecode(row!['steps'] as String) as List;
      final refs = [
        for (final step in steps)
          for (final t in (step as Map)['tokens'] as List)
            if ((t as Map)['t'] == 'ref') (t['refs'] as List).cast<String>(),
      ];
      // The original chips are untouched, and the minted line's chip resolves.
      expect(refs.first, [idAt[0]], reason: 'the onion chip is untouched');
      expect(refs.last, [idAt[4]], reason: 'the minted line is the fifth');
    });
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
        initialResolution(
          1,
          p.flatLines[1],
        ).resolveToIngredient('ing-mystery', 'Mystery Spice').drop(),
        initialResolution(
          2,
          p.flatLines[2],
        ).resolveToIngredient('ing-mystery', 'Mystery Spice'),
        initialResolution(
          3,
          p.flatLines[3],
        ).resolveToIngredient('ing-onion', 'Onion'),
      ];

      final recipeId = await repo.commit(
        buildCommit(p, resolutions, header: _header(p), issuesByLine: null),
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
        header: _header(c.payload),
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

  group('the unattended re-match seam', () {
    test('it sees ALIASES, not just the ingredient name', () async {
      // The learning loop absorbs a household's own phrasing as an alias. Until
      // now this seam searched `ingredient.match_text` alone, so everything it
      // taught us was invisible to the one caller that resolves without a
      // human. The vocab row here shares NO word with the candidate: only the
      // alias can bridge them.
      await _seedIngredient(db, 'ing-allium', 'Allium Sativum');
      await _seedAlias(db, 'ing-allium', 'garlic');

      final result = await repo.startImport(const ImportFromUrl('x'));
      final garlic = result.flatLines.firstWhere(
        (l) => l.raw.ingredientText == 'garlic cloves, sliced',
      );
      expect(garlic.candidates.single.ingredientId, 'ing-allium');
      // The RESOLVED row's own name replaces the canned one, so the chip the
      // user taps says what it will actually write.
      expect(garlic.candidates.single.canonicalName, 'Allium Sativum');
    });

    test('it ranks the candidates the way the PICKER ranks them — an alias the '
        'query IS beats a longer name the query merely prefixes', () async {
      // The divergence this seam used to carry: the SQL ordered by name
      // length, so the shorter canonical name won whatever the surfaces said.
      // "Parmesan" IS one row's alias (tier 0, an exact surface) and only
      // word-prefixes the other's name (tier 1) — the picker offers the alias
      // row first, and the commit must write the same one.
      await _seedIngredient(db, 'ing-parm', 'Parmesan cheese');
      await _seedIngredient(db, 'ing-grana', 'Aged Italian Hard Cheese');
      await _seedAlias(db, 'ing-grana', 'parmesan');

      final result = await repo.startImport(const ImportFromUrl('x'));
      final parm = result.flatLines.firstWhere(
        (l) => l.raw.ingredientText == 'Parmesan, grated',
      );
      expect(parm.candidates.single.ingredientId, 'ing-grana');
      expect(parm.candidates.single.canonicalName, 'Aged Italian Hard Cheese');

      // …which is the row the picker puts first, over the same vocabulary.
      final picker = SqliteIngredientRepository(db, householdId: 'h');
      final offered = await picker.search('Parmesan');
      expect(offered.rows.first.id, 'ing-grana');
    });

    test('it never guesses, even where the picker would', () async {
      // "Parmezan cheese" is ONE edit from the canned candidate "Parmesan", so
      // the picker offers it under a "did you mean" header. This seam commits
      // without a human looking, so it must refuse — ADR-0004 and the
      // never-invent invariant. Tier 2 is retrieval for a human to pick, never
      // a resolution.
      await _seedIngredient(db, 'ing-parmz', 'Parmezan cheese');

      final result = await repo.startImport(const ImportFromUrl('x'));
      final parm = result.flatLines.firstWhere(
        (l) => l.raw.ingredientText == 'Parmesan, grated',
      );
      expect(parm.band, MatchBand.none);
      expect(parm.candidates, isEmpty);

      // The same query, through the picker, DOES offer it — flagged a guess.
      final picker = SqliteIngredientRepository(db, householdId: 'h');
      final offered = await picker.search('Parmesan');
      expect(offered.rows.single.canonicalName, 'Parmezan cheese');
      expect(offered.guessed, isTrue);
    });
  });

  // --- Step 8.6 / D6: a review-linked line persists as a component ----------

  group('a linked line commits as a component', () {
    /// One aioli line offered a household recipe, plus one plain line beside
    /// it so the ordinary path is asserted in the same write.
    const linkedPayload = ReconciliationPayload(
      title: 'Sausage Sliders',
      servingsBase: 8,
      yieldRaw: 'MAKES: 8 SLIDERS',
      groups: [
        ReconGroup(
          lines: [
            ReconLine(
              raw: RawLineItem(
                ingredientText: 'Romesco Aioli (page 38)',
                qty: 0.25,
                unit: 'cup',
                rawAmount: '¼ cup',
                notes: 'to finish',
              ),
              band: MatchBand.none,
              recipeCandidates: [
                RecipeCandidate(
                  recipeId: 'r-aioli',
                  title: 'Romesco Aioli',
                  score: 1,
                ),
              ],
            ),
            ReconLine(
              raw: RawLineItem(
                ingredientText: 'onion, diced',
                qty: 1,
                unit: 'piece',
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

    Future<String> commitLinked({double? yieldQty, Unit? yieldUnit}) {
      const p = linkedPayload;
      final resolutions = [
        initialResolution(
          0,
          p.flatLines[0],
        ).linkToRecipe('r-aioli', 'Romesco Aioli'),
        initialResolution(1, p.flatLines[1]),
      ];
      return repo.commit(
        buildCommit(
          p,
          resolutions,
          header: _header(
            p,
            servingsBase: 8,
            yieldQty: yieldQty,
            yieldUnit: yieldUnit,
          ),
          issuesByLine: null,
        ),
      );
    }

    test('sub_recipe_id set, ingredient_id null, measure_id null — the XOR and '
        'its measure fence', () async {
      final recipeId = await commitLinked();
      final lines = await db.getAll(
        'SELECT li.* FROM recipe_line_item li '
        'JOIN ingredient_group g ON g.id = li.group_id '
        'WHERE g.recipe_id = ? ORDER BY li.sort_order',
        [recipeId],
      );
      expect(lines, hasLength(2));

      final component = lines.first;
      expect(component['sub_recipe_id'], 'r-aioli');
      expect(component['ingredient_id'], isNull);
      expect(component['measure_id'], isNull);
      // The printed amount is kept as printed — "¼ cup", not a batch guess.
      expect((component['quantity'] as num).toDouble(), 0.25);
      expect(component['unit'], 'cup');
      expect(component['note'], 'to finish');

      // The ordinary line beside it is untouched by any of this.
      final plain = lines.last;
      expect(plain['ingredient_id'], 'ing-onion');
      expect(plain['sub_recipe_id'], isNull);
    });

    test('the review MAKES row lands on the recipe row', () async {
      final recipeId = await commitLinked(yieldQty: 8, yieldUnit: pieces);
      final recipe = await db.get('SELECT * FROM recipe WHERE id = ?', [
        recipeId,
      ]);
      expect((recipe['yield_qty'] as num).toDouble(), 8);
      expect(recipe['yield_unit'], 'piece');
      // The review states ONE denomination; the second is the editor's.
      expect(recipe['yield_qty_2'], isNull);
      expect(recipe['yield_unit_2'], isNull);
    });

    test(
      'an unstated yield writes nulls — a yield-less recipe still saves',
      () {
        return commitLinked().then((recipeId) async {
          final recipe = await db.get('SELECT * FROM recipe WHERE id = ?', [
            recipeId,
          ]);
          expect(recipe['yield_qty'], isNull);
          expect(recipe['yield_unit'], isNull);
        });
      },
    );

    test('the committed component reloads as a component line', () async {
      // Seeded so the join resolves: the target is an ordinary household
      // recipe, which is the only thing a link may ever point at.
      await db.execute(
        'INSERT INTO recipe (id, household_id, title, servings_base, '
        'yield_qty, yield_unit, created_at, updated_at) '
        "VALUES ('r-aioli', 'h', 'Romesco Aioli', 4, 1, 'cup', ?, ?)",
        [
          DateTime.now().toUtc().toIso8601String(),
          DateTime.now().toUtc().toIso8601String(),
        ],
      );
      final recipeId = await commitLinked();
      final recipe = await SqliteRecipeRepository(
        db,
        householdId: 'h',
      ).watchRecipe(recipeId).first;
      final line = recipe!.groups.single.items.first;
      expect(line.isComponent, isTrue);
      expect(line.subRecipe?.title, 'Romesco Aioli');
      // And the batch math the whole step exists for now answers: ¼ cup of a
      // recipe that makes 1 cup is a quarter of a batch.
      expect(
        line.componentAmount,
        const ResolvedComponentAmount(0.25, against: (qty: 1, unit: cup)),
      );
    });
  });

  group('the header at review', () {
    test('commit writes every header column the editor writes: title, both '
        'yields, times, shelf life, filing', () async {
      await db.execute(
        'INSERT INTO book (id, household_id, name, sort_order, created_at, '
        "updated_at) VALUES ('b-mine', 'h', 'Weeknights', 0, '', '')",
      );
      await db.execute(
        'INSERT INTO book_section (id, household_id, book_id, name, '
        'sort_order, created_at, updated_at) '
        "VALUES ('s-quick', 'h', 'b-mine', 'Quick', 0, '', '')",
      );
      final c = resolvedCommit();
      const header = Recipe(
        id: 'draft',
        title: '  Test Recipe, ours  ',
        servingsBase: 3,
        yieldQty: 250,
        yieldUnit: g,
        yieldQty2: 16,
        yieldUnit2: tbsp,
        cookTimeSeconds: 2100,
        totalTimeSeconds: 4200,
        keepsForDays: 4,
        freezable: true,
        freezerDays: 30,
        bookId: 'b-mine',
        sectionId: 's-quick',
      );
      final recipeId = await repo.commit(
        buildCommit(
          c.payload,
          c.resolutions,
          header: header,
          issuesByLine: null,
        ),
      );

      final row = await db.get('SELECT * FROM recipe WHERE id = ?', [recipeId]);
      expect(row['title'], 'Test Recipe, ours');
      expect((row['servings_base'] as num).toDouble(), 3);
      expect((row['yield_qty'] as num).toDouble(), 250);
      expect(row['yield_unit'], 'g');
      expect((row['yield_qty_2'] as num).toDouble(), 16);
      expect(row['yield_unit_2'], 'tbsp');
      expect(row['cook_time_seconds'], 2100);
      expect(row['total_time_seconds'], 4200);
      expect(row['keeps_for_days'], 4);
      expect(row['freezable'], 1);
      expect(row['freezer_days'], 30);
      expect(row['book_id'], 'b-mine');
      expect(row['section_id'], 's-quick');

      // And it opens in the editor as the same aggregate — the recipe
      // repository reads back what the import wrote, column for column.
      final loaded = (await SqliteRecipeRepository(
        db,
        householdId: 'h',
      ).watchRecipe(recipeId).first)!;
      expect(loaded.title, 'Test Recipe, ours');
      expect(loaded.yields, [(qty: 250.0, unit: g), (qty: 16.0, unit: tbsp)]);
      expect((loaded.cookTimeSeconds, loaded.totalTimeSeconds), (2100, 4200));
      expect(
        (loaded.keepsForDays, loaded.freezable, loaded.freezerDays),
        (4, true, 30),
      );
      expect((loaded.bookName, loaded.sectionName), ('Weeknights', 'Quick'));
    });

    test('a header that states nothing writes nulls and an unfrozen row — and '
        'still files into the default book', () async {
      final c = resolvedCommit();
      final recipeId = await repo.commit(
        buildCommit(
          c.payload,
          c.resolutions,
          header: _header(c.payload),
          issuesByLine: null,
        ),
      );
      final row = await db.get('SELECT * FROM recipe WHERE id = ?', [recipeId]);
      expect(row['keeps_for_days'], isNull);
      expect(row['freezable'], 0);
      expect(row['freezer_days'], isNull);
      expect(row['section_id'], isNull);
      expect(row['yield_qty_2'], isNull);
      expect(row['book_id'], isNotNull);
    });
  });
}

typedef CommitPayloadResult = ({
  ReconciliationPayload payload,
  List<LineResolution> resolutions,
});
