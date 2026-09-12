/// The import review's per-line validation against the REAL local schema —
/// the cloud-shaped row the owner's Pixel field test flagged (plan 0020 J2).
///
/// The fakes elsewhere hand measures back as a `Stream.value`, which resolves
/// before anything can dispose it. PowerSync's `watch` does not, and routing
/// the review's measure loads through N autoDispose stream providers meant a
/// provider disposed mid-load completed with a `StateError` that the loader
/// swallowed into "no measures" — so a line reading "1 clove" of a garlic row
/// that carries a `clove` measure was flagged "Pick a supported unit", with
/// the measure missing from its chip row entirely.
library;

import 'dart:io';

import 'package:ansi/core/sync/database.dart';
import 'package:ansi/core/sync/session.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:powersync/powersync.dart';

import '../../helpers/fake_import_repository.dart';
import '../../helpers/test_db.dart';
import '_fixtures.dart';

/// The owner's line: "1 clove garlic", auto-matched to the cloud garlic row,
/// beside scenario 4's shape — nothing matches, the user creates a stub, and
/// the source printed an imprecise word.
ReconciliationPayload _clovePayload() => reconPayload(title: 'Kale salad', [
  reconLine(
    'garlic clove, crushed',
    qty: 1,
    unit: 'clove',
    rawAmount: '1 clove',
    ingredientId: 'i-garlic',
    canonicalName: 'Garlic',
    score: 0.98,
  ),
  reconLine(
    'chilli flakes',
    unit: 'pinch',
    rawAmount: 'a pinch of',
    band: MatchBand.none,
  ),
]);

