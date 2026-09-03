/// The words the four sync states are allowed to say, and the mechanical proof
/// that the Library and the Shop list read the same one.
///
/// This is product copy the owner ruled on, so it is pinned here rather than
/// left to a reviewer's memory. Two words must never appear: **"offline"**
/// (being offline is not a state this app reports) and **"failed"**.
library;

import 'package:ansi/core/sync/dropped_write.dart';
import 'package:ansi/core/sync/sync_health.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/sync_banner.dart';
import 'package:ansi/shared/sync_health_row.dart';
import 'package:ansi/shared/sync_status_line.dart';
import 'package:ansi/shared/sync_words.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _now = DateTime(2026, 9, 2, 14, 30);
final _since = DateTime(2026, 9, 2, 14, 2);

DroppedWrite _drop() => DroppedWrite(
  table: 'recipe',
  op: 'put',
  rowId: 'r1',
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
      expect(
        find.text(
          '7 changes have been waiting since 14:02. Ansi keeps trying.',
        ),
        findsOneWidget,
      );
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

      expect(
        find.text('One change couldn’t be saved to the server.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'A recipe edit from 14:02 was refused and won’t sync. '
          'It’s still on this phone.',
        ),
        findsOneWidget,
      );
      expect(find.text('What happened'), findsOneWidget);
      // The banner said it. The status line does not say it again.
      expect(find.textContaining('ticks'), findsNothing);
    });

    testWidgets('"What happened" names the table, the operation and the code', (
      tester,
    ) async {
      await tester.pumpWidget(_bothReadouts(SyncRefused([_drop()])));
      await tester.pump();

      await tester.tap(find.text('What happened'));
      await tester.pumpAndSettle();

      expect(find.textContaining('recipe · put · r1'), findsOneWidget);
      expect(find.textContaining('42501'), findsOneWidget);
    });
  });
}
