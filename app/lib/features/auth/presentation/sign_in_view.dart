/// The sign-in gate (step 7). Everything else in the app lives behind it — the
/// router redirects here whenever there's no Supabase session.
///
/// Two ways in: a dev email/password (local Supabase, so onboarding + sync can
/// be exercised end-to-end now) and "Continue with Google" (the spec's real
/// auth, ADR-0002 — wired here, verified against a real Google project at cloud
/// cutover). A successful sign-in flips the auth state; the router redirect and
/// the session controller take it from there — this screen never navigates.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/sync/session.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';

/// The deep-link the OAuth provider returns to. Registered in FOUR places that
/// must agree, or OAuth sign-in dead-ends on the redirect: `supabase/config.toml`
/// (local), the iOS `Info.plist` CFBundleURLSchemes, the Android manifest's
/// intent-filter, and — for cloud — the Supabase dashboard's Redirect URLs
/// (docs/cloud-setup.md §1.6).
const _oauthRedirect = 'io.ansi.app://login-callback';

class SignInView extends HookConsumerWidget {
  const SignInView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = useState('');
    final password = useState('');
    final busy = useState(false);
    final error = useState<String?>(null);

    final supabase = ref.watch(supabaseClientProvider);

    Future<void> run(Future<void> Function() action) async {
      if (busy.value) return;
      // Drop the keyboard BEFORE the sign-in navigates away. A successful
      // sign-in replaces this page while the keyboard is still up, and on
      // Android the IME inset can then outlive the keyboard (the owner's
      // Pixel: every tab shrunk by a keyboard height after signing in) — a
      // field that is unfocused here hides the keyboard while the page that
      // owns it is still around to hear the inset go back to zero.
      FocusManager.instance.primaryFocus?.unfocus();
      busy.value = true;
      error.value = null;
      try {
        await action();
      } on AuthException catch (e) {
        error.value = e.message;
      } on Exception catch (e) {
        error.value = '$e';
      } finally {
        busy.value = false;
      }
    }

    final canSubmit =
        !busy.value &&
        email.value.trim().isNotEmpty &&
        password.value.isNotEmpty;

    return FScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Ansi', style: ansiSerif(size: 34)),
                const SizedBox(height: 6),
                Text(
                  'Plan the week you want to eat.',
                  style: ansiSans(size: 14, color: AnsiColors.muted),
                ),
                const SizedBox(height: 28),

                Text('EMAIL', style: ansiLabel()),
                const SizedBox(height: 8),
                FTextField(
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  control: FTextFieldControl.managed(
                    onChange: (v) => email.value = v.text,
                  ),
                ),
                const SizedBox(height: 16),

                Text('PASSWORD', style: ansiLabel()),
                const SizedBox(height: 8),
                FTextField(
                  hint: 'password',
                  obscureText: true,
                  control: FTextFieldControl.managed(
                    onChange: (v) => password.value = v.text,
                  ),
                ),

                if (error.value != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    error.value!,
                    style: ansiSans(size: 12.5, color: AnsiColors.gone),
                  ),
                ],

                const SizedBox(height: 24),
                FButton(
                  onPress: canSubmit
                      ? () => run(
                          () => supabase.auth.signInWithPassword(
                            email: email.value.trim(),
                            password: password.value,
                          ),
                        )
                      : null,
                  child: Text(busy.value ? 'Signing in…' : 'Sign in'),
                ),
                const SizedBox(height: 10),
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: canSubmit
                      ? () => run(
                          () => supabase.auth.signUp(
                            email: email.value.trim(),
                            password: password.value,
                          ),
                        )
                      : null,
                  child: const Text('Create account'),
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: FDivider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or', style: ansiLabel()),
                    ),
                    const Expanded(child: FDivider()),
                  ],
                ),
                const SizedBox(height: 24),

                FButton(
                  variant: FButtonVariant.secondary,
                  onPress: busy.value
                      ? null
                      : () => run(
                          () => supabase.auth.signInWithOAuth(
                            OAuthProvider.google,
                            redirectTo: Env.isConfigured
                                ? _oauthRedirect
                                : null,
                            // The default in-app browser sheet does NOT
                            // dismiss itself when the io.ansi.app deep link
                            // fires — the app signs in underneath while the
                            // sheet sits on "loading" forever. The external
                            // browser backgrounds itself when the redirect
                            // foregrounds the app.
                            authScreenLaunchMode:
                                LaunchMode.externalApplication,
                          ),
                        ),
                  child: const Text('Continue with Google'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
