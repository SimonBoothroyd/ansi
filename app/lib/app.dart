import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Root widget: Forui theming + the router.
///
/// This is intentionally minimal scaffolding. The router and theme are wired in
/// `lib/core/router/` and `lib/core/theme/`.
class MiseApp extends ConsumerWidget {
  const MiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO(step-2): replace with MaterialApp.router using the go_router config
    // from lib/core/router/ and the Forui theme from lib/core/theme/.
    return FTheme(
      // Placeholder theme; see core/theme/mise_theme.dart. In forui 0.22 a
      // palette's `.light`/`.dark` exposes platform variants — pick `.touch`
      // (or `.desktop`) to get the concrete FThemeData.
      data: FThemes.zinc.light.touch,
      child: const _Placeholder(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
