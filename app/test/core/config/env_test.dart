import 'package:ansi/core/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real defines are compile-time constants, so the guard is exercised over
/// an explicit map — the same one [Env.assertDefinesUsable] passes it.
Map<String, String> _defines({
  String url = '',
  String anonKey = '',
  String powersync = '',
}) => {
  'SUPABASE_URL': url,
  'SUPABASE_ANON_KEY': anonKey,
  'POWERSYNC_URL': powersync,
};

void main() {
  group('blank --dart-define guard', () {
    test('all blank is local/dev mode, not an error', () {
      expect(() => checkDefines(_defines()), returnsNormally);
    });

    test('all set passes', () {
      expect(
        () => checkDefines(
          _defines(
            url: 'http://127.0.0.1:54321',
            anonKey: 'ey.anon',
            powersync: 'http://127.0.0.1:8080',
          ),
        ),
        returnsNormally,
      );
    });

    test('one blank define throws, naming it and the flag to fix', () {
      // The live failure: a real URL with an empty key built and "initialised"
      // fine, then bounced OAuth with "No API key found in request".
      expect(
        () => checkDefines(
          _defines(url: 'http://127.0.0.1:54321', powersync: 'http://ps'),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('SUPABASE_ANON_KEY is empty'),
              contains('--dart-define'),
              isNot(contains('SUPABASE_URL is')),
            ),
          ),
        ),
      );
    });

    test('a whitespace-only define counts as blank', () {
      expect(
        () => checkDefines(
          _defines(
            url: 'http://127.0.0.1:54321',
            anonKey: '  ',
            powersync: 'p',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('several blanks are all named, so one restart fixes the lot', () {
      expect(
        () => checkDefines(_defines(url: 'http://127.0.0.1:54321')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('SUPABASE_ANON_KEY, POWERSYNC_URL are empty'),
          ),
        ),
      );
    });
  });

  test('the unconfigured host test run stays in local/dev mode', () {
    // `flutter test` passes no --dart-define; the import feature's canned
    // fallback and every widget test depend on this staying false.
    expect(Env.isConfigured, isFalse);
    expect(Env.assertDefinesUsable, returnsNormally);
  });
}
