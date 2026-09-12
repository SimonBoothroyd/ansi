/// [HouseholdRepository] over the local PowerSync SQLite, plus the one RPC the
/// phone cannot do itself.
///
/// The read is a watched one-row query — the household's own row, which every
/// surface that draws a week reads through `weekShapeProvider`. The write is
/// not a write at all: `setWeekStart` calls `set_household_week_start`, which
/// flips the column and re-homes the household's weeks in one server
/// transaction, and the new column value arrives back by sync. Nothing here
/// ever writes `household` locally.
library;

import 'package:sqlite_async/sqlite_async.dart';

import '../../../core/week_shape.dart';
import '../domain/household_repository.dart';

/// Calls the server's `set_household_week_start` RPC. A function rather than a
/// client, so a test can fake the network boundary the way the session
/// controller's `ensureOnboarded` does.
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
        // An absent row and an absent column mean the same thing: nobody has
        // said otherwise, so the week starts on Monday.
        return value == null ||
                value < DateTime.monday ||
                value > DateTime.sunday
            ? WeekShape.monday
            : WeekShape(value);
      });

  @override
  Future<void> setWeekStart(int startsOn) => _flip(_householdId, startsOn);
}
