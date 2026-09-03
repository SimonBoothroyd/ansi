/// The post-await write door: `hostContextOf` + `container.write` land a write
/// — and report its failure — from a widget that unmounted while its dialog
/// was open. The mechanism every swept site stands on, pinned once.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_modals.dart';
import 'package:ansi/shared/write.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A row that opens a dialog and, on confirm, writes through the handles it
/// captured BEFORE the await — the swept shape. [action] is the write.
class _Row extends ConsumerWidget {
  const _Row({required this.action});

  final Future<void> Function() action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FButton(
      onPress: () async {
        final container = ProviderScope.containerOf(context, listen: false);
        final host = hostContextOf(context);
        final ok = await showAnsiDialog<bool>(
          context: context,
          builder: (context, style, animation) => FDialog(
            animation: animation,
            title: const Text('Sure?'),
            actions: [
              FButton(
                onPress: () => Navigator.of(context).pop(true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
        if (!(ok ?? false)) return;
        await container.writeOk(host, 'do the thing', action);
      },
      child: const Text('open'),
    );
  }
}

/// The app's ancestry — theme and the one toaster ABOVE the navigator — with
/// the row swappable for nothing while a dialog is up.
Widget _host(ValueNotifier<bool> show, Future<void> Function() action) =>
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) => FTheme(
          data: ansiThemeData(),
          child: FToaster(child: child!),
        ),
        home: FScaffold(
          child: ValueListenableBuilder<bool>(
            valueListenable: show,
            builder: (_, visible, _) =>
                visible ? _Row(action: action) : const SizedBox.shrink(),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the write lands after the opener unmounted under its dialog', (
    tester,
  ) async {
    var ran = 0;
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await tester.pumpWidget(_host(show, () async => ran++));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Sure?'), findsOneWidget);

    show.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(_Row), findsNothing);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(ran, 1);
  });

  testWidgets('a failure still reports, through the host, with Retry', (
    tester,
  ) async {
    var calls = 0;
    final show = ValueNotifier(true);
    addTearDown(show.dispose);
    await tester.pumpWidget(
      _host(show, () async {
        calls++;
        throw StateError('no');
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    show.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(calls, 1);
    expect(find.textContaining('do the thing'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
}
