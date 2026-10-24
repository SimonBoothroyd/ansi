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
import 'package:flutter/widgets.dart' show AppLifecycleListener;
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

/// The recipes' figures for one week, its variants re-summed. Null until
/// both have loaded: read early, every meal would look like it had no macros
/// and a pass would take back everything already sent.
@riverpod
Map<String, RecipeMacroSummary>? healthWeekMacros(Ref ref, String weekKey) {
  final recipes = ref.watch(recipeListProvider);
  final variants = ref.watch(weekVariantMacrosForProvider(weekKey));
  if (!recipes.hasValue || !variants.hasValue) return null;
  return {
    for (final r in recipes.value ?? const <RecipeSummary>[])
      if (r.macros != null) r.id: r.macros!,
    ...?variants.value,
  };
}

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
    if (macros == null) return null;
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
/// moment after anything changes and whenever the app comes back to the
/// front, while the switch is on. Watched from the app's root for the app's
/// whole life, so it runs whatever is on screen and keeps everything it reads
/// alive.
///
/// Its value is why the last pass did not reach Health Connect, or null when
/// it did: Account shows it, and its *Try again* invalidates this.
@riverpod
class HealthSyncRunner extends _$HealthSyncRunner {
  Timer? _debounce;
  bool _running = false;
  bool _again = false;
  String? _problem;

  @override
  String? build() {
    ref.onDispose(() => _debounce?.cancel());
    if (!ref.watch(healthIsSupportedProvider)) return null;
    final on = ref.watch(healthEnabledProvider).asData?.value ?? false;
    final wanted = ref.watch(healthMealsProvider);
    if (!on) return _problem = null;
    if (wanted == null) return _problem;
    final window = ref
        .watch(currentWeekStartProvider)
        .subtract(const Duration(days: 7));
    void soon() {
      _debounce?.cancel();
      _debounce = Timer(
        const Duration(seconds: 2),
        () => unawaited(_reconcile(window)),
      );
    }

    soon();
    // A pass that failed in the background (or never ran because the app
    // was put away) is tried again on the way back.
    final lifecycle = AppLifecycleListener(onResume: soon);
    ref.onDispose(lifecycle.dispose);
    return _problem;
  }

  Future<void> _reconcile(DateTime window) async {
    if (_running) {
      _again = true;
      return;
    }
    final wanted = ref.read(healthMealsProvider);
    if (wanted == null) return;
    _running = true;
    try {
      final unsent = await reconcileHealth(
        wanted.meals,
        windowStart: window,
        gateway: ref.read(healthGatewayProvider),
        log: ref.read(healthSendLogProvider),
      );
      _problem = unsent.isEmpty ? null : '${unsent.length} not sent';
    } on Exception catch (e) {
      // Permission withdrawn in Health Connect, or it went away: the log
      // still says what is there, and the next pass tries again.
      debugPrint('health: not sent ($e)');
      _problem = e is HealthNotAllowed
          ? 'Permission is off in Health Connect'
          : 'Not sent';
    } finally {
      _running = false;
    }
    if (ref.mounted) state = _problem;
    if (_again && ref.mounted) {
      _again = false;
      await _reconcile(window);
    }
  }
}

/// One pass: take back what should no longer be there, write what is new or
/// changed, and remember what is now sent. Deletes go first, so a meal that
/// moved never shows twice. Meals planned before [windowStart] are left as
/// they are, there and in the log's place.
///
/// A batch Health Connect refuses is sent again one meal at a time, so one
/// record it will not take never holds back the rest. Returns the ids it
/// would not take; they stay unsent in the log, and the next pass tries them
/// again. Throws when Health Connect cannot be reached at all.
Future<List<String>> reconcileHealth(
  List<HealthMeal> wanted, {
  required DateTime windowStart,
  required HealthGateway gateway,
  required HealthSendLog log,
}) async {
  if (!await gateway.canWrite()) throw const HealthNotAllowed();
  final sent = await log.sent();
  final plan = diffHealth(wanted, sent, windowStart: windowStart);
  if (plan.write.isEmpty && plan.delete.isEmpty) return const [];
  await gateway.delete(plan.delete);
  final refused = <String>[];
  try {
    await gateway.write(plan.write);
  } on Exception catch (e) {
    debugPrint('health: batch refused ($e); one at a time');
    for (final meal in plan.write) {
      try {
        await gateway.write([meal]);
      } on Exception catch (e) {
        debugPrint('health: ${meal.name} refused ($e)');
        refused.add(meal.id);
      }
    }
  }
  await log.setSent({
    for (final e in plan.keep.entries)
      if (!refused.contains(e.key))
        e.key: e.value
      // What Health Connect still holds from before, so it is not orphaned.
      else if (sent[e.key] case final before?)
        e.key: before,
  });
  return refused;
}

/// Ansi may not write nutrition: permission was taken back in Health Connect.
class HealthNotAllowed implements Exception {
  const HealthNotAllowed();

  @override
  String toString() => 'Health Connect permission is off';
}
