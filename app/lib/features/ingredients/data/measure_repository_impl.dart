/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../domain/allowed_units.dart';
import '../domain/measure_repository.dart';
import '../domain/serving_measure.dart';

const _uuid = Uuid();

class SqliteMeasureRepository implements MeasureRepository {
  const SqliteMeasureRepository(this._db, {required String householdId})
    : _householdId = householdId;

  final SqliteConnection _db;

  /// The household stamped on rows this repo writes.
  final String _householdId;

  /// A comparable creation key: the parsed instant re-serialized canonically
  /// (UTC ISO-8601), falling back to the raw text for unparseable values.
  /// created_at is TEXT and its format differs by writer — this client
  /// writes `…T…Z`, Postgres-sourced rows sync as `… …Z` (the space
  /// separator is the operative difference) — and a bare lexicographic
  /// compare across formats picks the wrong "oldest" (space sorts before
  /// 'T'), so the canonical-row choice would disagree between devices.
  /// Parsing first keeps the merge deterministic across formats. A value
  /// with no zone marker at all is read as UTC — `DateTime.tryParse` would
  /// otherwise read it in the device's local zone, and two devices in
  /// different zones would then disagree about which row is oldest.
  static String _createdKey(Object? raw) {
    final s = raw as String? ?? '';
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return s;
    final utc = parsed.isUtc
        ? parsed
        : DateTime.tryParse('${s.trim()}Z') ?? parsed.toUtc();
    return utc.toIso8601String();
  }

  // Both reads below spell their SELECT out in full rather than sharing an
  // interpolated constant: `watch_coverage_test` reads these queries as
  // literals to hold the LEFT-JOIN watch trap, and a `'$fragment WHERE …'`
  // string is invisible to it. The row→list rule is shared in [_merge], which
  // is the half that could actually drift.

  /// One ingredient's rows, deduplicated and ordered — the shared body of
  /// [watchMeasures] and [measuresByIngredients], so the two can never
  /// disagree about which duplicate is canonical.
  ///
  /// [rows] arrives oldest-first (by parsed instant, see [_createdKey]) so the
  /// merge keeps the canonical (oldest) row per duplicate label on every
  /// device — the offline-dupe doctrine (see the interface doc). Display order
  /// is re-established afterwards.
  static List<Measure> _merge(Iterable<Map<String, dynamic>> rows) {
    final ordered =
        [
          for (final r in rows)
            (
              measure: Measure(
                id: r['id'] as String,
                label: r['label'] as String,
                amount: (r['basis_amount'] as num).toDouble(),
                basis: MacrosBasis.fromDb(r['macros_basis'] as String?),
                sortOrder: (r['sort_order'] as int?) ?? 0,
                source: r['source'] as String?,
              ),
              created: _createdKey(r['created_at']),
            ),
        ]..sort((a, b) {
          final byCreated = a.created.compareTo(b.created);
          return byCreated != 0
              ? byCreated
              : a.measure.id.compareTo(b.measure.id);
        });

    final byLabel = <String, ({Measure measure, String created})>{};
    for (final e in ordered) {
      byLabel.putIfAbsent(e.measure.label, () => e); // newer dupe hidden
    }
    final kept = byLabel.values.toList()
      ..sort((a, b) {
        final bySort = a.measure.sortOrder.compareTo(b.measure.sortOrder);
        if (bySort != 0) return bySort;
        final byCreated = a.created.compareTo(b.created);
        return byCreated != 0
            ? byCreated
            : a.measure.id.compareTo(b.measure.id);
      });
    return [for (final e in kept) e.measure];
  }

