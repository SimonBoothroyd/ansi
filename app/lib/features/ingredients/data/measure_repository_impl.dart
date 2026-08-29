/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../domain/allowed_units.dart';
import '../domain/measure_repository.dart';

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

  @override
  Stream<List<Measure>> watchMeasures(String ingredientId) {
    // Ordered oldest-first (by parsed instant, see [_createdKey]) so the
    // merge below keeps the canonical (oldest) row per duplicate label on
    // every device — the offline-dupe doctrine (see the interface doc).
    // Display order is re-established afterwards. The ingredient join
    // supplies the basis its amounts are denominated in (macros_basis is
    // the single stored fact — ADR-0008); LEFT, so a measure whose vocab
    // row hasn't synced yet still lists (basis falls back per-g), and with
    // a SELECTed column so the watch re-fires on ingredient edits too (the
    // LEFT-JOIN watch trap).
    return _db
        .watch(
          'SELECT m.id, m.label, m.basis_amount, m.sort_order, m.source, '
          'm.created_at, i.macros_basis '
          'FROM ingredient_measure m '
          'LEFT JOIN ingredient i ON i.id = m.ingredient_id '
          'WHERE m.ingredient_id = ? AND m.deleted_at IS NULL '
          'ORDER BY m.created_at, m.id',
          parameters: [ingredientId],
        )
        .map((rows) {
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
        });
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
  Future<void> softDeleteMeasure(String measureId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _db.execute(
      'UPDATE ingredient_measure SET deleted_at = ?, updated_at = ? '
      'WHERE id = ?',
      [now, now, measureId],
    );
  }
}
