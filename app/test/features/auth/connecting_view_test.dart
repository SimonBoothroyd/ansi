/// Widget tests for [ConnectingView]: the spinner while connecting, and the
/// retry / sign-out affordances once the session machine reports an error (a
/// failure must never strand the user on an infinite spinner), including the
/// swap in prominence when the account is gone server-side.
library;

import 'package:ansi/core/sync/session.dart';
import 'package:ansi/core/theme/mise_theme.dart';
import 'package:ansi/features/auth/presentation/connecting_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

/// The [FButton] wrapping the given label, to read its prominence.
FButton _buttonFor(WidgetTester tester, String label) => tester.widget<FButton>(
  find.ancestor(of: find.text(label), matching: find.byType(FButton)),
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
    // Retry leads for anything that might just be a bad moment.
    expect(_buttonFor(tester, 'Retry').variant, FButtonVariant.primary);
    expect(_buttonFor(tester, 'Sign out').variant, FButtonVariant.ghost);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls.retries, 1);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(calls.signOuts, 1);
  });

  testWidgets('on a deleted account: sign-out leads, retry steps back', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(
        const SessionError(
          SessionError.accountMissingMessage,
          accountMissing: true,
        ),
        calls,
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('This account no longer exists on the server'),
      findsOneWidget,
    );
    // Prominence is the whole point: retrying a ghost session only fails
    // again, so sign-out and retry trade places.
    expect(_buttonFor(tester, 'Sign out').variant, FButtonVariant.primary);
    expect(_buttonFor(tester, 'Retry').variant, FButtonVariant.ghost);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(calls.signOuts, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls.retries, 1, reason: 'retry stays available, just secondary');
  });
}
