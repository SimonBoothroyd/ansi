/// Shown after sign-in while the session is being established — onboarding
/// (`ensure_onboarded`), PowerSync `connect`, and the first sync. The router
/// holds the user here until the household is resolved, so no screen reads
/// `currentHouseholdId` before it exists (see `app_router.dart`).
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';

class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mise', style: miseSerif(size: 34)),
            const SizedBox(height: 20),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: MiseColors.herb,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Setting up your kitchen…',
              style: miseSans(size: 14, color: MiseColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
