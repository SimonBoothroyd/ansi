/// The sync runner end to end, on fakes: meals ticked while the switch was
/// off reach Health Connect once it is turned on.
library;

import 'package:ansi/core/sync/session.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/health/data/health_providers.dart';
import 'package:ansi/features/health/presentation/health_sync.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:ansi/features/recipes/domain/recipe_macros.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_health.dart';

void main() {
  final weekStart = DateTime(2026, 10, 18);
  const curry = RecipeMacroSummary(
    perServing: Macros(kcal: 400, protein: 30, carb: 40, fat: 10),
  );
  final plan = WeekPlan(
    id: 'w',
    weekStart: weekStart,
    entries: [
      for (final (day, id) in [(1, 'e1'), (3, 'e2')])
        PlanEntry(
          id: id,
          dayOfWeek: day,
          mealSlot: 'Dinner',
          recipeId: 'curry',
          recipeTitle: 'Curry',
          eaterIds: const ['ada'],
          eatenAt: {'ada': DateTime(2026, 10, 18 + day, 19)},
        ),
    ],
  );

  ProviderContainer containerFor(
    FakeHealthGateway gateway,
    FakeHealthSendLog log, {
    Map<String, RecipeMacroSummary>? Function()? macros,
  }) {
    final container = ProviderContainer(
      overrides: [
        healthIsSupportedProvider.overrideWithValue(true),
        healthGatewayProvider.overrideWithValue(gateway),
        healthSendLogProvider.overrideWithValue(log),
        currentMemberIdProvider.overrideWithValue('ada'),
        membersByIdProvider.overrideWithValue(const {
          'ada': Member(id: 'ada', displayName: 'Ada'),
        }),
        currentWeekStartProvider.overrideWithValue(weekStart),
        healthWeekProvider.overrideWith(
          (ref, key) => Stream.value(key == '2026-10-18' ? plan : null),
        ),
        healthWeekMacrosProvider.overrideWith(
          (ref, key) => macros == null ? {'curry': curry} : macros(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(healthSyncRunnerProvider, (_, _) {});
    return container;
  }

  testWidgets('meals ticked while off are sent once it is turned on', (
    tester,
  ) async {
    final gateway = FakeHealthGateway()..granted = false;
    final log = FakeHealthSendLog();
    final container = containerFor(gateway, log);

    await tester.pump(const Duration(seconds: 3));
    expect(gateway.records, isEmpty);

    final turnedOn = container
        .read(healthEnabledProvider.notifier)
        .set(on: true);
    await tester.pump();
    expect(await turnedOn, isTrue);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(
      gateway.records.keys,
      unorderedEquals(['ansi:e1:ada', 'ansi:e2:ada']),
    );
  });

  testWidgets('a pass that fails says so, and is tried again on the way '
      'back to the app', (tester) async {
    final gateway = FakeHealthGateway()..unreachable = true;
    final log = FakeHealthSendLog()..on = true;
    final container = containerFor(gateway, log);

    await tester.pump(const Duration(seconds: 3));
    expect(gateway.records, isEmpty);
    expect(container.read(healthSyncRunnerProvider), '2 not sent');

    gateway.unreachable = false;
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(gateway.records, hasLength(2));
    expect(container.read(healthSyncRunnerProvider), isNull);
  });

  testWidgets('nothing is taken back while the recipes are still loading', (
    tester,
  ) async {
    final gateway = FakeHealthGateway();
    final log = FakeHealthSendLog()..on = true;
    containerFor(gateway, log);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(gateway.records, hasLength(2));

    // A fresh start, before the recipes have loaded.
    final later = FakeHealthGateway()..records.addAll(gateway.records);
    containerFor(later, log, macros: () => null);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(later.deleted, isEmpty);
    expect(later.records, hasLength(2));
  });
}
