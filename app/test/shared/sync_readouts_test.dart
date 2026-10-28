/// The words the four sync states are allowed to say, and the mechanical proof
/// that the Library and the Shop list read the same one.
///
/// This is product copy the owner ruled on, so it is pinned here rather than
/// left to a reviewer's memory. Two words must never appear: **"offline"**
/// (being offline is not a state this app reports) and **"failed"**.
library;

import 'dart:async';
import 'package:ansi/core/sync/dropped_write.dart';
import 'package:ansi/core/sync/sync_health.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/dropped_write_subject.dart';
import 'package:ansi/shared/sync_banner.dart';
import 'package:ansi/shared/sync_health_row.dart';
import 'package:ansi/shared/sync_status_line.dart';
import 'package:ansi/shared/sync_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_app.dart';

final _now = DateTime(2026, 9, 2, 14, 30);
final _since = DateTime(2026, 9, 2, 14, 2);

DroppedWrite _drop({String table = 'recipe', String rowId = 'r1'}) =>
    DroppedWrite(
      table: table,
      op: 'put',
      rowId: rowId,
      code: '42501',
      message: 'new row violates row-level security policy',
      at: _since,
    );

/// Both readouts at once, over ONE overridden provider — so an override that
/// changes what the Library says must change what Shop says in the same pump.
Widget _bothReadouts(SyncHealth health) => ProviderScope(
  overrides: [
    // ignore: scoped_providers_should_specify_dependencies, root test scope
    syncHealthProvider.overrideWith((ref) => Stream.value(health)),
  ],
  child: MaterialApp(
    home: FTheme(
      data: ansiThemeData(),
      child: Column(
        children: [
          const AnsiSyncBanner(),
          const AnsiSyncStatusLine(noun: 'tick'),
          FItemGroup(children: const [SyncHealthRow()]),
        ],
      ),
    ),
  ),
);

