/// The zone handler's floor: a quiet toast, rate-limited and coalesced.
///
/// The limiter is the part worth pinning — an exception thrown inside `build`
/// repeats every frame, and a wall of toasts is worse than the silence it
/// replaced.
library;

import 'package:ansi/core/observability/crash_sink.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// The app's ancestry: a toaster, and the anchor the sink reaches for.
Widget _host() => MaterialApp(
  home: FTheme(
    data: ansiThemeData(),
    child: FToaster(
      child: KeyedSubtree(key: ansiToastAnchor, child: const SizedBox.expand()),
    ),
  ),
);

void main() {
  testWidgets('an unhandled exception gets one quiet toast', (tester) async {
    await tester.pumpWidget(_host());
    ToastCrashSink(() => ansiToastAnchor.currentContext)
        .report(StateError('boom'), StackTrace.empty);
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Ansi kept going.'), findsOneWidget);
    expect(find.text('Copy details'), findsOneWidget);
    // Never the exception's own words on screen.
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('a build loop throwing every frame produces ONE toast', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 2, 14);
    final sink = ToastCrashSink(
      () => ansiToastAnchor.currentContext,
      clock: () => now,
    );
    await tester.pumpWidget(_host());

    for (var i = 0; i < 40; i++) {
      sink.report(StateError('frame $i'), StackTrace.empty);
      now = now.add(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('a later exception, past the interval, speaks again', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 2, 14);
    final sink = ToastCrashSink(
      () => ansiToastAnchor.currentContext,
      clock: () => now,
    );
    await tester.pumpWidget(_host());

    sink.report(StateError('first'), StackTrace.empty);
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong.'), findsOneWidget);

    // Past the window, and past the toast's own lifetime.
    now = now.add(crashToastInterval + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong.'), findsNothing);

    sink.report(StateError('second'), StackTrace.empty);
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong.'), findsOneWidget);
  });

  testWidgets('Copy details carries the whole coalesced burst', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    var now = DateTime(2026, 9, 2, 14);
    final sink = ToastCrashSink(
      () => ansiToastAnchor.currentContext,
      clock: () => now,
    );
    await tester.pumpWidget(_host());

    sink.report(StateError('first'), StackTrace.empty);
    now = now.add(const Duration(milliseconds: 20));
    sink.report(StateError('second'), StackTrace.empty);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy details'));
    await tester.pumpAndSettle();

    // One toast, but both problems in the paste — the second was swallowed by
    // the limiter, not by the app.
    expect(copied.single, contains('first'));
    expect(copied.single, contains('second'));
  });

  test('a NoopCrashSink is exactly that', () {
    const CrashSink sink = NoopCrashSink();
    // Neither call reaches anything: no toast, no anchor, no throw.
    sink
      ..report(StateError('x'), StackTrace.empty)
      ..note(StateError('y'), StackTrace.empty);
    expect(sink, isA<CrashSink>());
  });
}
