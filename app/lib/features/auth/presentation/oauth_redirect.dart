/// Where Google sends the sign-in back to, on each platform.
///
/// On a phone the answer is a custom scheme the OS routes back to the app; in
/// a browser there is no such thing — a `io.ansi.app://…` redirect dead-ends
/// on a page the browser cannot open — so the answer is the deployed page
/// itself, and `supabase_flutter` reads the session out of the URL it lands
/// back on.
///
/// The browser answer is computed from the URL the app is *actually* served
/// from ([Uri.base]) rather than compiled in, because there are several: a
/// GitHub Pages project site under a path, and `localhost:<port>` while
/// developing. Every one of them must also be listed in Supabase →
/// Authentication → URL Configuration (docs/cloud-setup.md §1.6) — an origin
/// the dashboard does not know is refused before the browser ever comes back.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// The deep-link the OAuth provider returns to on iOS and Android. Registered
/// in FOUR places that must agree, or OAuth sign-in dead-ends on the redirect:
/// `supabase/config.toml` (local), the iOS `Info.plist` CFBundleURLSchemes, the
/// Android manifest's intent-filter, and — for cloud — the Supabase dashboard's
/// Redirect URLs (docs/cloud-setup.md §1.6).
const nativeOAuthRedirect = 'io.ansi.app://login-callback';

/// The page the browser should come back to, given the URL it is on now.
///
/// It is the app's own document — origin plus the directory it is served from
/// — with the query and the route dropped: the router is on hash URLs
/// (`…/#/week`), so the fragment is this build's route and has no business in
/// a redirect, and the query is where Supabase will put its `?code=`. A
/// trailing file segment (`…/index.html`) is dropped too, so the redirect is a
/// directory URL whatever the host served.
///
/// Examples: `https://simonboothroyd.github.io/ansi/#/sign-in` →
/// `https://simonboothroyd.github.io/ansi/`; `http://localhost:8080/#/week` →
/// `http://localhost:8080/`.
String webOAuthRedirect(Uri base) {
  final path = base.path;
  final directory = path.endsWith('/')
      ? path
      : path.substring(0, path.lastIndexOf('/') + 1);
  return '${base.origin}${directory.isEmpty ? '/' : directory}';
}

/// What to hand `signInWithOAuth` as `redirectTo` from [base] (the caller
/// passes [Uri.base]), or null when the app is in local/dev mode with no
/// Supabase behind it at all.
String? oauthRedirectFor(Uri base, {required bool configured}) {
  if (!configured) return null;
  return kIsWeb ? webOAuthRedirect(base) : nativeOAuthRedirect;
}