  @override
  Future<Map<String, List<Measure>>> measuresByIngredients(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    // Ids are uuids we minted or synced, never user text; they still ride as
    // bound parameters rather than being interpolated into the SQL.
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.getAll(
      'SELECT m.id, m.ingredient_id, m.label, m.basis_amount, m.sort_order, '
      'm.source, m.created_at, i.macros_basis '
      'FROM ingredient_measure m '
      'LEFT JOIN ingredient i ON i.id = m.ingredient_id '
      'WHERE m.ingredient_id IN ($placeholders) AND m.deleted_at IS NULL '
      'ORDER BY m.created_at, m.id',
      ids.toList(),
    );
    final byIngredient = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      (byIngredient[r['ingredient_id'] as String] ??= []).add(r);
    }
    return {for (final e in byIngredient.entries) e.key: _merge(e.value)};
  }

  /// The ingredient join supplies the basis its amounts are denominated in
  /// (macros_basis is the single stored fact — ADR-0008); LEFT, so a measure
  /// whose vocab row hasn't synced yet still lists (basis falls back per-g),
  /// and with a SELECTed column so the watch re-fires on ingredient edits too
  /// (the LEFT-JOIN watch trap).
  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) {
    return _db
        .watch(
          'SELECT m.id, m.ingredient_id, m.label, m.basis_amount, '
          'm.sort_order, m.source, m.created_at, i.macros_basis '
          'FROM ingredient_measure m '
          'LEFT JOIN ingredient i ON i.id = m.ingredient_id '
          'WHERE m.ingredient_id = ? AND m.deleted_at IS NULL '
          'ORDER BY m.created_at, m.id',
          parameters: [ingredientId],
        )
        .map(_merge);
  }

  @override
  Future<Measure> addMeasure({
    required String ingredientId,
    required String label,
    required double amount,
  }) async {
    // Validated at the repository, not just the sheet's form (post-7.7
    // review): every write path — future import included — must hold the
    // same lines. Volume-named labels would shadow density-owned conversion;
    // a non-positive/NaN amount could never convert honestly (invariant 3).
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (isVolumeUnitLabel(trimmed)) {
      throw ArgumentError.value(
        label,
        'label',
        'names a volume unit — density owns volume conversion',
      );
    }
    if (!(amount > 0)) {
      // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
      throw ArgumentError.value(amount, 'amount', 'must be a positive number');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final int sortOrder;
    late final MacrosBasis basis;
    await _db.writeTransaction((tx) async {
      // The basis the amount is denominated in is the ingredient's single
      // stored fact (ADR-0008) — read it so the returned Measure labels
      // itself honestly ("200 ml" of a per-ml ingredient).
      final ing = await tx.getOptional(
        'SELECT macros_basis FROM ingredient WHERE id = ?',
        [ingredientId],
      );
      basis = MacrosBasis.fromDb(ing?['macros_basis'] as String?);
      // After the existing measures. A plain INSERT, never ON CONFLICT
      // (view-backed local tables reject UPSERT), and no label collision
      // check — a duplicate merges on read instead of failing anywhere.
      final row = await tx.get(
        'SELECT COALESCE(MAX(sort_order), -1) AS m FROM ingredient_measure '
        'WHERE ingredient_id = ? AND deleted_at IS NULL',
        [ingredientId],
      );
      sortOrder = (row['m'] as int) + 1;
      await tx.execute(
        'INSERT INTO ingredient_measure '
        '(id, household_id, ingredient_id, label, basis_amount, sort_order, '
        'source, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          ingredientId,
          trimmed,
          amount,
          sortOrder,
          'manual',
          now,
          now,
        ],
      );
    });
    return Measure(
      id: id,
      label: trimmed,
      amount: amount,
      basis: basis,
      sortOrder: sortOrder,
      source: 'manual',
    );
  }

  @override
  Future<void> renameMeasure(String measureId, String label) async {
    // The add form's lines, held here rather than in the row's editor, for
    // the reason addMeasure states: every write path must hold the same ones.
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(label, 'label', 'must not be empty');
    }
    if (isVolumeUnitLabel(trimmed)) {
      throw ArgumentError.value(
        label,
        'label',
        'names a volume unit — density owns volume conversion',
      );
    }
    if (trimmed.startsWith(kServingMeasurePrefix)) {
      throw ArgumentError.value(
        label,
        'label',
        'is the serving’s reserved name — a serving is stated in the '
            'nutrition section',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      final row = await tx.getOptional(
        'SELECT ingredient_id, label FROM ingredient_measure '
        'WHERE id = ? AND deleted_at IS NULL',
        [measureId],
      );
      if (row == null) {
        throw ArgumentError.value(
          measureId,
          'measureId',
          'names no live measure',
        );
      }
      if ((row['label'] as String).startsWith(kServingMeasurePrefix)) {
        throw ArgumentError.value(
          label,
          'label',
          'renames the serving — it is stated in the nutrition section',
        );
      }
      // Exactly the key the merge deduplicates on, so this refuses the
      // renames that would otherwise hide a row rather than every rename a
      // stricter comparison would dislike.
      final clash = await tx.getOptional(
        'SELECT id FROM ingredient_measure WHERE ingredient_id = ? '
        'AND deleted_at IS NULL AND label = ? AND id <> ?',
        [row['ingredient_id'], trimmed, measureId],
      );
      if (clash != null) {
        throw ArgumentError.value(
          label,
          'label',
          'is already a measure of this ingredient',
        );
      }
      await tx.execute(
        'UPDATE ingredient_measure SET label = ?, updated_at = ? WHERE id = ?',
        [trimmed, now, measureId],
      );
    });
  }

  @override
  Future<void> setMeasureAmount(String measureId, double amount) async {
    // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
    if (!(amount > 0)) {
      throw ArgumentError.value(amount, 'amount', 'must be a positive number');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient_measure SET basis_amount = ?, updated_at = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [amount, now, measureId],
    );
  }

  @override
  Future<void> reorderMeasures(String ingredientId, List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      // Stamped by position rather than swapped in pairs: two devices that
      // dragged different rows then converge on one list per row's last
      // write, instead of on a set of half-applied swaps.
      for (final (index, id) in ids.indexed) {
        await tx.execute(
          'UPDATE ingredient_measure SET sort_order = ?, updated_at = ? '
          'WHERE id = ? AND ingredient_id = ? AND deleted_at IS NULL',
          [index, now, id, ingredientId],
        );
      }
    });
  }

  @override
  Future<void> softDeleteMeasure(String measureId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE ingredient_measure SET deleted_at = ?, updated_at = ? '
        'WHERE id = ?',
        [now, now, measureId],
      );
      // Nothing else follows a measure out (ADR-0015): the piece weight is a
      // NUMBER on the ingredient row, copied from a curated size at seed time
      // and owned by the household after that, so deleting the size it was
      // borrowed from leaves the row's own fact exactly as stated.
    });
  }
}
