/// Where Google sends the sign-in back to, and what the sign-in page opens
/// in, on each platform.
///
/// A phone uses a custom scheme. A browser cannot open one, so it returns to
/// the page the app is served from, computed from [Uri.base] because there
/// are several hosts. Each must be listed in Supabase's URL Configuration
/// (docs/cloud-setup.md §1.6).
library;

import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

/// The deep link OAuth returns to on iOS and Android. Registered in four
/// places that must agree: `supabase/config.toml`, the iOS `Info.plist`
/// CFBundleURLSchemes, the Android manifest's intent-filter, and the Supabase
/// dashboard's Redirect URLs (docs/cloud-setup.md §1.6).
const nativeOAuthRedirect = 'io.ansi.app://login-callback';

/// The page the browser should come back to: the app's own directory URL,
/// with the query, the hash route and any trailing file segment dropped.
/// `http://localhost:8080/#/week` → `http://localhost:8080/`.
String webOAuthRedirect(Uri base) {
  final path = base.path;
  final directory = path.endsWith('/')
      ? path
      : path.substring(0, path.lastIndexOf('/') + 1);
  return '${base.origin}${directory.isEmpty ? '/' : directory}';
}

/// What to hand `getOAuthSignInUrl` as `redirectTo` from [base] (the caller
/// passes [Uri.base]), or null in local/dev mode with no Supabase.
String? oauthRedirectFor(Uri base, {required bool configured}) {
  if (!configured) return null;
  return kIsWeb ? webOAuthRedirect(base) : nativeOAuthRedirect;
}

/// What the Google sign-in page opens in on [platform].
///
/// - **Android**: a Custom Tab ([LaunchMode.inAppBrowserView]). It runs in
///   Ansi's own task, so when the deep link fires, `AuthCallbackActivity`
///   clears it off the top of the task. The external browser would leave a
///   signed-in Chrome tab behind in recents, since Chrome's task is not
///   Ansi's to close.
/// - **iOS**: the external browser. The in-app sheet stays open, loading,
///   over the app after the deep link has signed it in.
/// - **The web**: the same tab, which comes back to [webOAuthRedirect].
LaunchMode oauthLaunchModeFor(TargetPlatform platform, {required bool isWeb}) {
  if (isWeb) return LaunchMode.platformDefault;
  return platform == TargetPlatform.android
      ? LaunchMode.inAppBrowserView
      : LaunchMode.externalApplication;
}
