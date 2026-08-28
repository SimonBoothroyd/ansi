/// Widget tests for [ConnectingView]: the spinner while connecting, and the
/// retry / sign-out affordances once the session machine reports an error (a
/// failure must never strand the user on an infinite spinner).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/core/sync/session.dart';
import 'package:mise/core/theme/mise_theme.dart';
import 'package:mise/features/auth/presentation/connecting_view.dart';

/// Call counts recorded by [_FakeSessionController] (kept outside the notifier
/// so it exposes no public state beyond `state`).
class _Calls {
  int retries = 0;
  int signOuts = 0;
}

class _FakeSessionController extends SessionController {
  _FakeSessionController(this._initial, this._calls);

  final SessionState _initial;
  final _Calls _calls;

  @override
  SessionState build() => _initial;

  @override
  Future<void> retry() async {
    _calls.retries++;
  }

  @override
  Future<void> signOut() async {
    _calls.signOuts++;
  }
}

Widget _host(SessionState initial, _Calls calls) => ProviderScope(
  overrides: [
    // ignore: scoped_providers_should_specify_dependencies, root test scope
    sessionControllerProvider.overrideWith(
      () => _FakeSessionController(initial, calls),
    ),
  ],
  child: MaterialApp(
    home: FTheme(data: miseThemeData(), child: const ConnectingView()),
  ),
);

void main() {
  testWidgets('while connecting: spinner plus a sign-out escape hatch', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(const SessionConnecting(), calls));
    await tester.pump();

    expect(find.text('Setting up your kitchen…'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    await tester.tap(find.text('Sign out'));
    // A plain pump: the spinner animates forever, so settle would time out.
    // The flushed duration covers FTappable's internal press timers.
    await tester.pump(const Duration(seconds: 1));
    expect(calls.signOuts, 1);
  });

  testWidgets('on error: message, retry and sign-out are offered', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(const SessionError('Exception: network down'), calls),
    );
    await tester.pump();

    expect(find.text('Could not set up your kitchen.'), findsOneWidget);
    expect(find.textContaining('network down'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls.retries, 1);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(calls.signOuts, 1);
  });
}
