/// The chrome around the whole app on a wide window: the sidebar or the icon
/// rail, drawn once beside every page.
///
/// It builds the router's outer `ShellRoute`, outside the navigator that holds
/// the tab shell and pushed pages, so a push keeps the chrome. The lit
/// destination is read from the location; nothing lit means a pushed page.
/// At [AnsiShell.bar] it returns the navigator untouched.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'ansi_layout.dart';
import 'ansi_side_nav.dart';

class AnsiWideShell extends StatelessWidget {
  const AnsiWideShell({required this.child, super.key});

  /// The shell navigator: the tab shell and whatever is pushed over it.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final form = AnsiShell.of(context);
    if (!form.beside) return child;
    // The router rebuilds this builder on every location change.
    final lit = ansiBranchLocations.indexOf(
      GoRouter.of(context).state.uri.path,
    );
    return FScaffold(
      // The page inside owns its padding and keyboard inset; subtracting the
      // inset here too would subtract it twice.
      childPad: false,
      resizeToAvoidBottomInset: false,
      sidebar: AnsiSideNav(form: form, index: lit < 0 ? null : lit),
      child: child,
    );
  }
}
