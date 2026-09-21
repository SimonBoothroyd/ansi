/// `/account`: the household, this device's sync health, and the session. A
/// pushed page, not a fifth tab.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/session.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/sync_health_row.dart';
import '../../planning/presentation/household_section.dart';

/// The route the Library header's household control opens.
const kAccountRoute = '/account';

class AccountView extends ConsumerWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      // The shell is not above a pushed page, so this scaffold keeps its own
      // inset handling.
      header: FHeader.nested(
        title: Text('Account', style: ansiHeaderTitle()),
        // Both doors push this page; a pasted `/#/account` has nothing under
        // it and lands on the Library.
        prefixes: [FHeaderAction.back(onPress: () => ansiBack(context))],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _Eyebrow('Household'),
          const HouseholdSection(),
          const SizedBox(height: 26),

          // The quiet half of sync health. A stall or a refused write still
          // raises the shell's banner everywhere.
          const _Eyebrow('This device'),
          FItemGroup(children: const [SyncHealthRow()]),
          const SizedBox(height: 26),

          const _Eyebrow('Session'),
          FItemGroup(
            children: [
              FItem(
                prefix: const Icon(FLucideIcons.logOut),
                title: const Text('Sign out'),
                onPress: () async {
                  // The page can unmount under the dialog, so read the
                  // notifier through the container captured before the await.
                  final container = ProviderScope.containerOf(
                    context,
                    listen: false,
                  );
                  if (await confirmSignOut(context)) {
                    await container
                        .read(sessionControllerProvider.notifier)
                        .signOut();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A section heading in herb caps.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text.toUpperCase(), style: ansiLabel(color: AnsiColors.herb)),
  );
}

/// Asks before signing out: sign-out disconnects sync and clears this device's
/// local copy of the household data (it stays on the server).
Future<bool> confirmSignOut(BuildContext context) async {
  return askAnsi(
    context,
    title: 'Sign out?',
    body:
        'This removes the synced data from this device. It stays in your '
        'household and comes back when you sign in again.',
    confirm: 'Sign out',
  );
}
