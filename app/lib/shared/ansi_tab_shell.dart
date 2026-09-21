/// The app's tab shell: one [AnsiBottomNav], four branch Navigators, and an
/// opacity-only cross-fade between them.
///
/// A tab switch is an index change here, so the bar never animates and each
/// branch keeps its Navigator and state. While the bar is under the content
/// the whole shell sits in one [AnsiMeasure]; beside it, each branch root
/// measures its own pane through the router's [AnsiPane].
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'ansi_bottom_nav.dart';
import 'ansi_layout.dart';
import 'sync_banner.dart';

/// The home branch: back from any other tab lands here first.
const kHomeBranch = 0;

/// How long the content cross-fade takes. [Duration.zero] is a hard cut.
const kTabFade = Duration(milliseconds: 120);

class AnsiTabShell extends StatelessWidget {
  const AnsiTabShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => PopScope(
    // Only the home tab lets a back out of the app; elsewhere the pop returns
    // here. `canPop: false` still allows Android's predictive-back preview.
    canPop: shell.currentIndex == kHomeBranch,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) shell.goBranch(kHomeBranch);
    },
    child: AnsiShell.of(context).beside
        ? _PaneShell(shell: shell)
        : AnsiMeasure(child: _BarShell(shell: shell)),
  );
}

/// The shell with its bar under the content, up to `lg`.
class _BarShell extends StatelessWidget {
  const _BarShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => FScaffold(
    // Each tab screen's own FScaffold already applies the page padding.
    childPad: false,
    footer: AnsiBottomNav(shell: shell),
    child: Column(
      children: [
        // The sync banner, once, above every branch. It draws nothing while
        // sync is healthy.
        const AnsiSyncBanner(),
        Expanded(child: shell),
      ],
    ),
  );
}

/// The shell as a content pane: no bar, no measure; the outer shell draws
/// the sidebar. The banner spans the pane's full width.
class _PaneShell extends StatelessWidget {
  const _PaneShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => FScaffold(
    childPad: false,
    child: Column(
      children: [
        const AnsiSyncBanner(),
        Expanded(child: shell),
      ],
    ),
  );
}

/// Fades between the branch children in place: opacity only, so every
/// switch is the same animation.
Widget crossFadeBranchContainer(
  BuildContext context,
  StatefulNavigationShell shell,
  List<Widget> children,
) => _CrossFadeBranches(index: shell.currentIndex, children: children);

class _CrossFadeBranches extends StatefulWidget {
  const _CrossFadeBranches({required this.index, required this.children});

  final int index;

  /// One entry per branch, index-aligned and in a fixed order. go_router
  /// supplies a placeholder for an unvisited branch, so the length is stable.
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
  void initState() {
    super.initState();
    // The fade ending changes which branches are on stage ([_onStage]), and
    // an animation finishing does not rebuild on its own.
    _controller.addStatusListener(_onFadeStatus);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

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
    _controller
      ..removeStatusListener(_onFadeStatus)
      ..dispose();
    super.dispose();
  }

  /// Zero for a branch neither shown nor fading out; its subtree stays
  /// mounted.
  Animation<double> _opacityFor(int index) {
    if (index == widget.index) return _fadeIn;
    if (index == _outgoing) return _fadeOut;
    return const AlwaysStoppedAnimation<double>(0);
  }

  /// Whether a branch takes part in this frame: the one shown, plus the one
  /// fading out.
  ///
  /// The rest go [Offstage] so hit tests, semantics and a test's `find.*`
  /// skip them. `RenderOffstage` still lays its child out, so scroll offsets
  /// and view state survive.
  bool _onStage(int index) =>
      index == widget.index || (index == _outgoing && _controller.isAnimating);

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (index, child) in widget.children.indexed)
        Offstage(
          offstage: !_onStage(index),
          child: FadeTransition(
            opacity: _opacityFor(index),
            child: TickerMode(
              enabled: index == widget.index,
              child: IgnorePointer(
                ignoring: index != widget.index,
                child: child,
              ),
            ),
          ),
        ),
    ],
  );
}
