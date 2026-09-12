/// Riverpod wiring for the household row — and [weekShape], the one answer
/// anywhere in the app to "which day does the week start on?".
///
/// [weekShape] is SYNCHRONOUS on purpose. Every grid, label, key and derivation
/// reads it, and none of them has a sensible loading state: a week drawn
/// Monday-first for the half-second before the row arrives is the default this
/// household would have had anyway, and it re-draws when the row lands.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../../../core/week_shape.dart';
import '../domain/household_repository.dart';
import 'household_repository_impl.dart';

part 'household_providers.g.dart';

@Riverpod(keepAlive: true)
HouseholdRepository householdRepository(Ref ref) => SqliteHouseholdRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
  flipWeekStart: ref.watch(flipWeekStartProvider),
);

/// The `set_household_week_start` RPC (migration 0043) as a function, so the
/// widget that offers the flip can be tested without a Supabase client.
@Riverpod(keepAlive: true)
FlipWeekStart flipWeekStart(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return (householdId, startsOn) async => supabase.rpc<dynamic>(
    'set_household_week_start',
    params: {'p_household_id': householdId, 'p_starts_on': startsOn},
  );
}

@Riverpod(keepAlive: true)
Stream<WeekShape> weekShapeStream(Ref ref) =>
    ref.watch(householdRepositoryProvider).watchWeekShape();

/// The household's week shape, as a plain value.
///
/// Monday until the row arrives — and equally for a device that cannot reach
/// its own database yet. That is not a swallowed error: the shape has exactly
/// one honest default, the surfaces that read it have no loading state, and a
/// database that never opens has a louder failure than a Monday-first grid.
@Riverpod(keepAlive: true)
WeekShape weekShape(Ref ref) =>
    ref.watch(weekShapeStreamProvider).value ?? WeekShape.monday;
