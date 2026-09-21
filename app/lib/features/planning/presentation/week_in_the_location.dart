/// Keeps the week on screen ([ViewedWeekStart]) in the address bar for the
/// Week, Cook and Shop tab roots.
///
/// On the first build only, a `?week=` in the location seats the provider.
/// Afterwards the location follows the provider (and [WeekInTheLocation.also])
/// through `restateOnce`, which replaces in place with no history entry. Only
/// the tab whose path is the router's top location restates: the other branches
/// stay mounted and would otherwise overwrite the URL of the page on top.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/week_shape.dart';
import '../../../shared/guarded_navigation.dart';
import '../../account/data/household_providers.dart';
import 'week_view_models.dart';

/// A week tab's location: its [path], the week as `?week=`, and [also]. The one
/// builder, so two spellings never fight.
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

  /// This tab's own route — `/week`, `/cook`, `/shop`.
  final String path;

  /// The `?week=` the location arrived with, if any; read once.
  final String? weekKey;

  /// Extra query entries in wire form. The Week passes `{'day': 'YYYY-MM-DD'}`.
  final Map<String, String> also;

  final Widget child;

  @override
  ConsumerState<WeekInTheLocation> createState() => _WeekInTheLocationState();
}

class _WeekInTheLocationState extends ConsumerState<WeekInTheLocation> {
  /// Whether the cold-start read has happened. A flag rather than [initState],
  /// because Riverpod refuses a provider write during a first build.
  var _seated = false;

  @override
  Widget build(BuildContext context) {
    final shape = ref.watch(weekShapeProvider);
    final weekStart = ref.watch(viewedWeekStartProvider);
    final want = weekLocation(widget.path, weekStart, also: widget.also);

    // Both are writes (provider, router), so both wait for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_seated) {
        _seated = true;
        final asked = widget.weekKey == null
            ? null
            : weekStartOfKey(widget.weekKey!, shape);
        if (asked != null && asked != weekStart) {
          ref.read(viewedWeekStartProvider.notifier).set(asked);
          // The provider moved; the next build restates the new week.
          return;
        }
      }
      // Only the tab on top restates, and only when there is a router (tests
      // may have none).
      if (context.topLocationPath != widget.path) return;
      context.restateOnce(want);
    });

    return widget.child;
  }
}
