/// The chrome around the whole app on a wide window: the sidebar (or the icon
/// rail), drawn once, beside every page.
///
/// It is the builder of the router's outer `ShellRoute`, so it sits **outside**
/// the navigator that holds the tab shell and every pushed page. Three things
/// follow from that position, and they are the reason for it:
///
/// * **A push keeps the chrome.** The sidebar takes no part in a route
///   transition, so it cannot slide in over itself, fade, or appear twice while
///   a page animates.
/// * **It is one instance.** The lit destination is read from the location
///   rather than handed down by the tab shell, so the lit form and the neutral
///   form are the same widget with a different index — not two sidebars that
///   have to agree.
/// * **Nothing lit means you are not in the tab loop.** A pushed page draws its
///   own back control; the sidebar goes quiet behind it. On a phone the bar
///   being gone says the same thing, and a sidebar cannot go away.
///
/// At [AnsiShell.bar] it draws nothing at all: it returns the navigator
/// untouched, so the phone's tree is exactly what it was.
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
    // The router rebuilds this builder on every location change, so reading the
    // location here is enough to keep the lit destination current.
    final lit = ansiBranchLocations.indexOf(
      GoRouter.of(context).state.uri.path,
    );
    return FScaffold(
      // The page inside owns its own padding and its own keyboard inset — the
      // tab shell's scaffold, or a pushed page's. A scaffold that subtracted
      // the inset here as well would subtract it twice.
      childPad: false,
      resizeToAvoidBottomInset: false,
      sidebar: AnsiSideNav(form: form, index: lit < 0 ? null : lit),
      child: child,
    );
  }
}
