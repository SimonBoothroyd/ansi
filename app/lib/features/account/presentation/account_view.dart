/// `/account` — the household, this device, and the session.
///
/// A screen whose only content is a Sign-out button would exist to hold a
/// divider; this one holds the household roster, the device's sync health and
/// the session, so it earns the route.
///
/// A pushed page, not a fifth tab: the four tabs are a loop — find, plan,
/// cook, buy — and the moment the bar carries something that is not a phase of
/// the week it stops reading as the week's cycle. This is visited monthly; it
/// does not buy thumb-level space on every screen.
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
      // The page hosts a segment that can open a stepper sheet; the shell is
      // not above us here, so the scaffold keeps its own inset handling.
      header: FHeader.nested(
        title: Text('Account', style: ansiHeaderTitle()),
        // Both doors to this page push it — the Library header's on a phone,
        // the sidebar's footer item on wide — so the usual arrival pops. A
        // pasted `/#/account` has nothing under it, and lands on the Library.
        prefixes: [FHeaderAction.back(onPress: () => ansiBack(context))],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _Eyebrow('Household'),
          const HouseholdSection(),
          const SizedBox(height: 26),

          // Where this device stands with the server — the QUIET half of sync
          // health. The loud half does not move here: a stall or a refused
          // write still raises the shell's banner over whatever you are doing,
          // because a state that is wrong must not wait to be visited.
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
                  // The page can unmount under the dialog, so the notifier is
                  // read through the container captured before the await —
                  // never through this ref afterwards.
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

/// A section heading — the board's herb caps, the same eyebrow the recipe page
/// prints its filing in.
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
