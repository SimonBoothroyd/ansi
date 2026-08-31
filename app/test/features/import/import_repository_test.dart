import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/import/data/import_repository_impl.dart';
import 'package:mise/features/import/domain/import_repository.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
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
      buildCommit(c.payload, c.resolutions, servingsBase: 3),
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

  test('identical no-match lines coalesce onto one created stub', () async {
    final c = resolvedCommit();
    await repo.commit(buildCommit(c.payload, c.resolutions, servingsBase: 2));

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
    await repo.commit(buildCommit(c.payload, c.resolutions, servingsBase: 2));

    final aliases = await db.getAll(
      "SELECT * FROM ingredient_alias WHERE source = 'import_correction'",
    );
    expect(aliases, hasLength(1));
    expect(aliases.single['alias_text'], 'yellow onion');
    expect(aliases.single['ingredient_id'], 'ing-onion');
  });

  test('step line_index refs are remapped to real line_item_ids', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(c.payload, c.resolutions, servingsBase: 2),
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

  test('the committed recipe reloads with tokenized method steps', () async {
    final c = resolvedCommit();
    final recipeId = await repo.commit(
      buildCommit(c.payload, c.resolutions, servingsBase: 2),
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

  test(
    'a candidate resolves by token match, not only exact name (so a '
    'suggestion still surfaces when the vocab name differs)',
    () async {
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
    },
  );
}

typedef CommitPayloadResult = ({
  ReconciliationPayload payload,
  List<LineResolution> resolutions,
});
