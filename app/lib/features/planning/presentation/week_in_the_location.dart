/// The week on screen, in the address bar — for the three tabs that derive
/// from it.
///
/// The week is a **position, not a singleton** ([ViewedWeekStart]), and it is
/// held in one keep-alive provider shared by the Week, Cook and Shop tabs
/// because all three draw the switcher that moves it. A provider is not a URL,
/// so before this the week survived a tab switch and a push but not a browser
/// refresh: reload on week + 2 and you were back on this week, on whichever tab
/// you reloaded. The day the wide Week's left pane stands on was lost the same
/// way.
///
/// So each of the three tab roots wraps itself in one of these, and it does two
/// things, in one direction each:
///
/// * **URL → state, once.** On the first build only, a `?week=` in the
///   location seats [ViewedWeekStart] on the week it names. That is the
///   cold-start case — a refresh, a pasted link — and it is the only time the
///   URL is read, which is what keeps this from being a two-way binding with
///   two writers.
/// * **State → URL, always.** Afterwards the location follows the provider (and
///   whatever else the screen names in `also`) through `restateOnce`: a
///   `replace` inside `Router.neglect`, so the bar updates in place with no
///   history entry and the screen is not rebuilt. Stepping a week is not a page
///   the reader should have to press back through.
///
/// Only the tab you are LOOKING AT writes: the restate is skipped unless the
/// router's top location is this tab's own path. The other three branches stay
/// mounted (`navigation.md` §2) and would otherwise each try to rename the page
/// you are actually on — and a pushed recipe over the Week would have its URL
/// overwritten by the week underneath it.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/week_shape.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import 'week_view_models.dart';

/// The location a week tab names itself by: its [path], the week on screen as
/// `?week=`, and whatever else that screen names in [also].
///
/// One builder, used by [WeekInTheLocation] and by the controls that restate
/// the location themselves (the Week's `›`). Two spellings of the same
/// location would fight each other one frame apart.
String weekLocation(
  String path,
  DateTime weekStart, {
  Map<String, String> also = const {},
}) => Uri(
  path: path,
  queryParameters: {'week': isoDateOf(weekStart), ...also},
).toString();

class WeekInTheLocation extends ConsumerStatefulWidget {
  const WeekInTheLocation({
    required this.path,
    required this.weekKey,
    required this.child,
    this.also = const {},
    super.key,
  });

  /// This tab's own route — `/week`, `/cook`, `/shop`. The location is only
  /// restated while this is the page on top.
  final String path;

  /// The `?week=` the location arrived with, if any: a `YYYY-MM-DD` week key,
  /// read once.
  final String? weekKey;

  /// Anything else this screen names in its query, already in wire form. The
  /// Week passes `{'day': 'YYYY-MM-DD'}`; Cook and Shop pass nothing.
  final Map<String, String> also;

  final Widget child;

  @override
  ConsumerState<WeekInTheLocation> createState() => _WeekInTheLocationState();
}

class _WeekInTheLocationState extends ConsumerState<WeekInTheLocation> {
  /// Whether the cold-start read has happened. It is guarded by a flag rather
  /// than done in [initState] because seating the provider is a write, and a
  /// write during a widget's first build is the one Riverpod refuses.
  var _seated = false;

  @override
  Widget build(BuildContext context) {
    final shape = ref.watch(weekShapeProvider);
    final weekStart = ref.watch(viewedWeekStartProvider);
    final want = weekLocation(widget.path, weekStart, also: widget.also);

    // Both halves are writes — one to a provider, one to the router — so both
    // wait for the frame this build is part of to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_seated) {
        _seated = true;
        final asked = widget.weekKey == null
            ? null
            : weekStartOfKey(widget.weekKey!, shape);
        if (asked != null && asked != weekStart) {
          ref.read(viewedWeekStartProvider.notifier).set(asked);
          // The provider moved; this build's `want` named the old week, so the
          // next build restates it. Nothing to do here.
          return;
        }
      }
      // Only the tab on top renames the page — and only when there is a router
      // to name it in (a screen pumped on its own in a test has none).
      if (context.topLocationPath != widget.path) return;
      context.restateOnce(want);
    });

    return widget.child;
  }
}
