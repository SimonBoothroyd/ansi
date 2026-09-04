/// The signed-in session: what ties auth to sync.
///
/// [SessionController] listens to Supabase auth changes and drives PowerSync
/// through a small state machine ([SessionState]):
///
/// - First sign-in on a device (no cached household): onboard via the
///   idempotent `ensure_onboarded` RPC, **re-issue the access token** so it
///   carries the `household_id` claim the sync rules bucket on — a token
///   issued at sign-up predates the membership, and connecting with it yields
///   an empty first sync that wipes the local optimistic rows (the
///   `add_household_claim` hook only stamps the claim on tokens issued after
///   onboarding; see `scripts/smoke_auth.sh` step 3). Then connect, wait for
///   the first sync, ensure a default book, cache the household id and publish
///   [SessionReady].
/// - Relaunch with a cached household: connect immediately — the app is
///   offline-first, so no network round-trip gates the Library — and reconcile
///   with `ensure_onboarded` in the background.
/// - Sign-out: disconnect, clear the local database and the cached household.
/// - Any failure surfaces as [SessionError]; the connecting screen offers
///   retry and sign-out instead of an infinite spinner. One failure is
///   singled out — a user the server no longer has
///   ([SessionError.accountMissing]) — because retry can only ever fail again.
///
/// Auth events that arrive while one is being handled are never dropped: the
/// latest is queued and processed after the current one, so a sign-out during
/// onboarding still tears down and clears local data (shared-device safety).
///
/// [currentHouseholdId] exposes the resolved household id to repositories,
/// which stamp it on each row they write. Only read behind the auth gate (the
/// router redirect), so reading it without a [SessionReady] is a programming
/// error.
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

/// Where the session machine is: the router gates on it and the connecting
/// screen renders it.
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

/// Session establishment failed (e.g. no network on a fresh device, RPC
/// error). The connecting screen shows [message] with retry and sign-out.
final class SessionError extends SessionState {
  const SessionError(this.message, {this.accountMissing = false});

  /// [message] for the one failure retry cannot fix — see [accountMissing].
  static const accountMissingMessage =
      'This account no longer exists on the server — it was probably removed '
      'by a database reset. Sign out and sign in again.';

  final String message;

  /// The server has no such user: onboarding was refused because the signed-in
  /// account is gone (a local `supabase db reset` drops `auth.users` while the
  /// device keeps a still-valid JWT — see [_isMissingAccount]).
  ///
  /// Retrying cannot help until the token expires; the connecting screen leads
  /// with sign-out instead. Never inferred from a network or generic server
  /// failure, which would mask a real outage behind a bogus "sign out".
  final bool accountMissing;
}

/// Fully established: PowerSync connected and the household resolved.
final class SessionReady extends SessionState {
  const SessionReady(this.session);

  final AppSession session;
}

@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

/// Calls the idempotent `ensure_onboarded` RPC (migration 0007) and returns
/// the household id. A provider so [SessionController] tests can fake the
/// network boundary.
@Riverpod(keepAlive: true)
Future<String> Function() ensureOnboarded(Ref ref) {
  final supabase = ref.watch(supabaseClientProvider);
  return () async =>
      (await supabase.rpc<dynamic>('ensure_onboarded')).toString();
}

/// Postgres `foreign_key_violation`, which PostgREST passes through as the
/// error body's `code` (and postgrest-dart lifts into [PostgrestException]).
const _foreignKeyViolation = '23503';

/// Whether [e] is `ensure_onboarded` refusing to onboard a user the server no
/// longer has — the "ghost user" a local `supabase db reset` leaves behind.
///
/// `auth.uid()` is read out of the JWT and never checked against the table, so
/// a device holding a token minted before the reset still reaches the RPC's
/// last statement — `insert into household_member (…, auth_user_id, …)`, whose
/// column is `references auth.users(id)` (migration 0001). That insert is the
/// only foreign key the RPC can fail: every other one it writes (the household
/// it just created, the vocab it just cloned) is inserted in the same
/// transaction. A 23503 from here therefore means exactly one thing.
bool _isMissingAccount(Object e) =>
    e is PostgrestException && e.code == _foreignKeyViolation;

