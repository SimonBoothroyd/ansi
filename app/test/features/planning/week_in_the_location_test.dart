/// `WeekInTheLocation` — the week on screen, named in the address bar.
///
/// The week is one keep-alive position shared by the Week, Cook and Shop tabs,
/// which is why it survived a tab switch and a push but not a browser refresh:
/// a provider is not a URL. So each of those three tab roots names it in its
/// own `?week=`, seats itself from that on a cold start, and restates the
/// location afterwards — with no history entry, so back leaves the tab instead
/// of walking back through every week that was stepped through.
///
/// Read against the reported location (`SystemChannels.navigation`), which is
/// what the browser's bar actually shows.
library;

import 'dart:async';

import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/planning/presentation/week_in_the_location.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _shape = WeekShape.monday;

/// The week the app seats itself on with nothing asked for. Read the same way
/// `ViewedWeekStart` reads it — off the wall clock — because that provider is
/// deliberately not on the [clockProvider] seam: the week on screen does not
/// move at midnight, only today does.
final _thisWeek = _shape.weekStartOf(DateTime.now());

/// Every location reported to the engine, with whether it took a history entry.
({List<String> uris, List<bool> replaced}) _bar(WidgetTester tester) {
  final uris = <String>[];
  final replaced = <bool>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.navigation,
    (call) async {
      if (call.method == 'routeInformationUpdated') {
        final args = call.arguments as Map<Object?, Object?>;
        uris.add(args['uri']! as String);
        replaced.add(args['replace']! as bool);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      null,
    ),
  );
  return (uris: uris, replaced: replaced);
}

/// The three week tabs, each wrapped as its real screen is, under one router.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  String initial, {
  Map<String, String> also = const {},
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [weekShapeProvider.overrideWithValue(_shape)],
      child: MaterialApp.router(routerConfig: _router(initial, also)),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp).first),
    listen: false,
  );
}

GoRouter _router(String initial, Map<String, String> also) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final path in const ['/week', '/cook', '/shop'])
        GoRoute(
          path: path,
          builder: (context, state) => WeekInTheLocation(
            path: path,
            weekKey: state.uri.queryParameters['week'],
            also: path == '/week' ? also : const {},
            child: Text('on $path', textDirection: TextDirection.ltr),
          ),
        ),
      GoRoute(
        path: '/recipes/:id',
        builder: (context, state) =>
            const Text('a recipe', textDirection: TextDirection.ltr),
      ),
    ],
  );
  addTearDown(router.dispose);
  return router;
}

void main() {
  setUp(() => GoRouter.optionURLReflectsImperativeAPIs = true);
  tearDown(() => GoRouter.optionURLReflectsImperativeAPIs = false);

  testWidgets('a bare tab names the week it is standing on', (tester) async {
    final bar = _bar(tester);
    await _pump(tester, '/cook');

    expect(bar.uris.last, '/cook?week=${isoDateOf(_thisWeek)}');
    expect(
      bar.replaced.last,
      isTrue,
      reason:
          'naming where you already are is not a page to press back through',
    );
  });

  testWidgets('a cold `?week=` seats the week on screen — this is the refresh '
      'that used to land on this week', (tester) async {
    final other = _thisWeek.add(const Duration(days: 14));
    final container = await _pump(tester, '/cook?week=${isoDateOf(other)}');

    expect(container.read(viewedWeekStartProvider), other);
  });

  testWidgets('a `?week=` that is not a date is ignored, not obeyed', (
    tester,
  ) async {
    final bar = _bar(tester);
    final container = await _pump(tester, '/shop?week=last-tuesday');

    expect(container.read(viewedWeekStartProvider), _thisWeek);
    expect(bar.uris.last, '/shop?week=${isoDateOf(_thisWeek)}');
  });

  testWidgets(
    'stepping the week restates the location, with no history entry',
    (tester) async {
      final bar = _bar(tester);
      final container = await _pump(tester, '/week');
      final before = bar.uris.length;

      container.read(viewedWeekStartProvider.notifier).step(1);
      await tester.pumpAndSettle();

      final next = _thisWeek.add(const Duration(days: 7));
      expect(bar.uris.last, '/week?week=${isoDateOf(next)}');
      expect(bar.uris.length, before + 1);
      expect(
        bar.replaced.last,
        isTrue,
        reason: 'back should leave the week, not walk back through the weeks',
      );
    },
  );

  testWidgets('the Week also names the day its pane stands on', (tester) async {
    final bar = _bar(tester);
    await _pump(
      tester,
      '/week',
      also: {'day': isoDateOf(_shape.dateFor(_thisWeek, 3))},
    );

    expect(
      bar.uris.last,
      '/week?week=${isoDateOf(_thisWeek)}&day=${isoDateOf(_thisWeek.add(const Duration(days: 3)))}',
    );
  });

  testWidgets('an offstage tab does not rename the page you are on', (
    tester,
  ) async {
    // The three tabs you are not looking at stay mounted and keep rebuilding
    // (`navigation.md` §2). A recipe pushed over the Week keeps its own URL.
    final bar = _bar(tester);
    final container = await _pump(tester, '/week');
    final router = GoRouter.of(tester.element(find.text('on /week')));

    // Fire and forget: a push's future resolves on the POP, so awaiting it here
    // would wait for the recipe to close.
    unawaited(router.push('/recipes/9'));
    await tester.pumpAndSettle();
    expect(bar.uris.last, '/recipes/9');

    // The week moves underneath — a sync, another device, anything. The Week is
    // still mounted and rebuilds; the bar must stay on the recipe.
    container.read(viewedWeekStartProvider.notifier).step(-1);
    await tester.pumpAndSettle();

    expect(bar.uris.last, '/recipes/9');
  });
}
