import 'package:ansi/features/auth/presentation/oauth_redirect.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

void main() {
  group('webOAuthRedirect', () {
    test('a project site under a path comes back to that directory', () {
      expect(
        webOAuthRedirect(
          Uri.parse('https://simonboothroyd.github.io/ansi/#/sign-in'),
        ),
        'https://simonboothroyd.github.io/ansi/',
      );
    });

    test('localhost keeps its port', () {
      expect(
        webOAuthRedirect(Uri.parse('http://localhost:8080/#/week')),
        'http://localhost:8080/',
      );
    });

    test('a bare origin redirects to the root', () {
      expect(
        webOAuthRedirect(Uri.parse('https://ansi.example')),
        'https://ansi.example/',
      );
    });

    test('a served file drops to its directory', () {
      expect(
        webOAuthRedirect(Uri.parse('https://ansi.example/ansi/index.html')),
        'https://ansi.example/ansi/',
      );
    });

    test("Supabase's own ?code= is not carried back into the redirect", () {
      expect(
        webOAuthRedirect(
          Uri.parse('https://ansi.example/ansi/?code=abc#/week'),
        ),
        'https://ansi.example/ansi/',
      );
    });
  });

  group('oauthRedirectFor', () {
    test('local/dev mode has nowhere to come back to', () {
      expect(
        oauthRedirectFor(
          Uri.parse('http://localhost:8080/'),
          configured: false,
        ),
        isNull,
      );
    });

    test('off the web it is the registered custom scheme', () {
      expect(
        oauthRedirectFor(Uri.parse('http://localhost:8080/'), configured: true),
        nativeOAuthRedirect,
      );
    });
  });

  group('oauthLaunchModeFor', () {
    // Android: a Custom Tab in Ansi's own task, which the login-callback
    // trampoline can clear; Chrome proper would stay open in recents.
    test('Android opens a Custom Tab', () {
      expect(
        oauthLaunchModeFor(TargetPlatform.android, isWeb: false),
        LaunchMode.inAppBrowserView,
      );
    });

    // iOS: the in-app sheet stays open over the app after the deep link.
    test('iOS opens the external browser', () {
      expect(
        oauthLaunchModeFor(TargetPlatform.iOS, isWeb: false),
        LaunchMode.externalApplication,
      );
    });

    test('the web stays in its own tab, whatever the host OS', () {
      for (final platform in TargetPlatform.values) {
        expect(
          oauthLaunchModeFor(platform, isWeb: true),
          LaunchMode.platformDefault,
        );
      }
    });
  });
}
