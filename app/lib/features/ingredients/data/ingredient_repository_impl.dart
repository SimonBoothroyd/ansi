/// [IngredientRepository] over the local SQLite vocab (server-synced since
/// step 7 — `ensure_onboarded` clones the household's starter vocab).
///
/// Search is [searchRank]'s three tiers, split across SQL and Dart because
/// each half is better at one of them:
///
/// * **SQL selects, Dart ranks.** The word-boundary `LIKE` pass IS tiers 0 and
///   1 expressed as SQL, and it is the index-friendly way to ask the question.
///   What comes back is then ordered by [searchRank] alone, so the picker's
///   ordering is the shared rule rather than a `length(canonical_name)` proxy
///   that happened to approximate it. Each token is tried raw AND singularized
///   ([matchTextForms]), because `match_text` itself is singularized — that is
///   what lets "almonds" find "Almonds".
/// * **Tier 2 is Dart's.** When the SQL pass finds nothing at all, every live
///   row is scored in Dart and the guarded typo tier answers — or honestly
///   returns nothing. That result is flagged `IngredientMatches.guessed` so
///   the picker can label the band: the phone offers guesses to a human, it
///   never resolves on one (ADR-0004).
library;

import 'dart:convert';

import 'package:sqlite3/common.dart' show Row;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/search/search_query.dart';
import '../../../core/search/search_rank.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';

const _uuid = Uuid();

/// The volume-unit names the chip row refuses as measure labels
/// ([isVolumeUnitLabel] — ids, display labels, and their simple s plurals),
/// lowercased for the SQL filter below. Static catalog values, no user input.
final _volumeLabelList = [
  for (final u in kAllUnits)
    if (u.family == UnitFamily.volume)
      for (final name in {u.id.toLowerCase(), u.label.toLowerCase()}) ...[
        name,
        '${name}s',
      ],
].map((l) => "'$l'").join(', ');

/// Distinct live labels, matching the merge-on-read view of the measures
/// (duplicate labels collapse to one chip, so they count once here too) and
/// the chip row's volume-label exclusion — the hint counts what is actually
/// offered, not rows the picker hides.
final _measureCount =
    '(SELECT COUNT(DISTINCT m.label) FROM ingredient_measure m '
    'WHERE m.ingredient_id = i.id AND m.deleted_at IS NULL '
    'AND LOWER(TRIM(m.label)) NOT IN ($_volumeLabelList)) AS measure_count';

/// A row's live aliases' `match_text`, newline-separated so each stays a
/// phrase of its own — the rule's tier 0 asks whether the query IS an alias,
/// which a space-joined blob could never answer. `match_text` cannot contain a
/// newline (the normalizer collapses all whitespace), so the split is exact.
/// `char(10)`, not a quoted literal: SQLite reads `"x"` as an identifier first
/// and only falls back to a string as a legacy quirk that `SQLITE_DQS=0`
/// builds disable outright.
const _aliasText =
    '(SELECT GROUP_CONCAT(a.match_text, char(10)) FROM ingredient_alias a '
    'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL) AS alias_text';

/// The `macros` column's jsonb, or null when there are none — null (not `{}`,
/// and never four zeros) is how an absent panel is stored, on the create path
/// and the edit path alike (invariant 3).
String? _macrosJson(Macros? macros) => macros == null
    ? null
    : jsonEncode({
        'kcal': macros.kcal,
        'protein': macros.protein,
        'carb': macros.carb,
        'fat': macros.fat,
      });

