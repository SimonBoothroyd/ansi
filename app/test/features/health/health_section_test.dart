/// Account's Health Connect section: one switch, what cannot be sent, and the
/// way to Health Connect's own page while off.
library;

import 'package:ansi/core/sync/session.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/health/data/health_providers.dart';
import 'package:ansi/features/health/domain/health_gateway.dart';
import 'package:ansi/features/health/presentation/health_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_health.dart';
import '../../helpers/forui_semantics.dart';

Future<void> _pump(
  WidgetTester tester, {
  required FakeHealthGateway gateway,
  required FakeHealthSendLog log,
  bool supported = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        healthIsSupportedProvider.overrideWithValue(supported),
        healthGatewayProvider.overrideWithValue(gateway),
        healthSendLogProvider.overrideWithValue(log),
        // Who is signed in is not known: nothing to send, nothing named.
        currentMemberIdProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: const FScaffold(child: HealthSection()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('draws nothing where Health Connect cannot be', (tester) async {
    await _pump(
      tester,
      gateway: FakeHealthGateway(),
      log: FakeHealthSendLog(),
      supported: false,
    );
    expect(find.text('Send my meals'), findsNothing);
  });

  testWidgets('says so when the phone has no Health Connect', (tester) async {
    await _pump(
      tester,
      gateway: FakeHealthGateway()..available = HealthAvailability.unavailable,
      log: FakeHealthSendLog(),
    );
    expect(find.text('Health Connect isn’t on this phone'), findsOneWidget);
    expect(find.byType(FSwitch), findsNothing);
  });

  testWidgets('off: the switch, and the way to Health Connect’s own page', (
    tester,
  ) async {
    final gateway = FakeHealthGateway();
    await _pump(tester, gateway: gateway, log: FakeHealthSendLog());
    expect(find.text('Send my meals'), findsOneWidget);
    await tester.tap(find.text('Manage in Health Connect'));
    await tester.pumpAndSettle();
    expect(gateway.settingsOpened, 1);
  });

  testWidgets('turning it on asks first, and stays off if refused', (
    tester,
  ) async {
    filterForuiSemanticsAssertions();
    final gateway = FakeHealthGateway()
      ..granted = false
      ..grantsOnRequest = false;
    final log = FakeHealthSendLog();
    await _pump(tester, gateway: gateway, log: log);
    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    expect(gateway.requests, 1);
    expect(log.on, isFalse);
    expect(find.text('Manage in Health Connect'), findsOneWidget);
  });

  testWidgets('granted, it is on and the manage row goes', (tester) async {
    filterForuiSemanticsAssertions();
    final gateway = FakeHealthGateway()..granted = false;
    final log = FakeHealthSendLog();
    await _pump(tester, gateway: gateway, log: log);
    await tester.tap(find.byType(FSwitch));
    await tester.pumpAndSettle();
    expect(log.on, isTrue);
    expect(find.text('Manage in Health Connect'), findsNothing);
  });
}
