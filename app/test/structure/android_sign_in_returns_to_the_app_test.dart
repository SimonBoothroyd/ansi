/// On Android, the Google sign-in must come back to the app with nothing left
/// on top of it.
///
/// The sign-in page is a Custom Tab, which runs above `MainActivity` in Ansi's
/// own task. When Google redirects to `io.ansi.app://login-callback`, the tab
/// closes only if the link clears the top of that task — Chrome's launch
/// happens to, another Custom Tabs browser need not. So the link goes to
/// `AuthCallbackActivity`, a trampoline that re-launches the running
/// `MainActivity` with CLEAR_TOP itself, which closes the tab whichever
/// browser drew it.
///
/// The obvious alternative — `MainActivity` as singleTask — closes the tab
/// too, but clears the top of the task on every launch: tapping the launcher
/// icon would destroy a photo crop, a camera capture or a Health Connect
/// permission screen open over the app. Hence `singleTop` is pinned here.
///
/// Nothing in a Dart build would notice any of this going wrong; only a phone
/// does.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifest = 'android/app/src/main/AndroidManifest.xml';
const _trampoline =
    'android/app/src/main/kotlin/io/ansi/app/AuthCallbackActivity.kt';

/// The `<activity>` element named [name], whole.
String _activity(String manifest, String name) {
  final block = RegExp(
    r'<activity\b[^>]*android:name="' +
        RegExp.escape(name) +
        r'"[\s\S]*?</activity>',
  ).firstMatch(manifest);
  expect(block, isNotNull, reason: '$_manifest declares no $name');
  return block!.group(0)!;
}

void main() {
  final manifest = File(_manifest).readAsStringSync();

  test('the login callback is the trampoline, not MainActivity', () {
    expect(
      _activity(manifest, '.AuthCallbackActivity'),
      contains('android:scheme="io.ansi.app" android:host="login-callback"'),
    );
    expect(
      _activity(manifest, '.MainActivity'),
      isNot(contains('login-callback')),
      reason:
          'A deep link to MainActivity leaves the sign-in Custom Tab open '
          'over the app; it belongs on AuthCallbackActivity.',
    );
  });

  test('MainActivity stays singleTop', () {
    expect(
      _activity(manifest, '.MainActivity'),
      contains('android:launchMode="singleTop"'),
      reason:
          'singleTask would clear whatever is open over the app — a crop, '
          'the camera, Health Connect — every time the launcher icon is '
          'tapped.',
    );
  });

  test('the trampoline clears the task down to the running MainActivity', () {
    final source = File(_trampoline).readAsStringSync();
    for (final flag in [
      'FLAG_ACTIVITY_NEW_TASK',
      'FLAG_ACTIVITY_CLEAR_TOP',
      'FLAG_ACTIVITY_SINGLE_TOP',
    ]) {
      expect(source, contains(flag), reason: '$_trampoline lost $flag');
    }
    expect(source, contains('finish()'));
  });

  test('sign-in opens Google itself rather than through signInWithOAuth', () {
    // supabase_flutter's signInWithOAuth forces the external browser for
    // Google on Android, whatever launch mode it is given, and Chrome's own
    // task is not Ansi's to clear.
    final view = File(
      'lib/features/auth/presentation/sign_in_view.dart',
    ).readAsStringSync();
    expect(view, isNot(contains('signInWithOAuth(')));
    expect(view, contains('getOAuthSignInUrl('));
  });
}
