/// Riverpod wiring for the planning data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/planning_repository.dart';
import '../domain/week_variant_repository.dart';
import 'planning_repository_impl.dart';
import 'week_variant_repository_impl.dart';

part 'planning_providers.g.dart';

@Riverpod(keepAlive: true)
PlanningRepository planningRepository(Ref ref) => SqlitePlanningRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);

@Riverpod(keepAlive: true)
WeekVariantRepository weekVariantRepository(Ref ref) =>
    SqliteWeekVariantRepository(
      ref.watch(databaseProvider),
      householdId: ref.watch(currentHouseholdIdProvider),
    );
