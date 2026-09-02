/// The app's tab shell: one [AnsiBottomNav], four branch Navigators, and the
/// opacity-only cross-fade between them (design board: Navigation v2, D1/D1.1).
///
/// The bar lives here rather than on the four tab screens, so a tab switch
/// cannot animate it: the root Navigator's page list does not change, no route
/// transition runs, and the bar is never rebuilt or moved. Switching a tab is
/// an index change inside this widget.
///
/// The branch children keep their slot in a [Stack] and are never reordered,
/// so each tab holds its own Navigator, scroll offsets and view state (D7).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'ansi_bottom_nav.dart';

/// How long the content cross-fade takes.
///
/// Set to [Duration.zero] to compare against a hard cut — that is the "no
/// animation" option, one constant away and with no structural change.
const kTabFade = Duration(milliseconds: 120);

class AnsiTabShell extends StatelessWidget {
  const AnsiTabShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => FScaffold(
    // Each tab screen has its own FScaffold inside the branch, which applies
    // the page padding already; leaving it on here would double it.
    childPad: false,
    footer: AnsiBottomNav(shell: shell),
    child: shell,
  );
}

/// Fades between the branch children in place: opacity only, no translation and
/// no scale, so Library→Shop and Shop→Library are the same animation (D1.1).
Widget crossFadeBranchContainer(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) => _CrossFadeBranches(index: shell.currentIndex, children: children);

class _CrossFadeBranches extends StatefulWidget {
  const _CrossFadeBranches({required this.index, required this.children});

  final int index;

  /// One entry per branch, index-aligned with the shell's branches and in a
  /// fixed order. go_router hands over a placeholder for a branch that has not
  /// been visited yet, so the length is stable for the app's lifetime.
  final List<Widget> children;

  @override
  State<_CrossFadeBranches> createState() => _CrossFadeBranchesState();
}

class _CrossFadeBranchesState extends State<_CrossFadeBranches>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kTabFade,
    value: 1,
  );

  /// The branch fading out. Meaningful only while [_controller] is running.
  late int _outgoing = widget.index;

  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<double> _fadeOut = Tween<double>(
    begin: 1,
    end: 0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

  @override
  void didUpdateWidget(_CrossFadeBranches old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) {
      _outgoing = old.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Zero for a branch that is neither on screen nor on its way off it — the
  /// [FadeTransition] then paints nothing, while the subtree stays mounted.
  Animation<double> _opacityFor(int index) {
    if (index == widget.index) return _fadeIn;
    if (index == _outgoing) return _fadeOut;
    return const AlwaysStoppedAnimation<double>(0);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (index, child) in widget.children.indexed)
        FadeTransition(
          opacity: _opacityFor(index),
          child: TickerMode(
            enabled: index == widget.index,
            child: IgnorePointer(ignoring: index != widget.index, child: child),
          ),
        ),
    ],
  );
}