class SqliteIngredientRepository implements IngredientRepository {
  const SqliteIngredientRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes (the add-new stub path).
  final String _householdId;

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async {
    // Normalization also strips `%`/`_`, so nothing user-typed can act as a
    // LIKE wildcard below.
    final tokens = searchTokens(query);

    if (tokens.isEmpty) {
      final rows = await _db.getAll(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.deleted_at IS NULL '
        'ORDER BY i.canonical_name LIMIT ?',
        [limit],
      );
      return (rows: rows.map(_toIngredient).toList(), guessed: false);
    }

    // Token-subset match: EVERY query token must be a word-prefix of the
    // ingredient's `match_text` OR one of its live aliases (order-independent,
    // so "canned tomatoes" finds "Canned Whole Tomatoes"). Each token is a
    // word-boundary LIKE (`tok%` = leading word, `% tok%` = any later word).
    //
    // A token matches in its RAW form or its SINGULAR one ([matchTextForms]):
    // `match_text` is written by the phrase normalizer, which singularizes
    // ("Almonds" → `almond`), while the query is deliberately only
    // character-normalized. Without the singular branch `'almond'.startsWith(
    // 'almonds')` is false, so a one-word plural query would hit nothing here.
    // Both forms are still wildcard-free, so `%`/`_` stay inert.
    //
    // This pass SELECTS; it does not rank. `searchRank` does the ordering
    // below, over the same rows, so the picker and the two recipe pickers
    // cannot drift apart on what "best match" means.
    final where = StringBuffer('i.deleted_at IS NULL');
    final params = <Object?>[];
    for (final tok in tokens) {
      final patterns = [
        for (final form in matchTextForms(tok)) ...['$form%', '% $form%'],
      ];
      final own = patterns.map((_) => 'i.match_text LIKE ?').join(' OR ');
      final alias = patterns.map((_) => 'a.match_text LIKE ?').join(' OR ');
      where.write(
        ' AND ($own '
        'OR EXISTS (SELECT 1 FROM ingredient_alias a '
        'WHERE a.ingredient_id = i.id AND a.deleted_at IS NULL '
        'AND ($alias)))',
      );
      params.addAll([...patterns, ...patterns]);
    }
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, $_aliasText FROM ingredient i '
      'WHERE $where '
      // A stable page, then ranked in Dart. `length(canonical_name)` is only
      // the tie-break `searchRank` itself falls back on, so the page the LIMIT
      // keeps and the order it ends up in agree.
      'ORDER BY length(i.canonical_name), i.canonical_name '
      'LIMIT ?',
      [...params, limit],
    );
    if (rows.isNotEmpty) {
      return (rows: _rank(query, rows, limit: limit), guessed: false);
    }