void main() {
  late PowerSyncDatabase db;
  late Directory dir;

  setUp(() async {
    (db, dir) = await openTestDb();
    // Exactly the shape of the owner's synced row: count default, an explicit
    // allowed list that names no measure (measures never live there), per-100 g
    // macros and no density.
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, category, '
      'default_unit, macros_basis, allowed_units, status, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'i-garlic',
        'h',
        'Garlic',
        'produce',
        'piece',
        'g',
        '["piece","g"]',
        'complete',
        '2026-01-01',
        '2026-01-01',
      ],
    );
    await db.execute(
      'INSERT INTO ingredient_measure (id, household_id, ingredient_id, label, '
      'basis_amount, sort_order, source, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'm-clove',
        'h',
        'i-garlic',
        'clove',
        3,
        0,
        'seed',
        '2026-01-01',
        '2026-01-01',
      ],
    );
  });

  tearDown(() => closeTestDb(db, dir));

  Future<ProviderContainer> reviewing() async {
    final container = ProviderContainer(
      overrides: [
        powerSyncDatabaseProvider.overrideWithValue(db),
        currentHouseholdIdProvider.overrideWithValue('h'),
        importRepositoryProvider.overrideWithValue(
          FakeImportRepo(_clovePayload()),
        ),
      ],
    );
    addTearDown(container.dispose);
    // The review screen holds the controller; keep the autoDispose one alive.
    final sub = container.listen(importControllerProvider, (_, _) {});
    addTearDown(sub.close);
    await container
        .read(importControllerProvider.notifier)
        .startImport(const ImportFromUrl('https://example.test/kale'));
    return container;
  }

  // Plan 0040 A-D2/A-D3: the review is the other moment a wrong food is cheap
  // to catch, and it costs no extra read to say so — the row is already in
  // hand from the one vocab query this provider makes.
  Future<void> fillGarlicFromUsda({required bool edited}) {
    final flag = edited ? 1 : 0;
    return db.execute(
      'UPDATE ingredient SET source = ?, source_label = ?, source_score = ?, '
      'source_edited = ? WHERE id = ?',
      ['usda_fdc:11215', 'Garlic, raw', 0.94, flag, 'i-garlic'],
    );
  }

  test('a matched row’s USDA food rides on the validation; an unmatched line '
      'has no row to name', () async {
    await fillGarlicFromUsda(edited: false);
    final container = await reviewing();
    final byLine = await container.read(importValidationProvider.future);

    expect(byLine[0]!.sourceLine, 'usda · Garlic, raw');
    expect(byLine[1]!.sourceLine, isNull);
  });

  test('an edited row leads with EDITED', () async {
    await fillGarlicFromUsda(edited: true);
    final container = await reviewing();
    final byLine = await container.read(importValidationProvider.future);

    expect(byLine[0]!.sourceLine, 'edited · usda · Garlic, raw');
  });

  test(
    'a row nothing looked up says nothing — the fixture row as it stands',
    () async {
      final container = await reviewing();
      final byLine = await container.read(importValidationProvider.future);

      expect(byLine[0]!.sourceLine, isNull);
    },
  );

  test('a '
      "measure-word unit validates against the ingredient's real measures — it "
      'is not flagged "Pick a supported unit"', () async {
    final container = await reviewing();
    final byLine = await container.read(importValidationProvider.future);

    expect(byLine[0]!.issues, isEmpty);
    expect(byLine[0]!.isClean, isTrue);
  });

  test('the '
      "measure is offered as a chip, and the line's own parsed unit leads the "
      'ranking', () async {
    final container = await reviewing();
    final byLine = await container.read(importValidationProvider.future);
    final tokens = byLine[0]!.unitChoices.map((c) => c.token).toList();

    expect(tokens, contains('clove'));
    final ranked = rankedUnitChips(
      byLine[0]!.unitChoices,
      parsedUnit: 'clove',
    ).map((c) => c.token).toList();
    // The screenshot read "g piece pinch dash handful (+1 more)" — the exact
    // output of an EMPTY measure list, with the printed unit nowhere.
    expect(ranked.first, 'clove');
    expect(ranked.take(kVisibleUnitChips), contains('clove'));
  });

  test('validation survives a recompute — changing the unit re-reads the '
      'measures rather than degrading to none', () async {
    final container = await reviewing();
    await container.read(importValidationProvider.future);

    container
        .read(importControllerProvider.notifier)
        .updateResolution(0, (r) => r.pickUnit('g'));
    final after = await container.read(importValidationProvider.future);
    expect(after[0]!.issues, isEmpty);
    expect(after[0]!.unitChoices.map((c) => c.token), contains('clove'));
  });

  // --- A match at a row that was RETIRED between match and review ----------
  //
  // The de-duplication's own shape: two rows for one name, one retired. The
  // server matched the id that is now the tombstone, `byIds` hands back only
  // live rows, and before this the line read as DONE (no ingredient, so no
  // unit to fault) and wrote the dead id.

  group('a match at a row retired since the server answered', () {
    /// The live twin a de-duplication leaves behind — same name, same shape,
    /// its own `clove` measure, so a pick lands on something the line's
    /// printed unit is admissible on.
    Future<void> insertLiveTwin() async {
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, category, '
        'default_unit, macros_basis, allowed_units, status, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          'i-garlic-live',
          'h',
          'Garlic',
          'produce',
          'piece',
          'g',
          '["piece","g"]',
          'complete',
          '2026-01-01',
          '2026-01-01',
        ],
      );
      await db.execute(
        'INSERT INTO ingredient_measure (id, household_id, ingredient_id, '
        'label, basis_amount, sort_order, source, created_at, updated_at) '
        "VALUES ('m-clove-live', 'h', 'i-garlic-live', 'clove', 3, 0, 'seed', "
        "'2026-01-01', '2026-01-01')",
      );
    }

    Future<void> retireGarlic() => db.execute(
      "UPDATE ingredient SET deleted_at = '2026-02-01T00:00:00Z' "
      "WHERE id = 'i-garlic'",
    );

    /// The review with its OTHER line already answered, so the only thing
    /// standing between this import and Save is the retired match.
    Future<ProviderContainer> reviewingChilliResolved() async {
      final container = await reviewing();
      await db.execute(
        'INSERT INTO ingredient (id, household_id, canonical_name, '
        'default_unit, status, source, created_at, updated_at) VALUES (?, ?, '
        "?, 'g', 'stub', 'manual', ?, ?)",
        ['ing-chilli', 'h', 'Chilli flakes', '2026-01-01', '2026-01-01'],
      );
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            1,
            (r) => r.resolveToIngredient('ing-chilli', 'Chilli flakes'),
          );
      return container;
    }

    Map<int, List<LineIssue>> issuesOf(Map<int, LineValidation> byLine) => {
      for (final e in byLine.entries) e.key: e.value.issues,
    };

    test('reads as unmatched — there is nothing to name, and nothing to '
        'validate a unit against', () async {
      final container = await reviewingChilliResolved();
      await retireGarlic();
      final byLine = await container.read(importValidationProvider.future);

      expect(byLine[0]!.issues, [LineIssue.unmatched]);
      expect(byLine[0]!.unitChoices, isEmpty);
      expect(byLine[0]!.sourceLine, isNull);
      // Which is what holds Save: the button and the gate read this map.
      expect(allLinesValid(issuesOf(byLine)), isFalse);
    });

    test('the save path refuses it as well — the dead id never reaches '
        'PowerSync', () async {
      final container = await reviewingChilliResolved();
      await retireGarlic();
      final byLine = await container.read(importValidationProvider.future);
      final notifier = container.read(importControllerProvider.notifier);

      // Structurally the line still holds an id, so `canCommit` is true and
      // the refusal has to come from the issues map — which is the whole
      // reason `buildCommit` is handed the same map the button reads.
      expect(
        (container.read(importControllerProvider) as ImportReconciling)
            .canCommit,
        isTrue,
      );
      expect(
        () => notifier.commit(issuesByLine: issuesOf(byLine)),
        throwsStateError,
      );
    });

    test('picking the live twin clears it, and the import saves', () async {
      final container = await reviewingChilliResolved();
      await insertLiveTwin();
      await retireGarlic();
      await container.read(importValidationProvider.future);

      // What the card's picker does with the row the de-duplication kept.
      container
          .read(importControllerProvider.notifier)
          .updateResolution(
            0,
            (r) => r.resolveToIngredient('i-garlic-live', 'Garlic'),
          );
      final byLine = await container.read(importValidationProvider.future);

      expect(byLine[0]!.issues, isEmpty);
      expect(allLinesValid(issuesOf(byLine)), isTrue);
      final id = await container
          .read(importControllerProvider.notifier)
          .commit(issuesByLine: issuesOf(byLine));
      expect(id, isNotNull);
    });
  });

  test('a printed imprecise word on a freshly created row validates — the Save '
      'gate cannot lock on a unit the editor never offers', () async {
    final container = await reviewing();
    // The user takes "create new" on the no-match line, exactly as scenario 4
    // does: the sheet writes a plain `g` stub with NO category (the form is
    // where a category arrives), so the J3 category gate earns it no
    // imprecise word at all — and the line resolves to that row.
    await db.execute(
      'INSERT INTO ingredient (id, household_id, canonical_name, default_unit, '
      "status, source, created_at, updated_at) VALUES (?, ?, ?, 'g', 'stub', "
      "'manual', ?, ?)",
      ['ing-chilli', 'h', 'Chilli flakes', '2026-01-01', '2026-01-01'],
    );
    container
        .read(importControllerProvider.notifier)
        .updateResolution(
          1,
          (r) => r.resolveToIngredient('ing-chilli', 'Chilli flakes'),
        );

    final byLine = await container.read(importValidationProvider.future);
    expect(
      byLine[1]!.issues,
      isEmpty,
      reason: 'a source-printed "pinch" must stay admissible — never-invent',
    );
    // And the whole import is savable, which is what scenario 4 asserts.
    expect(
      allLinesValid({for (final e in byLine.entries) e.key: e.value.issues}),
      isTrue,
    );
    // The word is offered too, so the amount sheet can render the line.
    expect(byLine[1]!.unitChoices.map((c) => c.token), contains('pinch'));
  });
}
