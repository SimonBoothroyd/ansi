/// Riverpod wiring for the cook-plan data layer.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/database.dart';
import '../../../core/sync/session.dart';
import '../domain/cook_plan_repository.dart';
import '../domain/leftover_repository.dart';
import 'cook_plan_repository_impl.dart';
import 'leftover_repository_impl.dart';

part 'cook_plan_providers.g.dart';

@Riverpod(keepAlive: true)
CookPlanRepository cookPlanRepository(Ref ref) =>
    SqliteCookPlanRepository(ref.watch(databaseProvider));

@Riverpod(keepAlive: true)
LeftoverRepository leftoverRepository(Ref ref) => SqliteLeftoverRepository(
  ref.watch(databaseProvider),
  householdId: ref.watch(currentHouseholdIdProvider),
);
