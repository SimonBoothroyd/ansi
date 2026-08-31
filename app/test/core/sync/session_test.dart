/// Unit tests for [SessionController]'s state machine, with every network /
/// database boundary faked (the mocking style follows connector_test.dart):
///
/// - fresh onboarding re-issues the access token BEFORE PowerSync connects
///   (the sign-up token lacks the `household_id` claim, so connecting with it
///   yields an empty first sync that wipes local rows);
/// - a cached household connects offline without awaiting the network RPC;
/// - failures surface as [SessionError] and retry() recovers, with a
///   server-side-deleted account ([SessionError.accountMissing]) told apart
///   from every other server error;
/// - auth events arriving mid-handle are queued (latest wins), so a sign-out
///   during onboarding still clears local data.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/core/sync/database.dart';
import 'package:mise/core/sync/session.dart';
import 'package:mocktail/mocktail.dart';
import 'package:powersync/powersync.dart';
import 'package:sqlite3/common.dart' show ResultSet, Row;
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabase extends Mock implements SupabaseClient {}

class _MockAuth extends Mock implements GoTrueClient {}

/// Records the PowerSync calls the controller makes; implements just enough of
/// the query surface for the book repository's `ensureDefaultBook`
/// (getOptional finds an existing book, execute adopts orphan recipes).
class _FakeDb extends Fake implements PowerSyncDatabase {
  _FakeDb(this.log);

  final List<String> log;

  @override
  Future<void> connect({
    required PowerSyncBackendConnector connector,
    SyncOptions? options,
    Duration? crudThrottleTime,
    Map<String, dynamic>? params,
  }) async {
    log.add('connect');
  }

  @override
  Future<void> waitForFirstSync({StreamPriority? priority}) async {
    log.add('waitForFirstSync');
  }

  @override
  Future<void> disconnectAndClear({bool clearLocal = true}) async {
    log.add('disconnectAndClear');
  }

  @override
  Future<Row?> getOptional(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    log.add('ensureDefaultBook');
    return ResultSet(
      ['id', 'name'],
      null,
      [
        ['b1', 'Our Cookbook'],
      ],
    ).first;
  }

  @override
  Future<ResultSet> execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) async {
    return ResultSet([], [], []);
  }
}

class _MemoryCache implements HouseholdCache {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String userId) async => values[userId];

  @override
  Future<void> write(String userId, String householdId) async {
    values[userId] = householdId;
  }

  @override
  Future<void> clear() async => values.clear();
}

