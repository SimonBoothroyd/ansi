/// Cookings for repository tests, written as the app writes them: plain
/// INSERTs and UPDATEs, since PowerSync's local tables are views.
library;

import 'package:powersync/powersync.dart';

/// Stores a `cooking` row in household `h`. With [since], it is food said by
/// hand on [place]; without, a cooking dated by its ticks.
Future<void> insertCooking(
  PowerSyncDatabase db, {
  required String id,
  String? recipeId,
  String? label,
  double? made,
  String? place,
  String? since,
  String? goneAt,
}) => db.execute(
  'INSERT INTO cooking (id, household_id, recipe_id, label, made, place, '
  'since, gone_at, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    'h',
    recipeId,
    label,
    made,
    place ?? (since == null ? null : 'fridge'),
    since,
    goneAt,
    '2026-08-24T12:00:00Z',
    '2026-08-24T12:00:00Z',
  ],
);

/// Links the meal [entryId] to the cooking [cookingId].
Future<void> linkToCooking(
  PowerSyncDatabase db,
  String entryId,
  String cookingId,
) => db.execute('UPDATE plan_entry SET cooking = ? WHERE id = ?', [
  cookingId,
  entryId,
]);
