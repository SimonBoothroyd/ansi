/// The shared error state and the mapping behind its reason line.
///
/// The point of both is that a screen which failed to load says three things —
/// what, why, and what now — instead of the six-times-repeated shrug they
/// replace.
library;

import 'dart:async';
import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_error_state.dart';
import 'package:ansi/shared/describe_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:supabase_flutter/supabase_flutter.dart';

Widget _host(Widget child) => MaterialApp(
  home: FTheme(data: ansiThemeData(), child: child),
);

void main() {
  group('describeFailure', () {
    test('a PostgREST error speaks in the server’s own words', () {
      expect(
        describeFailure(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ),
        'new row violates row-level security policy',
      );
    });

    test('a timeout says what the server did, not what the class is', () {
      expect(
        describeFailure(TimeoutException('x')),
        'the server didn’t answer in time',
      );
    });

    test('an unreachable server is one sentence for both its shapes', () {
      const expected = 'couldn’t reach the server';
      expect(describeFailure(const SocketException('x')), expected);
      expect(describeFailure(ClientException('x')), expected);
    });

    test('a browser never throws a SocketException, and its own shape reads '
        'the same', () {
      // Verbatim what package:http's BrowserClient raises for a failed fetch —
      // offline, DNS, CORS and mixed content all arrive as this one string,
      // and on the web it is the ONLY network failure describeFailure sees.
      expect(
        describeFailure(
          ClientException(
            'XMLHttpRequest error.',
            Uri.parse('https://example.supabase.co/rest/v1/ingredient'),
          ),
        ),
        'couldn’t reach the server',
      );
    });

    test('a local database failure says it is the phone, not the network', () {
      expect(
        describeFailure(SqliteException(1, 'disk I/O error')),
        contains('this is on the phone, not the network'),
      );
    });

    test('anything unrecognised is honest about being unrecognised', () {
      expect(describeFailure(Object()), 'an unexpected problem');
    });

    test('the raw text survives, for the clipboard', () {
      final details = failureDetails(StateError('boom'), StackTrace.empty);
      expect(details, contains('boom'));
      expect(details, contains('StateError'));
    });
  });

  group('AnsiErrorState', () {
    testWidgets('says what, why and what now — in that order', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _host(
          AnsiErrorState(
            what: 'the week',
            error: TimeoutException('x'),
            onRetry: () => retried++,
          ),
        ),
      );

      expect(find.text('Couldn’t load the week.'), findsOneWidget);
      expect(find.text('the server didn’t answer in time'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Copy details'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    });

    testWidgets('never shows the exception’s own toString()', (tester) async {
      await tester.pumpWidget(
        _host(
          const AnsiErrorState(
            what: 'the library',
            error: SocketException('Connection refused (errno 61)'),
          ),
        ),
      );

      expect(find.textContaining('errno'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);
      expect(find.text('couldn’t reach the server'), findsOneWidget);
      // No retry offered means no button pretending one exists.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('the compact form fits one line beside what it reports on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AnsiErrorState(
            compact: true,
            what: 'the measures',
            error: TimeoutException('x'),
            onRetry: () {},
          ),
        ),
      );

      expect(
        find.text(
          'Couldn’t load the measures — the server didn’t answer '
          'in time',
        ),
        findsOneWidget,
      );
    });
  });
}
