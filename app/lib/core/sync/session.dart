/// The signed-in session: ties Supabase auth to PowerSync.
///
/// [SessionController] drives a state machine ([SessionState]). First sign-in
/// onboards, refreshes the token, connects, waits for first sync and caches
/// the household; a relaunch with a cached household connects offline and
/// reconciles in the background. Auth events are serialised, never dropped.
library;

import 'dart:async';

import 'package:powersync/powersync.dart' show PowerSyncDatabase;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/books/data/book_repository_impl.dart';
import 'connector.dart';
import 'database.dart';
import 'device_prefs.dart';
import 'dropped_write.dart';

part 'session.g.dart';

/// The signed-in user and the household their writes belong to.
typedef AppSession = ({String userId, String householdId});

/// Where the session machine is; the router gates on it.
sealed class SessionState {
  const SessionState();
}

/// No Supabase session — the router shows the sign-in gate.
final class SessionSignedOut extends SessionState {
  const SessionSignedOut();
}

/// Signed in; onboarding and the PowerSync connect are in flight.
final class SessionConnecting extends SessionState {
  const SessionConnecting();
}

/// Session establishment failed. The connecting screen shows [message] with
/// retry and sign-out.
final class SessionError extends SessionState {
  const SessionError(this.message, {this.accountMissing = false});

  /// [message] for the one failure retry cannot fix — see [accountMissing].
  static const accountMissingMessage =
      'This account no longer exists on the server — it was probably removed '
      'by a database reset. Sign out and sign in again.';

  final String message;

  /// The server has no such user (see [_isMissingAccount]), so retry cannot
  /// help and the connecting screen leads with sign-out. Never inferred from
  /// a network or generic server failure.
  final bool accountMissing;
}

/// Fully established: PowerSync connected and the household resolved.
final class SessionReady extends SessionState {
  const SessionReady(this.session);

  final AppSession session;
}

@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

/// Calls the idempotent `ensure_onboarded` RPC and returns the household id.
/// A provider so tests can fake the network boundary.
@Riverpod(keepAlive: true)
Future<String> Function() ensureOnboarded(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return () async =>
      (await supabase.rpc<dynamic>('ensure_onboarded')).toString();
}

/// Postgres `foreign_key_violation`, the `code` of a [PostgrestException].
const _foreignKeyViolation = '23503';

/// Whether [e] is `ensure_onboarded` refusing a user the server has dropped,
/// as a local `supabase db reset` leaves behind.
///
/// `auth.uid()` comes from the JWT unchecked, and the RPC's only foreign key
/// that can fail is `household_member.auth_user_id → auth.users`.
bool _isMissingAccount(Object e) =>
    e is PostgrestException && e.code == _foreignKeyViolation;

/// Local user-id → household-id cache, so an offline relaunch reaches the
/// Library without the onboarding RPC. Written only after a full first
/// sign-in; cleared on sign-out.
abstract interface class HouseholdCache {
  /// The household [userId] resolved to on this device, or null.
  Future<String?> read(String userId);

  /// Records [householdId] as [userId]'s household on this device.
  Future<void> write(String userId, String householdId);

  /// Forgets the cached households and everything in
  /// [DevicePrefs.sweptOnSignOut].
  Future<void> clear();
}

/// [HouseholdCache] over [SharedPreferences].
class SharedPrefsHouseholdCache implements HouseholdCache {
  static const _prefix = DevicePrefs.householdIdPrefix;

  @override
  Future<String?> read(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$userId');
  }

  @override
  Future<void> write(String userId, String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$userId', householdId);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final stale = prefs.getKeys().where(
      (k) => DevicePrefs.sweptOnSignOut.any(k.startsWith),
    );
    for (final key in stale.toList()) {
      await prefs.remove(key);
    }
  }
}

@Riverpod(keepAlive: true)
HouseholdCache householdCache(Ref ref) => SharedPrefsHouseholdCache();

