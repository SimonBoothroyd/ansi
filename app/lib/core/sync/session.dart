/// The signed-in session: what ties auth to sync.
///
/// [SessionController] listens to Supabase auth changes and drives PowerSync:
/// on sign-in it onboards the user (idempotent `ensure_onboarded` RPC → the
/// household id, migration 0007), connects PowerSync with the [MiseConnector],
/// waits for the first sync, ensures a default book, and publishes the
/// [AppSession]. On sign-out it disconnects and clears the local database.
///
/// [currentHouseholdId] exposes the resolved household id to repositories,
/// which stamp it on each row they write. Only read behind the auth gate (the
/// router redirect), so a null session there is a programming error.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/books/data/book_repository_impl.dart';
import 'connector.dart';
import 'database.dart';

part 'session.g.dart';

/// The signed-in user and the household their writes belong to.
typedef AppSession = ({String userId, String householdId});

@Riverpod(keepAlive: true)
SupabaseClient supabaseClient(Ref ref) => Supabase.instance.client;

@Riverpod(keepAlive: true)
class SessionController extends _$SessionController {
  StreamSubscription<AuthState>? _sub;
  bool _busy = false;

  @override
  AppSession? build() {
    final supabase = ref.watch(supabaseClientProvider);
    _sub = supabase.auth.onAuthStateChange.listen(
      (data) => _handle(data.session),
    );
    ref.onDispose(() => _sub?.cancel());
    // A restored session (relaunch while signed in) won't re-emit, so handle
    // the current one directly.
    _handle(supabase.auth.currentSession);
    return null;
  }

  Future<void> _handle(Session? session) async {
    if (_busy) return;
    _busy = true;
    try {
      final supabase = ref.read(supabaseClientProvider);
      final db = ref.read(powerSyncDatabaseProvider);

      if (session == null) {
        if (state != null) {
          await db.disconnectAndClear();
          state = null;
        }
        return;
      }
      if (state?.userId == session.user.id) return; // already connected

      final householdId = (await supabase.rpc<dynamic>(
        'ensure_onboarded',
      )).toString();
      await db.connect(connector: MiseConnector(supabase));
      // Let an existing household's books arrive before we seed one, so a
      // second device doesn't create a duplicate default book.
      await db.waitForFirstSync();
      await SqliteBookRepository(
        db,
        householdId: householdId,
      ).ensureDefaultBook();
      state = (userId: session.user.id, householdId: householdId);
    } finally {
      _busy = false;
    }
  }

  /// Signs the user out; the auth-change listener tears down sync.
  Future<void> signOut() => ref.read(supabaseClientProvider).auth.signOut();
}

/// The household every repository write is scoped to. Read only behind the auth
/// gate — throws before a session exists.
@Riverpod(keepAlive: true)
String currentHouseholdId(Ref ref) {
  final session = ref.watch(sessionControllerProvider);
  if (session == null) {
    throw StateError(
      'currentHouseholdId read before a session was established',
    );
  }
  return session.householdId;
}
