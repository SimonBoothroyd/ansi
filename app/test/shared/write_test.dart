/// `guardedWrite` / `ref.write` — the one door every user-initiated repository
/// write goes through (`lib/shared/write.dart`).
library;

import 'dart:async';

import 'package:ansi/shared/write.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../helpers/pump_app.dart';

/// A screen with one button that runs [action] through the guard.
class _Screen extends ConsumerWidget {
  const _Screen(this.action, {this.what = 'delete that section'});

  final Future<String> Function() action;
  final String what;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.topCenter,
    child: GestureDetector(
      onTap: () async {
        final result = await ref.write(context, what, action);
        _lastResult = result;
        _calls++;
      },
      child: const Text('go'),
    ),
  );
}

String? _lastResult;
int _calls = 0;

void main() {
  setUp(() {
    _lastResult = null;
    _calls = 0;
  });

  testWidgets('a write that lands returns its value and says nothing', (
    tester,
  ) async {
    await tester.pumpAnsiApp(_Screen(() async => 'ok'));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_lastResult, 'ok');
    expect(find.textContaining('Couldn’t'), findsNothing);
  });

  testWidgets('a write that throws shows the toast and returns null', (
    tester,
  ) async {
    await tester.pumpAnsiApp(
      _Screen(() async => throw StateError('no household')),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(_lastResult, isNull, reason: 'the caller must be able to bail');
    expect(find.text('Couldn’t delete that section.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Never the exception's own words.
    expect(find.textContaining('StateError'), findsNothing);
  });

  testWidgets('Retry runs the write again, and succeeds the second time', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpAnsiApp(
      _Screen(() async {
        attempts++;
        if (attempts == 1) throw StateError('transient');
        return 'saved';
      }),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.text('Couldn’t delete that section.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2, reason: 'Retry re-runs the action, not the future');
    // The toast the retry replaced is gone and no new one took its place.
    expect(find.text('Couldn’t delete that section.'), findsNothing);
  });

  testWidgets('a retried write that fails again toasts again', (tester) async {
    var attempts = 0;
    await tester.pumpAnsiApp(
      _Screen(() async {
        attempts++;
        throw StateError('still broken');
      }),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Couldn’t delete that section.'), findsOneWidget);
  });

  testWidgets("the words come from `what`, in the user's own noun", (
    tester,
  ) async {
    await tester.pumpAnsiApp(
      _Screen(() async => throw Exception('x'), what: "add Tuesday's dinner"),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn’t add Tuesday's dinner."), findsOneWidget);
  });

  testWidgets('an unmounted context is not chased by a toast', (tester) async {
    final completer = Completer<String>();
    final show = ValueNotifier(true);

    await tester.pumpAnsiApp(
      ValueListenableBuilder<bool>(
        valueListenable: show,
        builder: (context, visible, _) =>
            visible ? _Screen(() => completer.future) : const SizedBox(),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    // The sheet the write was started from goes away mid-flight.
    show.value = false;
    await tester.pumpAndSettle();
    completer.completeError(StateError('too late'));
    await tester.pumpAndSettle();

    expect(_calls, 1, reason: 'the guard still returned to its caller');
    expect(_lastResult, isNull);
    expect(find.textContaining('Couldn’t'), findsNothing);
  });
}