Session _session(String userId) => Session(
  accessToken: 'token-$userId',
  tokenType: 'bearer',
  user: User(
    id: userId,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

/// Drains the microtask/event queue so the controller's async pipeline runs to
/// completion.
Future<void> _settle() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _MockSupabase supabase;
  late _MockAuth auth;
  late StreamController<AuthState> authEvents;
  late _FakeDb db;
  late _MemoryCache cache;
  late List<String> log;
  late Future<String> Function() onboard;

  setUp(() {
    supabase = _MockSupabase();
    auth = _MockAuth();
    authEvents = StreamController<AuthState>.broadcast(sync: true);
    log = [];
    db = _FakeDb(log);
    cache = _MemoryCache();
    onboard = () async {
      log.add('rpc');
      return 'hh-1';
    };

    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange).thenAnswer((_) => authEvents.stream);
    when(() => auth.currentSession).thenReturn(null);
    when(() => auth.refreshSession()).thenAnswer((_) async {
      log.add('refresh');
      return AuthResponse();
    });
  });

  tearDown(() => authEvents.close());

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(supabase),
        powerSyncDatabaseProvider.overrideWithValue(db),
        householdCacheProvider.overrideWithValue(cache),
        ensureOnboardedProvider.overrideWithValue(() => onboard()),
      ],
    );
    addTearDown(c.dispose);
    // Activate the controller so it subscribes to auth changes (the app does
    // this once in MiseApp).
    c.read(sessionControllerProvider);
    return c;
  }

  void signIn(String userId) {
    final session = _session(userId);
    when(() => auth.currentSession).thenReturn(session);
    authEvents.add(AuthState(AuthChangeEvent.signedIn, session));
  }

  void signOutEvent() {
    when(() => auth.currentSession).thenReturn(null);
    authEvents.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  group('fresh onboarding (no cached household)', () {
    test('onboards, re-issues the token BEFORE connect, caches', () async {
      final c = container();
      expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());

      signIn('u1');
      await _settle();

      expect(
        log,
        ['rpc', 'refresh', 'connect', 'waitForFirstSync', 'ensureDefaultBook'],
        reason:
            'the token must be re-issued (with the household_id claim) '
            'before PowerSync connects, or the first sync comes back empty',
      );
      expect(
        c.read(sessionControllerProvider),
        isA<SessionReady>().having((s) => s.session, 'session', (
          userId: 'u1',
          householdId: 'hh-1',
        )),
      );
      expect(cache.values, {'u1': 'hh-1'});
      expect(c.read(currentHouseholdIdProvider), 'hh-1');
    });

    test('a failure surfaces as SessionError and retry() recovers', () async {
      onboard = () async => throw Exception('network down');
      final c = container();

      signIn('u1');
      await _settle();

      expect(
        c.read(sessionControllerProvider),
        isA<SessionError>().having(
          (s) => s.message,
          'message',
          contains('network down'),
        ),
      );
      expect(log, isNot(contains('connect')));
      expect(cache.values, isEmpty, reason: 'a failed onboard must not cache');

      onboard = () async => 'hh-1';
      await c.read(sessionControllerProvider.notifier).retry();
      await _settle();

      expect(c.read(sessionControllerProvider), isA<SessionReady>());
      expect(cache.values, {'u1': 'hh-1'});
    });

    test(
      'a deleted account is called out, not left as a generic error',
      () async {
        // What a ghost user (JWT outliving a `supabase db reset`) gets back:
        // `ensure_onboarded`'s household_member insert trips the auth.users FK,
        // and PostgREST passes the SQLSTATE through as `code`.
        onboard = () async => throw const PostgrestException(
          message:
              'insert or update on table "household_member" violates foreign '
              'key constraint "household_member_auth_user_id_fkey"',
          code: '23503',
          details: 'Key (auth_user_id)=(u1) is not present in table "users".',
        );
        final c = container();

        signIn('u1');
        await _settle();

        expect(
          c.read(sessionControllerProvider),
          isA<SessionError>()
              .having((s) => s.accountMissing, 'accountMissing', isTrue)
              .having(
                (s) => s.message,
                'message',
                SessionError.accountMissingMessage,
              ),
        );
        expect(cache.values, isEmpty);
      },
    );

    test('other server errors stay generic', () async {
      // Not the FK: a 5xx-ish RPC failure is a real server problem, and
      // telling the user to sign out would mask it.
      onboard = () async => throw const PostgrestException(
        message: 'canceling statement due to statement timeout',
        code: '57014',
      );
      final c = container();

      signIn('u1');
      await _settle();

      expect(
        c.read(sessionControllerProvider),
        isA<SessionError>()
            .having((s) => s.accountMissing, 'accountMissing', isFalse)
            .having((s) => s.message, 'message', contains('statement timeout')),
      );
    });
  });

  group('cached household (relaunch)', () {
    test('connects offline without awaiting the network RPC', () async {
      cache.values['u1'] = 'hh-9';
      onboard = () async => throw Exception('offline');
      when(() => auth.currentSession).thenReturn(_session('u1'));

      final c = container();
      expect(c.read(sessionControllerProvider), isA<SessionConnecting>());
      await _settle();

      expect(
        c.read(sessionControllerProvider),
        isA<SessionReady>().having((s) => s.session, 'session', (
          userId: 'u1',
          householdId: 'hh-9',
        )),
      );
      expect(log, contains('connect'));
      // The fast path must not gate on first sync (nothing to wait for
      // offline) nor re-seed the default book.
      expect(log, isNot(contains('waitForFirstSync')));
      expect(log, isNot(contains('ensureDefaultBook')));
    });

    test('background reconcile heals a drifted household id', () async {
      cache.values['u1'] = 'hh-stale';
      onboard = () async => 'hh-1';
      when(() => auth.currentSession).thenReturn(_session('u1'));

      final c = container();
      await _settle();

      expect(
        c.read(sessionControllerProvider),
        isA<SessionReady>().having(
          (s) => s.session.householdId,
          'householdId',
          'hh-1',
        ),
      );
      expect(cache.values, {'u1': 'hh-1'});
    });
  });

  group('sign-out', () {
    test('tears down sync and clears the cached household', () async {
      final c = container();
      signIn('u1');
      await _settle();
      expect(c.read(sessionControllerProvider), isA<SessionReady>());

      signOutEvent();
      await _settle();

      expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
      expect(log, contains('disconnectAndClear'));
      expect(cache.values, isEmpty);
    });

    test('a sign-out landing mid-onboarding is queued, not dropped', () async {
      final gate = Completer<String>();
      onboard = () {
        log.add('rpc');
        return gate.future;
      };
      final c = container();

      signIn('u1');
      await _settle();
      expect(log, ['rpc'], reason: 'onboarding is parked on the RPC');

      // The user signs out while the handler is still busy: the event must be
      // queued and processed afterwards, or local data leaks to the device's
      // next user.
      signOutEvent();
      await _settle();
      expect(log, isNot(contains('disconnectAndClear')));

      gate.complete('hh-1');
      await _settle();

      expect(c.read(sessionControllerProvider), isA<SessionSignedOut>());
      expect(log, contains('disconnectAndClear'));
      expect(cache.values, isEmpty);
    });
  });
}
