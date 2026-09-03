/// The stack under one smoke file: a fresh household on the local Supabase, a
/// Supabase client holding an in-memory session, and a throwaway PowerSync
/// database the app is booted over.
///
/// Every file starts its own [SmokeStack] in `setUpAll` — its OWN household,
/// so the files are independent of each other and of whatever an earlier run
/// left on the shared local backend (parallel lanes on separate simulators
/// never collide) — and signs in programmatically. The one exception is the
/// auth file, whose subject is the gate itself: it starts the stack signed out
/// and drives the sign-in form.
///
/// Provisioning is plain HTTP (sign-up + `ensure_onboarded`, the same calls
/// as `scripts/smoke_auth.sh`) so the app can SIGN IN to an already-onboarded
/// account. In-app sign-UP is not exercised on the sim — the session
/// controller's post-onboarding `refreshSession()` makes it work (verified
/// manually on device, 7.4 sweep), but provisioning over HTTP keeps each
/// run's users deterministic and the files focused on the signed-in app.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/app.dart';
import 'package:ansi/core/config/env.dart';
import 'package:ansi/core/sync/database.dart';
import 'package:ansi/core/sync/schema.dart';
import 'package:ansi/core/sync/session.dart' show currentHouseholdIdProvider;
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/data/import_repository_impl.dart';
import 'package:ansi/features/ingredients/barcode/barcode_add.dart'
    show OffLookup, offLookupProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../off_fixture.dart';
import 'drive.dart';

/// The password every provisioned smoke user is created with.
const smokePassword = 'smoke-password-123';

class SmokeStack {
  SmokeStack._({
    required this.db,
    required Directory dir,
    required this.email,
    required this.householdId,
  }) : _dir = dir;

  /// Provisions a fresh two-person household, initializes Supabase with
  /// in-memory auth, signs in as its first member ("Ada") unless [signIn] is
  /// false, and opens the throwaway database. Call once per file, in
  /// `setUpAll`; [dispose] in `tearDownAll`.
  static Future<SmokeStack> start({bool signIn = true}) async {
    expect(
      Env.isConfigured,
      isTrue,
      reason: 'run via `make test-sim` so the --dart-defines are set',
    );
    final household = await _provisionHousehold();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // The local stack issues a legacy anon JWT (mirrors bootstrap.dart).
      // ignore: deprecated_member_use
      anonKey: Env.supabaseAnonKey,
      // No persisted auth: the simulator can hold a session from an earlier
      // `make run` whose user a later `db reset` deleted — its JWT stays
      // validly signed for up to an hour and would drive the app as a ghost
      // user. In-memory-only sessions make every file start signed out and
      // sign in as its own provisioned user.
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
    if (signIn) {
      // The session controller reads `currentSession` when it builds, so a
      // client signed in before the app is pumped lands on /connecting and
      // then the Library without the gate — the gate is the auth file's
      // subject, not every file's tax.
      await Supabase.instance.client.auth.signInWithPassword(
        email: household.email,
        password: smokePassword,
      );
    }
    // A throwaway database rather than the app's own file, so a rerun starts
    // empty and everything a file asserts arrived through this run's sync.
    final dir = Directory.systemTemp.createTempSync('ansi_smoke');
    final db = PowerSyncDatabase(schema: schema, path: '${dir.path}/smoke.db');
    await db.initialize();
    return SmokeStack._(
      db: db,
      dir: dir,
      email: household.email,
      householdId: household.id,
    );
  }

  /// The throwaway local database the app runs over — read it to assert what
  /// landed, and write it through the app's own repositories to seed a
  /// file's prerequisites.
  final PowerSyncDatabase db;
  final Directory _dir;

  /// The provisioned user the app signs in as ("Ada").
  final String email;

  /// The household `ensure_onboarded` put Ada in — what a repository built
  /// over [db] stamps on the rows it writes.
  final String householdId;

  /// The URL the real [OffLookup] built for the last barcode lookup, captured
  /// by [openLibraryWithOffFixture]'s mock transport so a test can prove the
  /// typed digits reached it.
  Uri? offRequestUrl;

  Future<void> dispose() async {
    await db.close();
    _dir.deleteSync(recursive: true);
  }