/// Local user-id → household-id cache, so a signed-in relaunch reaches the
/// Library without awaiting the onboarding RPC (offline-first: an offline
/// relaunch must not dead-end on the network).
///
/// Written only after a device completes the full first-sign-in pipeline;
/// cleared on sign-out alongside the local database.
abstract interface class HouseholdCache {
  /// The household this user resolved to on this device, or null if the
  /// device never completed onboarding for them.
  Future<String?> read(String userId);

  /// Records [householdId] as [userId]'s household on this device.
  Future<void> write(String userId, String householdId);

  /// Forgets every device-local preference this app wrote — the cached
  /// households and everything else in [DevicePrefs.sweptOnSignOut] (sign-out).
  ///
  /// Leaving one household's folded books behind for the device's next user is
  /// untidy rather than unsafe, but sign-out is the one moment it costs nothing
  /// to be tidy.
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
    // A restored session (relaunch while signed in) won't re-emit, so handle
    // the current one — after build returns, since `state` isn't set before.
    // Read at execution time, not captured: an auth event that lands first
    // must not be clobbered by a stale snapshot.
    scheduleMicrotask(() => _handle(supabase.auth.currentSession));
    return supabase.auth.currentSession == null
        ? const SessionSignedOut()
        : const SessionConnecting();
  }

  /// Serialises auth events: one at a time, keeping the latest that arrives
  /// while busy. (Dropping instead would let a sign-out that lands during
  /// onboarding skip [PowerSyncDatabase.disconnectAndClear] — leaking this
  /// household's data to the device's next user.)
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
        // This device already onboarded this user: connect straight away (no
        // network needed) and reconcile with the server opportunistically.
        await _connect(db);
        state = SessionReady((userId: userId, householdId: cached));
        unawaited(_reconcile(userId));
        return;
      }

      final householdId = await ref.read(ensureOnboardedProvider)();
      // The current access token may predate the membership just ensured (a
      // fresh sign-up), so it lacks the `household_id` claim the sync rules
      // bucket on — connecting with it yields an EMPTY first sync that wipes
      // the local optimistic rows. Re-issue the token first; the connector
      // reads `currentSession`, so a refresh is all it takes.
      await ref.read(supabaseClientProvider).auth.refreshSession();
      await _connect(db);
      // Let an existing household's books arrive before we seed one, so a
      // second device doesn't create a duplicate default book.
      await db.waitForFirstSync();
      // The one place core builds a feature's repository itself, and the one
      // repository write that does not go through the door in
      // `shared/write.dart`. `bookRepositoryProvider` reads
      // `currentHouseholdId`, which is derived from the very state this
      // method is computing and throws until it is set — and a failure here
      // must land on the connecting screen as a SessionError, which is where
      // the door would have sent it anyway.
      await SqliteBookRepository(
        db,
        householdId: householdId,
      ).ensureDefaultBook();
      // Cache last: the fast path above skips first-sync + default-book, so
      // it must only run on a device that completed them once.
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
      // The refused-and-discarded write finally has somewhere to be heard:
      // the sync-health banner reads this list (core/sync/sync_health.dart).
      onDropped: ref.read(droppedWritesProvider.notifier),
    ),
  );

  /// Re-runs `ensure_onboarded` behind an already-published cached session, to
  /// heal drift (e.g. the household changed server-side).
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
      // Offline or transient: the cached household stands; a later launch
      // reconciles.
    }
  }

  /// Restarts the sync connection — what the sync banner's "Try now" does.
  ///
  /// PowerSync backs off on its own and, while disconnected, breaks out of the
  /// upload loop entirely until the sync stream reconnects. That is correct for
  /// a sync engine and useless to someone who has just walked out of a
  /// basement, which is the whole reason this button exists.
  ///
  /// A no-op unless a session is established: there is nothing to reconnect.
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
      // The server-side token revoke can fail offline; the local session is
      // removed and the signed-out event fires regardless, which is what the
      // teardown keys off.
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
