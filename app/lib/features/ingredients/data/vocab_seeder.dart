/// One-shot loader that populates the local (unsynced) ingredient vocabulary
/// from the bundled `assets/seed/vocab.jsonl`.
///
/// Step 2 runs offline, so the vocab the picker searches can't arrive via sync
/// yet — we bundle the seed source of truth and load it on first run.
/// Idempotent: no-ops once the local `ingredient` table has rows. Step 7
/// replaces it with real sync and drops the loader.
///
/// The bundle carries names/categories/units/aliases but not USDA-resolved
/// macros/density (a server-seed concern), so every row loads as `stub` — honest
/// (invariant 3) and fine for step 2, which does no macro math.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/dev_household.dart';

const _asset = 'assets/seed/vocab.jsonl';
const _uuid = Uuid();

class VocabSeeder {
  const VocabSeeder(this._db);

  final SqliteConnection _db;

  /// Loads the vocab if the local table is empty; otherwise returns at once.
  Future<void> ensureSeeded() async {
    final existing = await _db.get('SELECT count(*) AS c FROM ingredient');
    if ((existing['c'] as int) > 0) return;

    final raw = await rootBundle.loadString(_asset);
    final lines = const LineSplitter().convert(raw)
      ..removeWhere((l) => l.trim().isEmpty);

    await _db.writeTransaction((tx) async {
      for (final line in lines) {
        final row = jsonDecode(line) as Map<String, dynamic>;
        final name = row['canonical_name'] as String;
        final id = _uuid.v4();

        await tx.execute(
          'INSERT INTO ingredient (id, household_id, canonical_name, category, '
          'default_unit, density_g_per_ml, status, source, match_text) '
          'VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?)',
          [
            id,
            kDevHouseholdId,
            name,
            row['category'],
            row['default_unit'],
            'stub',
            'seed',
            name.toLowerCase(),
          ],
        );

        for (final alias in (row['aliases'] as List? ?? const [])) {
          await tx.execute(
            'INSERT INTO ingredient_alias (id, ingredient_id, alias_text, '
            'match_text) VALUES (?, ?, ?, ?)',
            [_uuid.v4(), id, alias, (alias as String).toLowerCase()],
          );
        }
      }
    });
  }
}
