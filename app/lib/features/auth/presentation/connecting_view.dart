/// Shown after sign-in while the session is being established — onboarding
/// (`ensure_onboarded`), PowerSync `connect`, and the first sync. The router
/// holds the user here until the household resolves ([SessionReady]); a
/// [SessionError] surfaces here with retry and sign-out affordances, so a
/// failure never pins the user on an infinite spinner (see `app_router.dart`).
/// The two swap prominence when the server no longer has this account
/// ([SessionError.accountMissing]): only signing out can clear that one.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/session.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';

class ConnectingView extends ConsumerWidget {
  const ConnectingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final error = session is SessionError ? session : null;
    // When the server no longer has this account, retry can only fail again:
    // sign-out leads and retry steps back to the ghost slot.
    final accountMissing = error?.accountMissing ?? false;

    return FScaffold(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Ansi',
                  style: ansiSerif(size: AnsiType.display),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (error == null) ...[
                  const Center(child: FCircularProgress()),
                  const SizedBox(height: 20),
                  Text(
                    'Setting up your kitchen…',
                    textAlign: TextAlign.center,
                    style: ansiSans(size: 14, color: AnsiColors.muted),
                  ),
                ] else ...[
                  Text(
                    'Could not set up your kitchen.',
                    textAlign: TextAlign.center,
                    style: ansiSans(size: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    error.message,
                    textAlign: TextAlign.center,
                    style: ansiSans(size: 12.5, color: AnsiColors.gone),
                  ),
                  const SizedBox(height: 20),
                  FButton(
                    onPress: accountMissing
                        ? controller.signOut
                        : controller.retry,
                    child: Text(accountMissing ? 'Sign out' : 'Retry'),
                  ),
                ],
                const SizedBox(height: 10),
                FButton(
                  variant: FButtonVariant.ghost,
                  onPress: accountMissing
                      ? controller.retry
                      : controller.signOut,
                  child: Text(accountMissing ? 'Retry' : 'Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