void main() {
  group('the words', () {
    test('settled says when, not that it is fine', () {
      expect(
        syncLine(
          SyncSettled(_now.subtract(const Duration(seconds: 5))),
          now: _now,
        ).text,
        'Synced · just now',
      );
      expect(
        syncLine(SyncSettled(_since), now: _now).text,
        'Synced · 28 min ago',
      );
      expect(
        syncLine(const SyncSettled(null), now: _now).text,
        'Not synced yet',
      );
    });

    test('waiting counts, in the screen’s own noun', () {
      expect(
        syncLine(const SyncWaiting(queued: 3), now: _now).text,
        '3 changes waiting',
      );
      expect(
        syncLine(const SyncWaiting(queued: 2), noun: 'tick', now: _now).text,
        '2 ticks waiting',
      );
      expect(
        syncLine(const SyncWaiting(queued: 1), noun: 'tick', now: _now).text,
        '1 tick waiting',
      );
    });

    test('waiting is never styled as an error', () {
      expect(
        syncLine(const SyncWaiting(queued: 3), now: _now).tone,
        SyncTone.busy,
      );
    });

    test('uploading reads as progress, not as a fifth state', () {
      expect(
        syncLine(
          const SyncWaiting(queued: 2, uploading: true),
          noun: 'tick',
          now: _now,
        ).text,
        'Sending…',
      );
    });

    test('stalled names the other phone and the time', () {
      expect(
        syncLine(SyncStalled(queued: 7, since: _since), now: _now).text,
        'Changes aren’t reaching the other phone · since 14:02',
      );
      expect(
        syncLine(
          SyncStalled(queued: 2, since: _since),
          noun: 'tick',
          now: _now,
        ).text,
        'Ticks aren’t reaching the other phone · since 14:02',
      );
    });

    test('never the word "offline", and never "failed"', () {
      final everything = [
        syncLine(const SyncSettled(null), now: _now),
        syncLine(const SyncWaiting(queued: 3), now: _now),
        syncLine(const SyncWaiting(queued: 3, uploading: true), now: _now),
        syncLine(SyncStalled(queued: 3, since: _since), now: _now),
        syncLine(SyncRefused([_drop()]), now: _now),
      ].map((l) => l.text!.toLowerCase());
      for (final line in everything) {
        expect(line, isNot(contains('offline')));
        expect(line, isNot(contains('fail')));
      }
    });
  });

  group('the readouts', () {
    testWidgets('a healthy app confirms once on Shop, then goes quiet', (
      tester,
    ) async {
      await tester.pumpWidget(_bothReadouts(SyncSettled(_since)));
      await tester.pump();

      // Both readouts say it — the Shop line because "it got there" is the
      // confirmation a shopper wants, the Library line because it is always
      // there for anyone who looks.
      expect(find.textContaining('Synced ·'), findsNWidgets(2));
      // The banner never appears for a healthy app.
      expect(find.textContaining('aren’t reaching'), findsNothing);

      // A grocery list does not carry a permanent status bar: the Shop line
      // retires itself and the Library's stays.
      await tester.pump(settledLinger + const Duration(milliseconds: 1));
      expect(find.textContaining('Synced ·'), findsOneWidget);
    });

    testWidgets('waiting is quiet on both, with each screen’s own noun', (
      tester,
    ) async {
      await tester.pumpWidget(_bothReadouts(const SyncWaiting(queued: 2)));
      await tester.pump();
      // The Library's line answers a question someone went looking for, so it
      // is there at once. The Shop's waits out its grace first.
      expect(find.text('2 changes waiting'), findsOneWidget); // Library
      await tester.pump(waitingGrace + const Duration(milliseconds: 1));

      expect(find.text('2 changes waiting'), findsOneWidget); // Library
      expect(find.text('2 ticks waiting'), findsOneWidget); // Shop
      expect(find.textContaining('aren’t reaching'), findsNothing);
    });

    testWidgets('stalled raises the banner AND both lines, from one state', (
      tester,
    ) async {
      await tester.pumpWidget(
        _bothReadouts(SyncStalled(queued: 7, since: _since)),
      );
      await tester.pump();

      // The banner: the board's copy, word for word.
      expect(
        find.text('Changes aren’t reaching the other phone.'),
        findsOneWidget,
      );
      expect(find.text('7 changes not synced since 14:02'), findsOneWidget);
      expect(find.text('Try now'), findsWidgets);
      // And the two quiet lines, in their own nouns — the mechanical proof
      // that Library and Shop cannot disagree: one override, both changed.
      expect(
        find.text('Changes aren’t reaching the other phone · since 14:02'),
        findsOneWidget,
      );
      expect(
        find.text('Ticks aren’t reaching the other phone · since 14:02'),
        findsOneWidget,
      );
    });

    testWidgets('a refused write is the red banner, and Shop does not '
        'repeat it', (tester) async {
      await tester.pumpWidget(_bothReadouts(SyncRefused([_drop()])));
      await tester.pump();

      expect(find.text('1 change didn’t sync.'), findsOneWidget);
      expect(find.text('It’s only on this phone.'), findsOneWidget);
      expect(find.text('Show me'), findsOneWidget);
      // The banner said it. The status line does not say it again.
      expect(find.textContaining('ticks'), findsNothing);
    });

    testWidgets('several refused writes are counted', (tester) async {
      await tester.pumpWidget(
        _bothReadouts(SyncRefused([_drop(), _drop(rowId: 'r2')])),
      );
      await tester.pump();

      expect(find.text('2 changes didn’t sync.'), findsOneWidget);
      expect(find.text('They’re only on this phone.'), findsOneWidget);
    });
  });

  group('"Didn’t sync"', () {
    final curry = _drop();
    final gone = _drop(table: 'plan_entry', rowId: 'p9');

    /// The banner on a router, with the lookup answered: the curry is found,
    /// the meal is not.
    Future<void> open(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        routedHost(
          initial: '/',
          routes: {
            '/': (_, _) => const Column(children: [AnsiSyncBanner()]),
            '/recipes/:id': (_, s) => Text('recipe ${s.pathParameters['id']}'),
          },
          overrides: [
            // ignore: scoped_providers_should_specify_dependencies, root test scope
            syncHealthProvider.overrideWith(
              (ref) => Stream.value(SyncRefused([gone, curry])),
            ),
            droppedWriteSubjectProvider(curry).overrideWith(
              (ref) async => const DroppedWriteSubject(
                name: 'Weeknight Chicken Curry',
                kind: 'recipe edit',
                route: '/recipes/r1',
              ),
            ),
            droppedWriteSubjectProvider(gone).overrideWith(
              (ref) async => DroppedWriteSubject.unfound('plan_entry'),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Show me'));
      await tester.pumpAndSettle();
    }

    testWidgets('names each change by the thing it changed, newest first', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Didn’t sync'), findsOneWidget);
      expect(find.text('Weeknight Chicken Curry'), findsOneWidget);
      expect(find.text('recipe edit · 14:02'), findsOneWidget);
      // Not found: the kind's plain noun, and nothing to open.
      expect(find.text('A meal'), findsOneWidget);
      expect(find.text('meal change · 14:02'), findsOneWidget);
      expect(find.byIcon(FLucideIcons.chevronRight), findsOneWidget);
      // The connector's words are not on the sheet.
      expect(find.textContaining('42501'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Weeknight Chicken Curry')).dy,
        lessThan(tester.getTopLeft(find.text('A meal')).dy),
      );
    });

    testWidgets('a change opens the thing it changed', (tester) async {
      await open(tester);

      await tester.tap(find.text('Weeknight Chicken Curry'));
      await tester.pumpAndSettle();

      expect(find.text('Didn’t sync'), findsNothing);
      expect(find.text('recipe r1'), findsOneWidget);
    });

    testWidgets('Copy details carries the table, the operation and the code', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
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
      await open(tester);

      await tester.tap(find.text('Copy details'));
      await tester.pump();

      expect(copied, contains('recipe · put · r1'));
      expect(copied, contains('42501: new row violates'));
      expect(copied, contains('plan_entry · put · p9'));
      // Toasts linger on a timer; let it run out.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    });

    testWidgets('Done acknowledges the drops', (tester) async {
      await open(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.text('Didn’t sync')),
      );
      container.read(droppedWritesProvider.notifier).dropped(curry);
      expect(container.read(droppedWritesProvider), isNotEmpty);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Didn’t sync'), findsNothing);
      expect(container.read(droppedWritesProvider), isEmpty);
    });
  });

  group('the Shop line does not move the list', () {
    /// The Shop's shape: the line above the scroll, outside it, with a row to
    /// watch. Driven by a controller so a queue can be made to last.
    Widget shop(Stream<SyncHealth> health) => ProviderScope(
      overrides: [
        // ignore: scoped_providers_should_specify_dependencies, root test scope
        syncHealthProvider.overrideWith((ref) => health),
      ],
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: Column(
            children: [
              const AnsiSyncStatusLine(noun: 'tick'),
              Expanded(
                child: ListView(
                  children: const [
                    SizedBox(height: 44, child: Text('Tomatoes')),
                    SizedBox(height: 44, child: Text('Butter beans')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    /// A state, delivered and drawn. The stream reaches the provider on one
    /// pump and the widget on the next, and the grace timer starts from the
    /// second — so both pumps happen here, at no cost in elapsed time.
    Future<void> emit(
      WidgetTester tester,
      StreamController<SyncHealth> health,
      SyncHealth state,
    ) async {
      health.add(state);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a tick that uploads in a moment draws nothing at all', (
      tester,
    ) async {
      final health = StreamController<SyncHealth>();
      addTearDown(health.close);
      await tester.pumpWidget(shop(health.stream));
      await tester.pump();
      final firstRow = tester.getTopLeft(find.text('Tomatoes'));

      await emit(tester, health, const SyncWaiting(queued: 1));
      await tester.pump(const Duration(milliseconds: 200));
      // Inside the grace, so the strip never appears…
      expect(find.textContaining('waiting'), findsNothing);
      expect(tester.getTopLeft(find.text('Tomatoes')), firstRow);

      await emit(tester, health, SyncSettled(_now));
      // …and a queue nobody was shown gets no confirmation either.
      expect(find.textContaining('Synced'), findsNothing);
      expect(tester.getTopLeft(find.text('Tomatoes')), firstRow);

      await tester.pump(settledLinger + waitingGrace);
      expect(find.textContaining('Synced'), findsNothing);
      expect(tester.getTopLeft(find.text('Tomatoes')), firstRow);
    });

    testWidgets('a queue that lasts says so — in the same place, at the same '
        'height', (tester) async {
      final health = StreamController<SyncHealth>();
      addTearDown(health.close);
      await tester.pumpWidget(shop(health.stream));
      await tester.pump();
      final firstRow = tester.getTopLeft(find.text('Tomatoes'));

      await emit(tester, health, const SyncWaiting(queued: 1));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('1 tick waiting'), findsOneWidget);
      // The slot was always there: saying something does not cost the list a
      // single pixel of travel.
      expect(tester.getTopLeft(find.text('Tomatoes')), firstRow);
    });
  });
}