  /// Builds the app over the throwaway database, with any extra provider
  /// [overrides] a file needs.
  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          powerSyncDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const AnsiApp(),
      ),
    );
    await tester.pump();
  }

  /// Launches the app already signed in and waits out /connecting until the
  /// Library renders.
  Future<void> openLibrary(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await pumpApp(tester, overrides: overrides);
    await pumpUntilFound(
      tester,
      find.text('Our Cookbook'),
      timeout: const Duration(seconds: 60),
    );
    await tester.pumpAndSettle();
  }

  /// [openLibrary], but with the import repository swapped for the LOCAL one —
  /// `SqliteImportRepository`, exactly what `importRepositoryProvider` builds
  /// when Supabase is unconfigured. It is the fake edge function: it returns
  /// the canned payload and re-resolves its candidates against the household's
  /// really-synced vocab. Nothing on the import path touches the network or a
  /// provider key; every other collaborator stays real.
  Future<void> openLibraryWithLocalImport(WidgetTester tester) => openLibrary(
    tester,
    overrides: [
      importRepositoryProvider.overrideWith(
        (Ref ref) => SqliteImportRepository(
          ref.watch(databaseProvider),
          householdId: ref.watch(currentHouseholdIdProvider),
        ),
      ),
    ],
  );

  /// [openLibrary], but with the Open Food Facts client's SOCKET swapped for a
  /// `MockClient` serving the committed Nutella fixture.
  ///
  /// Only the transport is fake. The real [OffLookup] still normalizes the
  /// barcode, builds the URL, sends the `fields=` projection and classifies
  /// the status; the real mapper still turns the payload into a draft. This is
  /// the same shape as [openLibraryWithLocalImport] — one provider overridden,
  /// every other collaborator real — and it is the reason `offLookupProvider`
  /// exists: the scan sheet is opened from inside a navigation stack that no
  /// caller can thread a parameter through.
  Future<void> openLibraryWithOffFixture(WidgetTester tester) => openLibrary(
    tester,
    overrides: [
      offLookupProvider.overrideWithValue(
        OffLookup(
          client: MockClient((request) async {
            offRequestUrl = request.url;
            return http.Response(
              offNutellaFixtureJson,
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ),
    ],
  );

  /// Waits until every queued local write has uploaded, then pumps a little
  /// real time so the server's round-trip streams back down over the local
  /// rows. Asserts made after this run against round-tripped data — exactly
  /// where the old connector jsonb/tombstone bugs corrupted rows (within ~a
  /// second of the save).
  Future<void> waitForSyncRoundTrip(WidgetTester tester) async {
    await waitForDb(
      tester,
      () async => (await db.getUploadQueueStats()).count == 0,
      'the upload queue to drain',
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

// -----------------------------------------------------------------------------
// Provisioning — plain HTTP against the local Supabase (mirrors
// scripts/smoke_auth.sh). In-app sign-up is not used: see the library doc.
// -----------------------------------------------------------------------------

typedef _Household = ({String email, String id});

/// Creates a fresh two-person household ("Ada" + "Jun") and returns Ada's
/// email with the household's id. `ensure_onboarded` joins ANY household with
/// room before creating one, so stray one-member households left by earlier
/// runs are filled with plug users until a sign-up lands in a genuinely fresh
/// (and therefore clean) household; the partner then deterministically joins
/// it.
Future<_Household> _provisionHousehold() async {
  for (var attempt = 0; attempt < 8; attempt++) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // NOTE: example.com is on the cloud blocklist — use the app's own domain.
    final email = 'smoke$stamp.ada@ansi.app';
    final token = await _signUp(email, fullName: 'Ada');
    final household = await _ensureOnboarded(token);
    if (await _memberCount(token, household) > 1) continue; // filled a stray
    final partnerToken = await _signUp(
      'smoke$stamp.jun@ansi.app',
      fullName: 'Jun',
    );
    final partnerHousehold = await _ensureOnboarded(partnerToken);
    if (partnerHousehold != household) {
      throw StateError(
        'partner landed in $partnerHousehold, not $household — '
        'another client raced the provisioning?',
      );
    }
    return (email: email, id: household);
  }
  throw StateError('no fresh household after 8 sign-ups — too many strays?');
}

Future<String> _signUp(String email, {required String fullName}) async {
  final body = await _post('/auth/v1/signup', {
    'email': email,
    'password': smokePassword,
    'data': {'full_name': fullName},
  });
  final token = (body as Map)['access_token'] as String?;
  if (token == null) {
    throw StateError(
      'sign-up returned no access token (email confirmations on?): $body',
    );
  }
  return token;
}

Future<String> _ensureOnboarded(String token) async =>
    await _post('/rest/v1/rpc/ensure_onboarded', {}, bearer: token) as String;

Future<int> _memberCount(String token, String householdId) async {
  final body = await _get(
    '/rest/v1/household_member?select=id'
    '&household_id=eq.$householdId&deleted_at=is.null',
    bearer: token,
  );
  return (body as List).length;
}

Future<dynamic> _post(
  String path,
  Map<String, dynamic> body, {
  String? bearer,
}) => _request('POST', path, body: body, bearer: bearer);

Future<dynamic> _get(String path, {String? bearer}) =>
    _request('GET', path, bearer: bearer);

Future<dynamic> _request(
  String method,
  String path, {
  Map<String, dynamic>? body,
  String? bearer,
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('${Env.supabaseUrl}$path'),
    );
    req.headers
      ..set('apikey', Env.supabaseAnonKey)
      ..contentType = ContentType.json;
    if (bearer != null) req.headers.set('Authorization', 'Bearer $bearer');
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    if (res.statusCode >= 400) {
      throw StateError('$method $path → ${res.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  } finally {
    client.close();
  }
}