@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  StreamSubscription<AuthState>? _sub;
  bool _busy = false;
  bool _hasQueued = false;
  Session? _queued;

  @override
  SessionState build() {
    final supabase = ref.watch(supabaseClientProvider);
    _sub = supabase.auth.onAuthStateChange.listen(
      (data) => _handle(data.session),
    );
    ref.onDispose(() => _sub?.cancel());
    // A restored session does not re-emit, so handle the current one after
    // build returns. Read at execution time so a stale snapshot cannot
    // clobber an auth event that lands first.
    scheduleMicrotask(() => _handle(supabase.auth.currentSession));
    return supabase.auth.currentSession == null
        ? const SessionSignedOut()
        : const SessionConnecting();
  }

  /// Serialises auth events, keeping the latest that arrives while busy.
  /// Dropping one could let a sign-out during onboarding skip
  /// [PowerSyncDatabase.disconnectAndClear].
  Future<void> _handle(Session? session) async {
    if (_busy) {
      _queued = session;
      _hasQueued = true;
      return;
    }
    _busy = true;
    try {
      await _process(session);
    } finally {
      _busy = false;
    }
    if (_hasQueued) {
      final next = _queued;
      _queued = null;
      _hasQueued = false;
      await _handle(next);
    }
  }

  Future<void> _process(Session? session) async {
    final db = ref.read(powerSyncDatabaseProvider);
    final cache = ref.read(householdCacheProvider);

    if (session == null) {
      if (state is SessionSignedOut) return;
      try {
        await db.disconnectAndClear();
        await cache.clear();
      } finally {
        // Even a failed teardown must not strand the UI behind the gate.
        state = const SessionSignedOut();
      }
      return;
    }

    final userId = session.user.id;
    if (state case SessionReady(
      session: final active,
    ) when active.userId == userId) {
      return; // already connected (e.g. a routine token refresh)
    }

    state = const SessionConnecting();
    try {
      final cached = await cache.read(userId);
      if (cached != null) {
        // Already onboarded on this device: connect without the network and
        // reconcile in the background.
        await _connect(db);
        state = SessionReady((userId: userId, householdId: cached));
        unawaited(_reconcile(userId));
        return;
      }

      final householdId = await ref.read(ensureOnboardedProvider)();
      // A fresh sign-up's token lacks the `household_id` claim the sync rules
      // bucket on, and connecting with it yields an empty first sync that
      // wipes local optimistic rows. Refresh first.
      await ref.read(supabaseClientProvider).auth.refreshSession();
      await _connect(db);
      // Let an existing household's books arrive before seeding one, so a
      // second device does not create a duplicate default book.
      await db.waitForFirstSync();
      // Built directly: `bookRepositoryProvider` reads `currentHouseholdId`,
      // which throws until this method sets the state. A failure here lands
      // as a SessionError.
      await SqliteBookRepository(
        db,
        householdId: householdId,
      ).ensureDefaultBook();
      // Cache last: the fast path skips first-sync and default-book, so it
      // must only run on a device that completed them.
      await cache.write(userId, householdId);
      state = SessionReady((userId: userId, householdId: householdId));
    } on Exception catch (e) {
      state = _isMissingAccount(e)
          ? const SessionError(
              SessionError.accountMissingMessage,
              accountMissing: true,
            )
          : SessionError('$e');
    }
  }

  Future<void> _connect(PowerSyncDatabase db) => db.connect(
    connector: AnsiConnector(
      ref.read(supabaseClientProvider),
      // The sync-health banner reads this list.
      onDropped: ref.read(droppedWritesProvider.notifier),
    ),
  );

  /// Re-runs `ensure_onboarded` behind a cached session, to heal drift.
  Future<void> _reconcile(String userId) async {
    try {
      final householdId = await ref.read(ensureOnboardedProvider)();
      await ref.read(householdCacheProvider).write(userId, householdId);
      if (state case SessionReady(
        session: final active,
      ) when active.userId == userId && active.householdId != householdId) {
        state = SessionReady((userId: userId, householdId: householdId));
      }
    } on Exception {
      // Offline or transient: the cached household stands.
    }
  }

  /// Restarts the sync connection, for the sync banner's "Try now".
  ///
  /// PowerSync stops uploading while disconnected until its own backoff
  /// reconnects. A no-op unless a session is established.
  Future<void> reconnect() async {
    if (state is! SessionReady) return;
    final db = ref.read(powerSyncDatabaseProvider);
    await db.disconnect();
    await _connect(db);
  }

  /// Re-attempts session establishment after a [SessionError].
  Future<void> retry() =>
      _handle(ref.read(supabaseClientProvider).auth.currentSession);

  /// Signs the user out; the auth-change listener tears down sync and clears
  /// local data.
  Future<void> signOut() async {
    try {
      await ref.read(supabaseClientProvider).auth.signOut();
    } on Exception {
      // The server-side revoke can fail offline; the local session is removed
      // and the signed-out event fires regardless.
    }
  }
}

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session is ready.
@Riverpod(keepAlive: true)
String currentHouseholdId(Ref ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session is! SessionReady) {
    throw StateError(
      'currentHouseholdId read before a session was established',
    );
  }
  return session.session.householdId;
}
