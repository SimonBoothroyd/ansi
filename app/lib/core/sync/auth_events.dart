/// Supabase auth's event stream, as the app listens to it. The only reader of
/// `onAuthStateChange`; `test/structure/one_auth_stream_test.dart` holds it.
///
/// gotrue reports a token refresh that could not reach the server as an
/// ERROR on that stream, not an event: it keeps the session, retries later,
/// and calls `notifyException`. Offline that fires on the refresh ticker, on
/// every resume and behind every REST, functions or storage call with an
/// expired token, and the stream replays past errors to late listeners. A
/// listener without `onError` hands each one to the zone, which shows the
/// crash toast for what is only "offline".
///
/// [authEvents] drops an [AuthRetryableFetchException] with a [CrashSink.note]
/// and reports any other error to [CrashSink.report]; no error reaches the
/// listener. Events pass through unchanged. A revoked or expired session is
/// never hidden: gotrue signals it as a `signedOut` event, not an error.
library;

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../observability/crash_sink.dart';

/// [auth]'s auth events, with its errors routed to [crashes] instead of the
/// listener.
Stream<AuthState> authEvents(GoTrueClient auth, CrashSink crashes) =>
    auth.onAuthStateChange.transform(
      StreamTransformer.fromHandlers(
        handleError: (error, stack, _) => error is AuthRetryableFetchException
            ? crashes.note(error, stack)
            : crashes.report(error, stack),
      ),
    );
