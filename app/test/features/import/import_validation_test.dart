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

/// The owner's line: "1 clove garlic", auto-matched to the cloud garlic row.
ReconciliationPayload _clovePayload() => const ReconciliationPayload(
  title: 'Kale salad',
  servingsBase: 2,
  groups: [
    ReconGroup(
      lines: [
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'garlic clove, crushed',
            qty: 1,
            unit: 'clove',
            rawAmount: '1 clove',
          ),
          band: MatchBand.auto,
          candidates: [
            MatchCandidate(
              ingredientId: 'i-garlic',
              canonicalName: 'Garlic',
              score: 0.98,
            ),
          ],
        ),
        // Scenario 4's shape: nothing matches, the user creates a stub, and
        // the source printed an imprecise word (plan 0020 J3b).
        ReconLine(
          raw: RawLineItem(
            ingredientText: 'chilli flakes',
            unit: 'pinch',
            rawAmount: 'a pinch of',
          ),
          band: MatchBand.none,
        ),
      ],
    ),
  ],
);

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

  test("a measure-word unit validates against the ingredient's real measures "
      '— it is not flagged "Pick a supported unit" (J2)', () async {
    final container = await reviewing();
    final byLine = await container.read(importValidationProvider.future);

    expect(byLine[0]!.issues, isEmpty);
    expect(byLine[0]!.isClean, isTrue);
  });

  test("the measure is offered as a chip, and the line's own parsed unit "
      'leads the ranking (J2)', () async {
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

  test('J3b: a printed imprecise word on a freshly created row validates — '
      'the Save gate cannot lock on a unit the editor never offers', () async {
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
