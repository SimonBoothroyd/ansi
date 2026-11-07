/// Fridge and freezer rows for repository tests, written as a later build's
/// Leftovers page will write them: plain INSERTs and UPDATEs, since
/// PowerSync's local tables are views.
library;

import 'package:powersync/powersync.dart';

/// Stores a `leftover` row in household `h`: a recipe's or, with [label], the
/// household's own words.
Future<void> insertLeftover(
  PowerSyncDatabase db, {
  required String id,
  String place = 'freezer',
  String? recipeId,
  String? label,
  double portions = 2,
  String since = '2026-08-24',
  String? batch,
}) => db.execute(
  'INSERT INTO leftover (id, household_id, place, recipe_id, label, '
  'portions, since, batch, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    'h',
    place,
    recipeId,
    label,
    portions,
    since,
    batch,
    '2026-08-24T12:00:00Z',
    '2026-08-24T12:00:00Z',
  ],
);

/// Marks the meal [entryId] as eaten from the stored row [leftoverId].
Future<void> planFromLeftover(
  PowerSyncDatabase db,
  String entryId,
  String leftoverId,
) => db.execute('UPDATE plan_entry SET from_leftover = ? WHERE id = ?', [
  leftoverId,
  entryId,
]);
