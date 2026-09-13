/// The app's tab shell: one [AnsiBottomNav], four branch Navigators, and the
/// opacity-only cross-fade between them.
///
/// The bar lives here rather than on the four tab screens, so a tab switch
/// cannot animate it: the root Navigator's page list does not change, no route
/// transition runs, and the bar is never rebuilt or moved. Switching a tab is
/// an index change inside this widget.
///
/// The branch children keep their slot in a [Stack] and are never reordered,
/// so each tab holds its own Navigator, scroll offsets and view state (D7).
///
/// Back on a non-Library tab returns to the Library tab, and a second back
/// leaves the app (D3-b — the Android convention, one step, cannot loop). The
/// rule is stated here rather than inherited from whatever `context.go` left on
/// the stack.
///
/// While the bar is under the content the whole shell sits in one
/// [AnsiMeasure], so on a wide window the tabs, the banner and the bar stay one
/// centred column together — a bar stretched over a desktop monitor while its
/// content is 640 wide is two layouts, not one. This is the tabs' single wrap:
/// no tab root wraps itself.
///
/// Once the chrome moves **beside** the content the bar is gone and so is that
/// wrap: the sidebar is drawn by the outer shell, once and outside every
/// Navigator (`core/router/app_router.dart`), and each branch root measures its
/// own pane through the router's [AnsiPane]. That is what lets a tab root ask
/// for the whole pane — the Week's two panes, the Library's shelf — instead of
/// being capped by a wrap it cannot see.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import 'ansi_bottom_nav.dart';
import 'ansi_layout.dart';
import 'sync_banner.dart';

/// The branch the app treats as home: back from anywhere else lands here first.
const kHomeBranch = 0;

/// How long the content cross-fade takes.
///
/// Set to [Duration.zero] to compare against a hard cut — that is the "no
/// animation" option, one constant away and with no structural change.
const kTabFade = Duration(milliseconds: 120);

class AnsiTabShell extends StatelessWidget {
  const AnsiTabShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => PopScope(
    // Only the home tab lets a back out of the app. Everywhere else the pop is
    // intercepted and spent on returning here, so leaving takes two backs from
    // any tab and never more. `canPop: false` still lets Android start its
    // predictive animation — Flutter routes it through PredictiveBackRoute —
    // so the gesture keeps its preview.
    canPop: shell.currentIndex == kHomeBranch,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) shell.goBranch(kHomeBranch);
    },
    child: AnsiShell.of(context).beside
        ? _PaneShell(shell: shell)
        : AnsiMeasure(child: _BarShell(shell: shell)),
  );
}

/// The shell with its bar under the content: the phone's form, and what a
/// window up to `lg` keeps.
class _BarShell extends StatelessWidget {
  const _BarShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => FScaffold(
    // Each tab screen has its own FScaffold inside the branch, which
    // applies the page padding already; leaving it on here would double it.
    childPad: false,
    footer: AnsiBottomNav(shell: shell),
    child: Column(
      children: [
        // The sync banner belongs to the app, not to a tab, so it lives
        // here exactly once, above every branch. It draws nothing at all
        // while sync is healthy — which is almost always.
        const AnsiSyncBanner(),
        Expanded(child: shell),
      ],
    ),
  );
}

/// The shell as a content pane: no bar, no measure, and the sidebar drawn
/// around it by the outer shell.
///
/// The banner stays the pane's full width rather than sitting in a branch's
/// measure: it is the app's own band, like the sidebar, and it draws nothing at
/// all while sync is healthy.
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
  void initState() {
    super.initState();
    // The fade ending changes which branches are on stage (see [_onStage]),
    // and an animation finishing does not rebuild anything on its own.
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

  /// Zero for a branch that is neither on screen nor on its way off it — the
  /// [FadeTransition] then paints nothing, while the subtree stays mounted.
  Animation<double> _opacityFor(int index) {
    if (index == widget.index) return _fadeIn;
    if (index == _outgoing) return _fadeOut;
    return const AlwaysStoppedAnimation<double>(0);
  }

  /// Whether a branch takes part in this frame: the one being shown, plus the
  /// one fading out while the fade runs.
  ///
  /// Everything else goes [Offstage] — not to save work (an invisible branch
  /// already paints nothing) but so it leaves the *visible* tree: an offstage
  /// subtree is skipped by hit tests, by the semantics tree a screen reader
  /// walks, and by the default `find.*` in a test. Without it the three tabs
  /// you are not looking at answer for text on the one you are.
  ///
  /// It costs nothing in state: `RenderOffstage` still lays its child out with
  /// the same constraints, so scroll offsets and every view state survive
  /// (D7) — it only stops painting and hit-testing it.
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
