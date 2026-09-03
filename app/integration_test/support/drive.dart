/// Driving the real UI on a device: the waits that cross network time, the
/// finders that stay unambiguous under the tab shell, and the one error
/// filter every file installs.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first text field INSIDE [of]. Since Library v2 a pinned search field
/// is the first `EditableText` in the tree on every screen the Library branch
/// sits under, so a bare `.first` would type into it.
Finder fieldIn(Finder of) =>
    find.descendant(of: of, matching: find.byType(EditableText)).first;

/// Filters one known, benign error report; everything else still fails the
/// test. Installed at the top of every scenario.
///
/// Opening a Forui dialog while the accessibility tree is live trips a
/// semantics assertion inside the framework — it reproduces in a plain
/// widget test with `ensureSemantics()`, and forui is already pinned at
/// the newest 0.22.x (tech-debt tracker, 2026-08-27).
/// (7.7) A dismissed sheet whose text field held focus can fire one last
/// `EditableText` periodic post-frame callback after deactivation —
/// "Looking up a deactivated widget's ancestor is unsafe" out of
/// `_updateSelectionRects`. Debug-only framework noise on teardown of the
/// autofocused picker/quantity sheets; filtered narrowly by its stack.
void ignoreForuiSemanticsAssertion() {
  final reportError = FlutterError.onError!;
  FlutterError.onError = (details) {
    final text = '${details.exception}';
    if (text.contains('semantics.dart')) return;
    if (text.contains("Looking up a deactivated widget's ancestor") &&
        '${details.stack}'.contains('_updateSelectionRects')) {
      return;
    }
    // Same family, other callback: a focused field's show-caret-on-screen
    // post-frame callback can outlive its route by one frame when a form is
    // popped mid-focus ("findRenderObject ... inactive/DEFUNCT" out of
    // EditableTextState._scheduleShowCaretOnScreen). Debug-only framework
    // noise on teardown; filtered narrowly by its stack. NB the same
    // callback, when it fires in time, SCROLLS the enclosing viewport — a
    // late one can shove the just-returned list to an arbitrary offset,
    // which is why post-return assertions scroll rather than wait.
    if ('${details.stack}'.contains('_scheduleShowCaretOnScreen')) {
      return;
    }
    reportError(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
}

/// Taps a bottom-nav tab.
///
/// `.last`: under the shell the bar is the FScaffold's footer, so it is the
/// last match in the tree — and two of its icons are drawn elsewhere too
/// (the Library's ＋ menu uses `cookingPot` for "New recipe"). A bare finder
/// is ambiguous the moment one of those is on screen.
Future<void> tapTab(WidgetTester tester, IconData icon) =>
    tester.tap(find.byIcon(icon).last);

/// Pumps until [finder] matches, then settles. `pumpAndSettle` alone can't
/// cross the network waits here (the /connecting spinner animates forever),
/// so poll real time first. The settle matters: a widget is findable the
/// moment it is *built*, which can be mid transition — a tap taken then
/// lands beside the still-moving target (observed: the Week page's row menu
/// at x=439 on a 402pt screen). A tab switch no longer moves anything (it is
/// a cross-fade in place under one fixed bar), but a pushed page's slide and
/// a sheet's rise still do. A perpetual animation on the found screen just
/// times the settle out; that's fine, proceed.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );
    // `pumpAndSettle` times out with a FlutterError (an Error, not an
    // Exception): still animating after 5s means an ambient spinner —
    // positions are stable enough, and the next wait re-checks anyway.
    // ignore: avoid_catching_errors
  } on FlutterError {
    // Intentionally swallowed; see above.
  }
}

/// Polls the local database until [probe] returns true.
Future<void> waitForDb(
  WidgetTester tester,
  Future<bool> Function() probe,
  String what, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await probe()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $what');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Scrolls the screen's primary list until [finder] matches, then ensures it
/// is visible.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  double delta = 150,
}) async {
  // The FIRST Scrollable is not always the screen's list: an expanded
  // review card puts horizontal chip rows earlier in the tree, and scrolling
  // one of those never reveals anything below the fold. Scroll the first
  // VERTICAL scrollable instead — downward first, and if the target never
  // appears (it may be ABOVE the viewport when a flow revisits an earlier
  // card), retry upward.
  // Target the screen's primary ListView, NOT the first vertical Scrollable:
  // an FTextField's EditableText carries its own vertical Scrollable and can
  // sit earlier in the tree (the manager's search box), turning every drag
  // into a no-op on a single-line text field.
  final lists = find.byType(ListView);
  final vertical = lists.evaluate().isNotEmpty
      ? lists.first
      : find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
  // Edge-detected, not budget-bounded: a direction ends when the scroll
  // position stops moving (we hit that end of the list). A miss costs
  // seconds; the old fixed 130-drag budget ground for minutes on a miss.
  double pixels() {
    final scrollableFinder = lists.evaluate().isNotEmpty
        ? find.descendant(of: vertical, matching: find.byType(Scrollable)).first
        : vertical;
    return tester.state<ScrollableState>(scrollableFinder).position.pixels;
  }

  for (final d in [delta, -delta]) {
    var last = double.nan;
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.drag(vertical, Offset(0, -d));
      await tester.pumpAndSettle();
      final now = pixels();
      if ((now - last).abs() < 1.0) break; // at this end — stop this way
      last = now;
    }
    if (finder.evaluate().isNotEmpty) break;
  }
  if (finder.evaluate().isEmpty) {
    final seen = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .take(30)
        .toList();
    fail(
      'scrollTo exhausted both directions without finding the target.\n'
      'Visible texts at failure: $seen',
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}
