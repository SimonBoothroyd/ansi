/// Riverpod wiring for the household row, and [weekShape]: which day the week
/// starts on.
///
/// [weekShape] is synchronous because its readers have no loading state; it
/// is Monday until the row arrives, then re-draws.
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

/// The `set_household_week_start` RPC as a function, so the widget that
/// offers the flip can be tested without a Supabase client.
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

/// The household's week shape, as a plain value. Monday until the row
/// arrives, or while the database cannot be reached.
@Riverpod(keepAlive: true)
WeekShape weekShape(Ref ref) =>
    ref.watch(weekShapeStreamProvider).value ?? WeekShape.monday;
