/// Health Connect, kept in step with what this phone's member ate.
///
/// [HealthEnabled] is the Account switch. [healthMeals] is what should be in
/// Health Connect: this member's ticked meals and what they had instead, over
/// this week and last. [HealthSyncRunner] writes the difference whenever
/// either changes — a tick, an untick, a swap, a `−`, or the partner's phone
/// removing a meal and this phone hearing of it through sync — so Health
/// Connect never holds a duplicate and never keeps a meal that is gone.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/session.dart';
import '../../../core/week_shape.dart';
import '../../planning/data/planning_providers.dart';
import '../../planning/domain/planning.dart';
import '../../planning/presentation/week_view_models.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_macros.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../data/health_providers.dart';
import '../domain/health_gateway.dart';
import '../domain/health_meal.dart';

part 'health_sync.g.dart';

/// The Account switch: whether this phone sends its member's meals. Turning
/// it on asks Health Connect for permission, and stays off if refused.
/// Turning it off stops sending and leaves what was sent where it is.
@riverpod
class HealthEnabled extends _$HealthEnabled {
  @override
  Future<bool> build() async {
    if (!ref.watch(healthIsSupportedProvider)) return false;
    return ref.watch(healthSendLogProvider).enabled();
  }

  /// Switches sending on or off; true when it is now [on].
  Future<bool> set({required bool on}) async {
    final gateway = ref.read(healthGatewayProvider);
    if (on && !await gateway.canWrite() && !await gateway.requestWrite()) {
      return false;
    }
    await ref.read(healthSendLogProvider).setEnabled(on: on);
    if (!ref.mounted) return true;
    state = AsyncData(on);
    return true;
  }
}

/// Whether Health Connect is on this phone at all.
@riverpod
Future<HealthAvailability> healthAvailability(Ref ref) =>
    ref.watch(healthIsSupportedProvider)
    ? ref.watch(healthGatewayProvider).availability()
    : Future.value(HealthAvailability.unavailable);

/// One week as Health Connect reads it, by its first day's ISO date.
@riverpod
Stream<WeekPlan?> healthWeek(Ref ref, String weekKey) => ref
    .watch(planningRepositoryProvider)
    .watchWeek(DateTime.parse('${weekKey}T00:00:00Z'));

/// The recipes' figures for one week, its variants re-summed.
@riverpod
Map<String, RecipeMacroSummary> healthWeekMacros(Ref ref, String weekKey) => {
  for (final r
      in ref.watch(recipeListProvider).asData?.value ?? const <RecipeSummary>[])
    if (r.macros != null) r.id: r.macros!,
  ...ref.watch(weekVariantMacrosForProvider(weekKey)).asData?.value ?? const {},
};

/// What should be in Health Connect — this member's meals over this week and
/// last — and what cannot be sent. Null while who is signed in is not known,
/// or a week has not loaded: nothing is written or taken back on a guess.
@riverpod
({List<HealthMeal> meals, List<String> notSent})? healthMeals(Ref ref) {
  final me = ref.watch(currentMemberIdProvider);
  if (me == null) return null;
  final members = ref.watch(membersByIdProvider);
  final current = ref.watch(currentWeekStartProvider);
  final meals = <HealthMeal>[];
  final notSent = <String>[];
  for (final start in [current.subtract(const Duration(days: 7)), current]) {
    final key = isoDateOf(start);
    final week = ref.watch(healthWeekProvider(key));
    if (!week.hasValue) return null;
    final plan = week.value;
    if (plan == null) continue;
    final macros = ref.watch(healthWeekMacrosProvider(key));
    final found = healthMealsIn(
      plan,
      memberId: me,
      membersById: members,
      summaryFor: (id) => macros[id],
    );
    meals.addAll(found.meals);
    notSent.addAll(found.notSent);
  }
  return (meals: meals, notSent: notSent);
}

/// Writes the difference between [healthMeals] and what was last sent, a
/// moment after anything changes, while the switch is on. Watched from the
/// app's root for the app's whole life, so it runs whatever is on screen and
/// keeps everything it reads alive.
@riverpod
class HealthSyncRunner extends _$HealthSyncRunner {
  Timer? _debounce;
  bool _running = false;
  bool _again = false;

  @override
  void build() {
    ref.onDispose(() => _debounce?.cancel());
    if (!ref.watch(healthIsSupportedProvider)) return;
    final on = ref.watch(healthEnabledProvider).asData?.value ?? false;
    final wanted = ref.watch(healthMealsProvider);
    if (!on || wanted == null) return;
    _debounce?.cancel();
    final window = ref
        .watch(currentWeekStartProvider)
        .subtract(const Duration(days: 7));
    _debounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(_reconcile(wanted.meals, window)),
    );
  }

  Future<void> _reconcile(List<HealthMeal> wanted, DateTime window) async {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      await reconcileHealth(
        wanted,
        windowStart: window,
        gateway: ref.read(healthGatewayProvider),
        log: ref.read(healthSendLogProvider),
      );
    } on Exception catch (e) {
      // Permission withdrawn in Health Connect, or it went away: the next
      // change tries again, and the log still says what is there.
      debugPrint('health: not sent ($e)');
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      final latest = ref.read(healthMealsProvider);
      if (latest != null) await _reconcile(latest.meals, window);
    }
  }
}

/// One pass: take back what should no longer be there, write what is new or
/// changed, and remember what is now sent. Deletes go first, so a meal that
/// moved never shows twice. Meals planned before [windowStart] are left as
/// they are, there and in the log's place.
Future<void> reconcileHealth(
  List<HealthMeal> wanted, {
  required DateTime windowStart,
  required HealthGateway gateway,
  required HealthSendLog log,
}) async {
  if (!await gateway.canWrite()) return;
  final sent = await log.sent();
  final plan = diffHealth(wanted, sent, windowStart: windowStart);
  if (plan.write.isEmpty && plan.delete.isEmpty) return;
  await gateway.delete(plan.delete);
  await gateway.write(plan.write);
  await log.setSent(plan.keep);
}