    // Nothing was spelled right. Score every live row instead — the guarded
    // typo tier, which may still answer with nothing, and that emptiness is an
    // honest answer ("no match for 'tfu'"), not a bug.
    return _typoSearch(query, limit: limit);
  }

  /// The tier-2 pass: scores every live ingredient with [searchRank] and
  /// returns what clears the guards, best first. Runs only when the SQL pass
  /// found nothing, so the common path never pays for it.
  ///
  /// A hit here is normally a guess, and the result says so. It is not always:
  /// the SQL pass searches `match_text` only, and the phrase normalizer eats
  /// any name word that happens to be a measure ("Jars", "Blocks"), while
  /// [searchRank] also sees the row's raw name. A row rescued that way is a
  /// genuine prefix hit, so the band is keyed on the best tier found rather
  /// than on which pass produced it.
  Future<IngredientMatches> _typoSearch(
    String query, {
    required int limit,
  }) async {
    // No LIMIT: a cap would silently stop typo-tolerance working for whatever
    // fell off the end as the household's vocab grew, and this pass only runs
    // when the SQL search already found nothing. The stated bound (and it is a
    // bound, not an accident): correct to roughly 2 000 rows on a phone; past
    // that it needs an index, and that is a tracker row.
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, $_aliasText FROM ingredient i '
      'WHERE i.deleted_at IS NULL ORDER BY i.canonical_name',
    );
    final ranked = _rankHits(query, rows);
    if (ranked.isEmpty) return (rows: const <Ingredient>[], guessed: false);
    return (
      rows: [for (final r in ranked.take(limit)) r.ingredient],
      guessed: ranked.first.hit.tier == SearchTier.typo,
    );
  }

  /// [rows] in [searchRank] order, capped at [limit].
  List<Ingredient> _rank(String query, List<Row> rows, {required int limit}) =>
      [for (final r in _rankHits(query, rows).take(limit)) r.ingredient];

  /// [rows] scored and ordered by the shared rule: the tier decides first (a
  /// guess never outranks a spelling), then the score, then the shorter name,
  /// then the name.
  List<({SearchHit hit, Ingredient ingredient})> _rankHits(
    String query,
    List<Row> rows,
  ) {
    final scored = <({SearchHit hit, Ingredient ingredient})>[];
    for (final r in rows) {
      final hit = searchRank(query, _surfaces(r));
      if (hit == null) continue;
      scored.add((hit: hit, ingredient: _toIngredient(r)));
    }
    scored.sort((a, b) {
      final byTier = a.hit.tier.index.compareTo(b.hit.tier.index);
      if (byTier != 0) return byTier;
      final byScore = b.hit.score.compareTo(a.hit.score);
      if (byScore != 0) return byScore;
      final byLength = a.ingredient.canonicalName.length.compareTo(
        b.ingredient.canonicalName.length,
      );
      if (byLength != 0) return byLength;
      return a.ingredient.canonicalName.compareTo(b.ingredient.canonicalName);
    });
    return scored;
  }

  /// One row's searchable surface: its `match_text`, each live alias's
  /// `match_text`, and the character-normalized raw name (which carries the
  /// words the phrase normalizer strips).
  List<String> _surfaces(Row r) => [
    (r['match_text'] as String?) ?? '',
    ...((r['alias_text'] as String?) ?? '').split('\n'),
    normalizeSearchQuery(r['canonical_name'] as String),
  ];

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async {
    // "Used" = referenced by a live recipe line or a manual shopping top-up;
    // the newest reference wins. Mirrors what a cook actually reaches for.
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount, MAX(u.used_at) AS last_used '
      'FROM ingredient i '
      'JOIN ( '
      'SELECT li.ingredient_id AS ingredient_id, li.created_at AS used_at '
      'FROM recipe_line_item li WHERE li.deleted_at IS NULL '
      'UNION ALL '
      'SELECT e.ingredient_id, c.created_at '
      'FROM shopping_list_contribution c '
      'JOIN shopping_list_entry e ON e.id = c.entry_id '
      'WHERE c.deleted_at IS NULL AND e.deleted_at IS NULL '
      'AND e.ingredient_id IS NOT NULL '
      ') u ON u.ingredient_id = i.id '
      'WHERE i.deleted_at IS NULL '
      'GROUP BY i.id ORDER BY last_used DESC LIMIT ?',
      [limit],
    );
    return rows.map(_toIngredient).toList();
  }

  @override
  Future<Ingredient?> byId(String id) async {
    final row = await _db.getOptional(
      'SELECT i.*, $_measureCount FROM ingredient i '
      'WHERE i.id = ? AND i.deleted_at IS NULL',
      [id],
    );
    return row == null ? null : _toIngredient(row);
  }

  @override
  Stream<Ingredient?> watchIngredient(String id) => _db
      .watch(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        parameters: [id],
      )
      .map((rows) => rows.isEmpty ? null : _toIngredient(rows.first));

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async {
    if (ids.isEmpty) return const {};
    // Ids are uuids we minted or synced, never user text; they still ride as
    // bound parameters rather than being interpolated into the SQL.
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT i.*, $_measureCount FROM ingredient i '
      'WHERE i.deleted_at IS NULL AND i.id IN ($placeholders)',
      ids.toList(),
    );
    return {for (final r in rows) r['id'] as String: _toIngredient(r)};
  }

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async {
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(gPerMl > 0)) {
      throw ArgumentError.value(gPerMl, 'gPerMl', 'must be a positive number');
    }
    // Read-modify-write: the allowed set written back is derived from the row
    // as it is read, so the read and the write must be one transaction — a
    // concurrent density/allowed-units write between them would be clobbered.
    // This is the repo's only such pair; every other write is self-contained.
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      // Extend the explicit list with what this density unlocks, in the same
      // write (see the interface doc). A row still on the derived fallback is
      // materialized first, so the extension has something explicit to join.
      final unlocked = {
        ...current.allowedUnits ?? defaultAllowedUnitSet(current),
        ...densityUnlockedUnits(current),
      };
      final edited =
          isLookupFilled(current.source) && gPerMl != current.densityGPerMl
          ? 1
          : null;
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = ?, allowed_units = ?, '
        // The quantity sheet's density entry is a human write that changes a
        // number, so it flags a lookup-filled row exactly as the form's Save
        // does (0034) — the flag is a fact about the row, not about which
        // screen you were standing on.
        'source_edited = COALESCE(?, source_edited), updated_at = ? '
        'WHERE id = ?',
        [
          gPerMl,
          jsonEncode([for (final u in unlocked) u.id]),
          edited,
          now,
          ingredientId,
        ],
      );
      return true;
    });
    if (!updated) return null;
    return byId(ingredientId);
  }

  @override
  Future<Ingredient?> clearDensity(String ingredientId) async {
    // Read-modify-write for the same reason [setDensity] is: the list written
    // back is derived from the row as it is read.
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      if (current.densityGPerMl == null) return true; // nothing to delete
      final edited = isLookupFilled(current.source) ? 1 : null;
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = NULL, allowed_units = ?, '
        // Deleting a lookup's density is as much an override of its numbers as
        // typing a different one (0034). Not to be confused with
        // [declineUsdaPrefill], which also clears a density but is the person
        // rejecting the match outright — that row stops being a fill at all.
        'source_edited = COALESCE(?, source_edited), updated_at = ? '
        'WHERE id = ?',
        [
          jsonEncode([for (final u in _strippedOfDensity(current)) u.id]),
          edited,
          now,
          ingredientId,
        ],
      );
      return true;
    });
    if (!updated) return null;
    return byId(ingredientId);
  }

  /// D4b: the admission list as it reads once [current]'s density is gone —
  /// the cross-family units go with the number they were derived from. The
  /// basis family and the default unit's family survive (see
  /// [densityStrippedUnits]); curated units outside the derived rules are
  /// untouched. Read by [clearDensity] and [declineUsdaPrefill], which are
  /// the two places a density is ever deleted.
  static Set<Unit> _strippedOfDensity(Ingredient current) =>
      {...current.allowedUnits ?? defaultAllowedUnitSet(current)}
        ..removeAll(densityStrippedUnits(current));

  @override
  Future<Ingredient?> declineUsdaPrefill(String ingredientId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final declined = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      // Only a row the prefill still authors: anything else is a human's.
      if (!isUsdaPrefilled(current.source)) return false;
      // One statement: the density strip (the clearDensity rule, D4b), the
      // macros, the stamp, and the status — a row with no macros is a stub
      // (D5). The label stays: the form names what was refused.
      // `source_edited` goes back to 0 with them (0034): the flag says "the
      // numbers on this row are no longer the source's", and after a decline
      // there are no numbers and no fill — there is nothing left to override,
      // so `true` would be a claim about a state that no longer exists. The
      // two doors themselves are untouched (B-D3).
      await tx.execute(
        'UPDATE ingredient SET density_g_per_ml = NULL, macros = NULL, '
        "allowed_units = ?, source = ?, source_score = NULL, status = 'stub', "
        'source_edited = 0, updated_at = ? WHERE id = ?',
        [
          jsonEncode([for (final u in _strippedOfDensity(current)) u.id]),
          usdaDeclinedSource,
          now,
          ingredientId,
        ],
      );
      return true;
    });
    return declined ? byId(ingredientId) : null;
  }

  @override
  Future<Ingredient?> stopOfferingPiece(String ingredientId) async {
    // Read-modify-write for the same reason the density pair is: the list
    // written back is derived from the row as it is read.
    final now = DateTime.now().toUtc().toIso8601String();
    final updated = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.id = ? AND i.deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      final current = _toIngredient(row);
      final kept = {...current.allowedUnits ?? defaultAllowedUnitSet(current)};
      if (!kept.remove(pieces)) return true; // nothing to take away
      await tx.execute(
        'UPDATE ingredient SET allowed_units = ?, updated_at = ? WHERE id = ?',
        [
          jsonEncode([for (final u in kept) u.id]),
          now,
          ingredientId,
        ],
      );
      return true;
    });
    if (!updated) return null;
    return byId(ingredientId);
  }

  @override
  Future<Ingredient?> setDefaultMeasure(
    String ingredientId,
    String? measureId,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final wrote = await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT id FROM ingredient WHERE id = ? AND deleted_at IS NULL',
        [ingredientId],
      );
      if (row == null) return false;
      if (measureId != null) {
        // The server's own-measure trigger (0023) refuses a measure from
        // another row or another household. Checking it here too is not
        // belt-and-braces: local writes land in SQLite first and only reach
        // that trigger on the next upload, so without this the app would
        // read back a default that the server is about to reject.
        final measure = await tx.getOptional(
          'SELECT id FROM ingredient_measure '
          'WHERE id = ? AND ingredient_id = ? AND deleted_at IS NULL',
          [measureId, ingredientId],
        );
        if (measure == null) {
          throw ArgumentError.value(
            measureId,
            'measureId',
            'is not a live measure of ingredient $ingredientId',
          );
        }
      }
      await tx.execute(
        'UPDATE ingredient SET default_measure_id = ?, updated_at = ? '
        'WHERE id = ?',
        [measureId, now, ingredientId],
      );
      return true;
    });
    if (!wrote) return null;
    return byId(ingredientId);
  }

  // --- The manager's write half (step 8.5) -----------------------------------

  @override
  Stream<List<Ingredient>> watchVocabulary() => _db
      .watch(
        'SELECT i.*, $_measureCount FROM ingredient i '
        'WHERE i.deleted_at IS NULL ORDER BY i.canonical_name',
      )
      .map((rows) => rows.map(_toIngredient).toList());

  @override
  Stream<int> watchStubCount() => _db
      .watch(
        "SELECT COUNT(*) AS n FROM ingredient WHERE status = 'stub' "
        'AND deleted_at IS NULL',
      )
      .map((rows) => (rows.first['n'] as int?) ?? 0);

  @override
  Stream<int> watchVocabularyCount() => _db
      .watch('SELECT COUNT(*) AS n FROM ingredient WHERE deleted_at IS NULL')
      .map((rows) => (rows.first['n'] as int?) ?? 0);

  @override
  Stream<List<String>> watchCategories() => _db
      .watch(
        'SELECT DISTINCT TRIM(category) AS c FROM ingredient '
        'WHERE deleted_at IS NULL AND category IS NOT NULL '
        "AND TRIM(category) <> '' "
        'ORDER BY c',
      )
      .map((rows) => [for (final r in rows) r['c'] as String]);

  @override
  Future<Ingredient?> saveForm(
    String? ingredientId,
    IngredientFormEdit edit,
  ) async {
    // **Validate everything BEFORE opening the transaction.** The contract is
    // that nothing is written when this throws, and the cheapest way to mean
    // it is to refuse before a single statement runs. These are the same
    // lines `addMeasure` and `addAlias` hold — batching does not soften them.
    final name = edit.row.canonicalName.trim();
    if (name.isEmpty) {
      throw ArgumentError.value(
        edit.row.canonicalName,
        'canonicalName',
        'must not be blank',
      );
    }
    for (final m in edit.measuresAdded) {
      final label = m.label.trim();
      if (label.isEmpty) {
        throw ArgumentError.value(m.label, 'label', 'must not be empty');
      }
      if (isVolumeUnitLabel(label)) {
        throw ArgumentError.value(
          m.label,
          'label',
          'names a volume unit — density owns volume conversion',
        );
      }
      // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
      if (!(m.amount > 0)) {
        throw ArgumentError.value(
          m.amount,
          'amount',
          'must be a positive number',
        );
      }
    }
    final aliases = <({String id, String text, String matchText})>[];
    for (final a in edit.aliasesAdded) {
      final trimmed = a.text.trim();
      final matchText = normalizeMatchText(trimmed);
      if (matchText.isEmpty) {
        throw ArgumentError.value(
          a.text,
          'text',
          'an alias must carry at least one identity word',
        );
      }
      aliases.add((id: a.id, text: trimmed, matchText: matchText));
    }
    final density = edit.density;
    if (density is DensitySet && !(density.gPerMl > 0)) {
      throw ArgumentError.value(
        density.gPerMl,
        'gPerMl',
        'must be a positive number',
      );
    }

    final macros = edit.row.macros;
    final macrosJson = _macrosJson(macros);
    final now = DateTime.now().toUtc().toIso8601String();

    // C1: a form with no row yet mints one here, so the row and its children
    // are inserted in the same transaction — a create that half-lands stops
    // being representable, which the sheet's four-calls-under-one-guard never
    // managed.
    final creating = ingredientId == null;
    final id = ingredientId ?? _uuid.v4();

    final ok = await _db.writeTransaction((tx) async {
      if (creating) {
        // Born a stub whatever arrived: filling a form in never promotes a
        // row — only `markComplete` does, which is a human tapping the CTA.
        await tx.execute(
          'INSERT INTO ingredient (id, household_id, canonical_name, '
          'default_unit, status, match_text, created_at, updated_at) '
          "VALUES (?, ?, ?, 'g', 'stub', ?, ?, ?)",
          [id, _householdId, name, normalizeMatchText(name), now, now],
        );
      }
      // The row AS IT STANDS — the status the CTA may flip, and the four facts
      // the edited flag is decided against (see [_sourceEditedPatch]).
      final row = await tx.getOptional(
        'SELECT status, source, macros, macros_basis, density_g_per_ml '
        'FROM ingredient WHERE id = ? AND deleted_at IS NULL',
        [id],
      );
      if (row == null) return false;
      // D5, both directions in one place now. Clearing the macros of a
      // complete row returns it to `stub` rather than leaving it asserting a
      // number it no longer has; filling them in never promotes on its own —
      // only `markComplete`, which is a human tapping the CTA (W5b).
      final status = macros == null
          ? 'stub'
          : edit.markComplete
          ? 'complete'
          : row['status'] as String;

      // The row itself. `allowed_units` is written AS THE FORM HOLDS IT: the
      // draft has already applied whatever the density unlocked or stripped,
      // so re-deriving here would give two owners to one fact.
      await tx.execute(
        'UPDATE ingredient SET canonical_name = ?, match_text = ?, '
        'category = ?, default_unit = ?, macros = ?, macros_basis = ?, '
        'allowed_units = ?, status = ?, '
        // Provenance is patch-shaped (see [IngredientEdit.source]): a null
        // keeps what is stored, so a save that is not about the match cannot
        // erase which food filled the row.
        'source = COALESCE(?, source), '
        'source_label = COALESCE(?, source_label), '
        'source_score = COALESCE(?, source_score), '
        // Patch-shaped too, and for a sharper reason: most saves have nothing
        // to say about the flag, and a save that DID edit the numbers must not
        // be un-said by the next one that only renamed the row (0034).
        'source_edited = COALESCE(?, source_edited), '
        'updated_at = ? WHERE id = ?',
        [
          name,
          // The rename hazard (D6): the stored name and its match_text are
          // written together or the cascade searches for a name nothing
          // carries.
          normalizeMatchText(name),
          edit.row.category,
          edit.row.defaultUnit.id,
          macrosJson,
          edit.row.macrosBasis.dbValue,
          jsonEncode([for (final u in edit.row.allowedUnits) u.id]),
          status,
          edit.row.source,
          edit.row.sourceLabel,
          edit.row.sourceScore,
          _sourceEditedPatch(
            storedSource: row['source'] as String?,
            storedMacros: Macros.tryParse(row['macros'] as String?),
            storedBasis: MacrosBasis.fromDb(row['macros_basis'] as String?),
            storedDensity: (row['density_g_per_ml'] as num?)?.toDouble(),
            edit: edit,
          ),
          now,
          id,
        ],
      );

      switch (density) {
        case DensitySet(:final gPerMl):
          await tx.execute(
            'UPDATE ingredient SET density_g_per_ml = ?, updated_at = ? '
            'WHERE id = ?',
            [gPerMl, now, id],
          );
        case DensityCleared():
          await tx.execute(
            'UPDATE ingredient SET density_g_per_ml = NULL, updated_at = ? '
            'WHERE id = ?',
            [now, id],
          );
        case DensityUnchanged():
          break;
      }

      if (edit.defaultMeasure case DefaultMeasureSet(:final measureId)) {
        await tx.execute(
          'UPDATE ingredient SET default_measure_id = ?, updated_at = ? '
          'WHERE id = ?',
          [measureId, now, id],
        );
      }

      // Removals first, so a label freed in this same save can be re-added in
      // it without the two rows coexisting even momentarily.
      for (final id in edit.measuresRemoved) {
        await tx.execute(
          'UPDATE ingredient_measure SET deleted_at = ?, updated_at = ? '
          'WHERE id = ?',
          [now, now, id],
        );
      }
      for (final id in edit.aliasesRemoved) {
        await tx.execute(
          'UPDATE ingredient_alias SET deleted_at = ?, updated_at = ? '
          'WHERE id = ?',
          [now, now, id],
        );
      }

      if (edit.measuresAdded.isNotEmpty) {
        final maxRow = await tx.get(
          'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
          'WHERE ingredient_id = ? AND deleted_at IS NULL',
          [id],
        );
        var sortOrder = (maxRow['m'] as int) + 1;
        for (final m in edit.measuresAdded) {
          // A plain INSERT, never ON CONFLICT (view-backed local tables
          // reject UPSERT), and no label-collision check — a duplicate merges
          // on read instead of failing anywhere.
          await tx.execute(
            'INSERT INTO ingredient_measure '
            '(id, household_id, ingredient_id, label, basis_amount, '
            'sort_order, source, created_at, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              m.id,
              _householdId,
              id,
              m.label.trim(),
              m.amount,
              sortOrder++,
              'manual',
              now,
              now,
            ],
          );
        }
      }

      for (final a in aliases) {
        // Find-or-create, not blind insert (the import cascade's rule): two
        // identically matching aliases on one ingredient are noise that can
        // only ever tie.
        final existing = await tx.getOptional(
          'SELECT id FROM ingredient_alias '
          'WHERE ingredient_id = ? AND match_text = ? AND deleted_at IS NULL '
          'LIMIT 1',
          [id, a.matchText],
        );
        if (existing != null) continue;
        await tx.execute(
          'INSERT INTO ingredient_alias '
          '(id, household_id, ingredient_id, alias_text, match_text, source, '
          'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [a.id, _householdId, id, a.text, a.matchText, 'manual', now, now],
        );
      }
      return true;
    });
    if (!ok) return null;
    return byId(id);
  }

  /// What this save has to say about `source_edited` — `1`, `0`, or **null for
  /// "nothing"**, which the `COALESCE` above turns into "leave it as it is"
  /// (migration 0034).
  ///
  /// Three answers, and the fence is the whole design:
  ///
  /// * **A fresh stamp clears it.** [IngredientEdit.source] is non-null only
  ///   when this very save carries a new provenance — a USDA pick or a barcode
  ///   read — and then the numbers landing beside it ARE that source's, so the
  ///   row starts un-edited whatever it said before (B-D3).
  /// * **A human write over a lookup's numbers sets it.** Only macros, the
  ///   macros basis and the density count. That is the fence: a rename, a unit
  ///   toggle, a measure, an alias, "Counts as", a category, `Mark complete` —
  ///   none of them contradicts the source, so none of them may set the flag.
  ///   A save that only touches those returns null here and the stored value
  ///   stands, in both directions.
  /// * **Anything else says nothing.** Including every save on a row with no
  ///   lookup provenance to contradict ([isLookupFilled]): a `manual` row's
  ///   numbers were always its owner's, so "edited" is not a fact about it.
  ///
  /// Compared against the row AS STORED, not against the draft's own idea of
  /// what changed: opening a form and saving it untouched must not flag it,
  /// and `MacroDraft` seeds losslessly precisely so that round-trip is exact.
  ///
  /// Once set it is **sticky** until a fresh pick, which is the honest answer
  /// available: the source's own figures are not kept on the row (B-D1 refused
  /// a second copy of them), so nothing here can tell a number typed back to
  /// the food's value from a coincidence.
  static int? _sourceEditedPatch({
    required String? storedSource,
    required Macros? storedMacros,
    required MacrosBasis storedBasis,
    required double? storedDensity,
    required IngredientFormEdit edit,
  }) {
    if (edit.row.source != null) return 0;
    if (!isLookupFilled(storedSource)) return null;
    final densityChanged = switch (edit.density) {
      DensitySet(:final gPerMl) => gPerMl != storedDensity,
      DensityCleared() => storedDensity != null,
      DensityUnchanged() => false,
    };
    final changed =
        densityChanged ||
        edit.row.macros != storedMacros ||
        edit.row.macrosBasis != storedBasis;
    return changed ? 1 : null;
  }

  @override
  Future<Ingredient?> unconfirm(String ingredientId) =>
      _setStatus(ingredientId, 'stub');

  Future<Ingredient?> _setStatus(String ingredientId, String status) async {
    await _db.execute(
      'UPDATE ingredient SET status = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [status, DateTime.now().toUtc().toIso8601String(), ingredientId],
    );
    return byId(ingredientId);
  }

  /// Live recipe lines naming [ingredientId], as (recipes, lines) — the
  /// delete guard's evidence, and the numbers a refusal names.
  Future<({int recipeCount, int lineCount})> _recipeReferences(
    String ingredientId,
  ) async {
    // A line's recipe is reached through its group, and both must be live —
    // a line inside a tombstoned group belongs to nothing a user can open.
    final row = await _db.get(
      'SELECT COUNT(*) AS lines, COUNT(DISTINCT gr.recipe_id) AS recipes '
      'FROM recipe_line_item li '
      'JOIN ingredient_group gr ON gr.id = li.group_id '
      'JOIN recipe r ON r.id = gr.recipe_id '
      'WHERE li.ingredient_id = ? AND li.deleted_at IS NULL '
      'AND gr.deleted_at IS NULL AND r.deleted_at IS NULL',
      [ingredientId],
    );
    return (
      recipeCount: (row['recipes'] as int?) ?? 0,
      lineCount: (row['lines'] as int?) ?? 0,
    );
  }

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) async {
    final current = await byId(ingredientId);
    if (current == null) return const DeleteMissing();
    final refs = await _recipeReferences(ingredientId);
    if (refs.lineCount > 0) {
      return DeleteRefused(
        recipeCount: refs.recipeCount,
        lineCount: refs.lineCount,
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE ingredient SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [now, now, ingredientId],
      );
      // The aliases go with it: an alias outliving its ingredient is a match
      // that resolves to nothing.
      await tx.execute(
        'UPDATE ingredient_alias SET deleted_at = ?, updated_at = ? '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [now, now, ingredientId],
      );
    });
    return const Deleted();
  }

  @override
  Stream<List<IngredientAlias>> watchAliases(String ingredientId) => _db
      .watch(
        'SELECT id, alias_text, source FROM ingredient_alias '
        'WHERE ingredient_id = ? AND deleted_at IS NULL '
        'ORDER BY created_at, id',
        parameters: [ingredientId],
      )
      .map(_toAliases);

  static List<IngredientAlias> _toAliases(Iterable<Row> rows) => [
    for (final r in rows)
      IngredientAlias(
        id: r['id'] as String,
        text: r['alias_text'] as String,
        source: (r['source'] as String?) ?? 'manual',
      ),
  ];

  Ingredient _toIngredient(Row r) => Ingredient(
    id: r['id'] as String,
    canonicalName: r['canonical_name'] as String,
    // Seed units are always valid units.dart ids; fall back defensively.
    defaultUnit: unitById(r['default_unit'] as String) ?? pieces,
    status: r['status'] == 'complete'
        ? IngredientStatus.complete
        : IngredientStatus.stub,
    category: r['category'] as String?,
    densityGPerMl: (r['density_g_per_ml'] as num?)?.toDouble(),
    macros: Macros.tryParse(r['macros'] as String?),
    macrosBasis: MacrosBasis.fromDb(r['macros_basis'] as String?),
    allowedUnits: _parseAllowedUnits(r['allowed_units'] as String?),
    defaultMeasureId: r['default_measure_id'] as String?,
    measureCount: (r['measure_count'] as int?) ?? 0,
    source: r['source'] as String?,
    sourceLabel: r['source_label'] as String?,
    sourceScore: (r['source_score'] as num?)?.toDouble(),
    // PowerSync carries the server's boolean as 0/1. A row synced before 0034
    // has no value at all, which is the same answer as `false`: nobody edited
    // it, because there was nothing to record the edit in.
    sourceEdited: (r['source_edited'] as int?) == 1,
  );

  /// Parses the row's `allowed_units` jsonb (a JSON array of unit ids) into
  /// catalog units. Unknown ids are dropped (a newer server vocabulary must
  /// not orphan this client); a malformed/absent value is null, which sends
  /// the pickers to the derived-defaults fallback.
  static List<Unit>? _parseAllowedUnits(String? json) {
    if (json == null || json.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! List) return null;
    return [
      for (final id in decoded)
        if (id is String && unitById(id) != null) unitById(id)!,
    ];
  }
}
