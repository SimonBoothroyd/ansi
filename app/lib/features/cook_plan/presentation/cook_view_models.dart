/// Riverpod ViewModels for the Cook screen.
///
/// [currentCookPlan] streams the derived cook plan for the active week (the
/// same Monday the Week screen uses). It's read-only — the plan is derived, so
/// there are no mutations here.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../planning/presentation/week_view_models.dart';
import '../data/cook_plan_providers.dart';
import '../domain/cook_plan.dart';

part 'cook_view_models.g.dart';

/// The derived cook plan for the active week, reacting to plan/recipe changes.
@riverpod
Stream<CookPlan> currentCookPlan(Ref ref) => ref
    .watch(cookPlanRepositoryProvider)
    .watchCookPlan(ref.watch(currentWeekStartProvider));
