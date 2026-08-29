/// [MeasureRepository] over the local PowerSync SQLite (synced vocab rows).
library;

import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

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
    // Display order is re-established afterwards.
    return _db
        .watch(
          'SELECT id, label, grams, sort_order, source, created_at '
          'FROM ingredient_measure '
          'WHERE ingredient_id = ? AND deleted_at IS NULL '
          'ORDER BY created_at, id',
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
                      grams: (r['grams'] as num).toDouble(),
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
    required double grams,
  }) async {
    // Validated at the repository, not just the sheet's form (post-7.7
    // review): every write path — future import included — must hold the
    // same lines. Volume-named labels would shadow density-owned conversion;
    // non-positive/NaN grams could never convert honestly (invariant 3).
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
    if (!(grams > 0)) {
      // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
      throw ArgumentError.value(grams, 'grams', 'must be a positive number');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    late final int sortOrder;
    await _db.writeTransaction((tx) async {
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
        '(id, household_id, ingredient_id, label, grams, sort_order, source, '
        'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          _householdId,
          ingredientId,
          trimmed,
          grams,
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
      grams: grams,
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
