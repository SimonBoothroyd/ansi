/// `/account` (plan 0028 E6) — the three things v2 D1 said would justify the
/// route: the household, this device, and the session.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/account/presentation/account_view.dart';
import 'package:ansi/features/health/data/health_providers.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_planning_repository.dart';

const _roster = [
  Member(id: 'm1', displayName: 'Ada'),
  Member(id: 'm2', displayName: 'Jun', portionFactor: 0.75),
];

/// Flutter's tests run as Android, so the Health Connect section would draw
/// and reach for the platform; its own test file covers it.
final _noHealthConnect = healthIsSupportedProvider.overrideWithValue(false);

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: [_noHealthConnect, ...overrides],
  child: MaterialApp(
    home: const AccountView(),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    _host([
      planningRepositoryProvider.overrideWithValue(
        FakePlanningRepository(_roster),
      ),
    ]),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the page carries the household, the device and the session', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('HOUSEHOLD'), findsOneWidget);
    expect(find.text('THIS DEVICE'), findsOneWidget);
    expect(find.text('SESSION'), findsOneWidget);
  });

  testWidgets('the roster is the household section, live', (tester) async {
    await _pump(tester);

    expect(find.text('USUAL PORTION'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Jun'), findsOneWidget);
    expect(find.text('×¾'), findsWidgets);
  });

  testWidgets('Sign out asks first, and says the data comes back', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign out?'), findsOneWidget);
    expect(find.text('Your data comes back when you sign in.'), findsOneWidget);

    // Cancelling leaves the session alone — the page is still here.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsNothing);
    expect(find.byType(AccountView), findsOneWidget);
  });
}
