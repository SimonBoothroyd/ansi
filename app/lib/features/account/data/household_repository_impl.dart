/// [HouseholdRepository] over the local PowerSync SQLite, plus one RPC.
///
/// The read is a watched one-row query. `setWeekStart` calls
/// `set_household_week_start`, and the new value arrives back by sync;
/// nothing here writes `household` locally.
library;

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/week_shape.dart';
import '../domain/household_repository.dart';

/// Calls the server's `set_household_week_start` RPC. A function rather than a
/// client, so a test can fake the network boundary.
typedef FlipWeekStart = Future<void> Function(String householdId, int startsOn);

class SqliteHouseholdRepository implements HouseholdRepository {
  const SqliteHouseholdRepository(
    this._db, {
    required String householdId,
    required FlipWeekStart flipWeekStart,
  }) : _householdId = householdId,
       _flip = flipWeekStart;

  final SqliteConnection _db;
  final String _householdId;
  final FlipWeekStart _flip;

  @override
  Stream<WeekShape> watchWeekShape() => _db
      .watch(
        'SELECT h.week_starts_on FROM household h '
        'WHERE h.id = ? AND h.deleted_at IS NULL LIMIT 1',
        parameters: [_householdId],
      )
      .map((rows) {
        final value = rows.isEmpty
            ? null
            : rows.first['week_starts_on'] as int?;
        // An absent row or column means Monday.
        return value == null ||
                value < DateTime.monday ||
                value > DateTime.sunday
            ? WeekShape.monday
            : WeekShape(value);
      });

  @override
  Future<void> setWeekStart(int startsOn) => _flip(_householdId, startsOn);
}
