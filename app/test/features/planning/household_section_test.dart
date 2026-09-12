/// The Household section of `/account` (plan 0027 P-D2/D3, moved off the
/// Library `⋯` by 0028 E6): the roster with each member's segment, every tap
/// a write, custom in quarter steps within ¼..3 — and, under it, the day the
/// household's week starts on.
library;

import 'package:ansi/core/sync/sync_health.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/features/account/data/household_providers.dart';
import 'package:ansi/features/account/domain/household_repository.dart';
import 'package:ansi/features/planning/data/planning_providers.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/household_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_planning_repository.dart';

const _roster = [
  Member(id: 'm1', displayName: 'Ada'),
  Member(id: 'm2', displayName: 'Jun', portionFactor: 0.75),
];

/// Records the flip the control asks for, and can refuse it — the server side
/// of D4, without a server.
class _FakeHouseholdRepository implements HouseholdRepository {
  _FakeHouseholdRepository({this.shape = WeekShape.monday, this.fails = false});

  final WeekShape shape;
  final bool fails;

  /// Every `startsOn` the control asked the server for, in order.
  final flips = <int>[];

  @override
  Stream<WeekShape> watchWeekShape() => Stream.value(shape);

  @override
  Future<void> setWeekStart(int startsOn) async {
    flips.add(startsOn);
    if (fails) throw StateError('no');
  }
}

/// The section with a household repository behind it, and the two facts the
/// week control reads: the shape on file and whether the server is reachable.
Future<_FakeHouseholdRepository> _openWeekControl(
  WidgetTester tester, {
  WeekShape shape = WeekShape.monday,
  bool reachable = true,
  bool fails = false,
}) async {
  final household = _FakeHouseholdRepository(shape: shape, fails: fails);
  await tester.pumpWidget(
    _host([
      planningRepositoryProvider.overrideWithValue(FakePlanningRepository()),
      householdRepositoryProvider.overrideWithValue(household),
      weekShapeProvider.overrideWithValue(shape),
      serverReachableProvider.overrideWith((ref) => Stream.value(reachable)),
    ]),
  );
  await tester.pumpAndSettle();
  return household;
}

/// The section on its own — `/account` renders it under an eyebrow, and this
/// exercises the roster without the page's chrome around it.
Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: const FScaffold(
      child: SingleChildScrollView(child: HouseholdSection()),
    ),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

Future<FakePlanningRepository> _open(
  WidgetTester tester, {
  List<Member> roster = _roster,
}) async {
  final repo = FakePlanningRepository(roster);
  await tester.pumpWidget(
    _host([planningRepositoryProvider.overrideWithValue(repo)]),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// The chip labelled [label] on the row for [name] — the segment sits under
/// the member's name, so the row is found by ancestry.
Finder _chip(String name, String label) => find.descendant(
  of: find.ancestor(of: find.text(name), matching: find.byType(Column)).first,
  matching: find.text(label),
);

void main() {
  testWidgets('lists every member with their factor on file selected, and says '
      'what a meal for both now counts as', (tester) async {
    await _open(tester);

    expect(find.text('USUAL PORTION'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Jun'), findsOneWidget);
    // The value on file, printed as a fraction beside each name.
    expect(find.text('×1'), findsWidgets);
    expect(find.text('×¾'), findsWidgets);
    // The five picks, twice — one segment per member — and the custom door.
    for (final label in ['×½', '×¾', '×1', '×1¼', '×1½']) {
      expect(find.text(label), findsAtLeast(2), reason: label);
    }
    expect(find.text('…'), findsNWidgets(2));
    // 1 + ¾.
    expect(
      find.text(
        'a meal for both counts as 1¾ portions — the cook plan, the shop and '
        'the macro lens all read it that way',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a pick writes through for THAT member — either may set either — '
      'and the sheet shows the write land', (tester) async {
    final repo = await _open(tester);

    await tester.tap(_chip('Jun', '×½'));
    await tester.pumpAndSettle();

    expect(repo.factorWrites, [('m2', 0.5)]);
    // The roster re-emitted; the foot line reads the new sum.
    expect(find.textContaining('counts as 1½ portions'), findsOneWidget);

    await tester.tap(_chip('Ada', '×1¼'));
    await tester.pumpAndSettle();
    expect(repo.factorWrites, [('m2', 0.5), ('m1', 1.25)]);
    expect(find.textContaining('counts as 1¾ portions'), findsOneWidget);
  });

  testWidgets(
    '… opens the custom stepper: quarter steps, each a write, clamped to ¼..3',
    (tester) async {
      final repo = await _open(tester);

      // No stepper until asked.
      expect(find.byIcon(FLucideIcons.plus), findsNothing);
      await tester.tap(_chip('Jun', '…'));
      await tester.pumpAndSettle();
      expect(find.byIcon(FLucideIcons.plus), findsOneWidget);
      expect(find.text('quarter steps, ¼ to 3'), findsOneWidget);

      // Opening custom writes nothing; stepping does, a quarter at a time.
      expect(repo.factorWrites, isEmpty);
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();
      expect(repo.factorWrites, [('m2', 1.0)]);
      await tester.tap(find.byIcon(FLucideIcons.plus));
      await tester.pumpAndSettle();
      expect(repo.factorWrites.last, ('m2', 1.25));

      // Down to the floor: ¼ is the last step, and the − then goes inert.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byIcon(FLucideIcons.minus));
        await tester.pumpAndSettle();
      }
      expect(repo.factorWrites.last, ('m2', 0.25));
      await tester.tap(find.byIcon(FLucideIcons.minus));
      await tester.pumpAndSettle();
      expect(repo.factorWrites.last, ('m2', 0.25), reason: 'clamped at ¼');
      expect(repo.factorWrites.where((w) => w.$2 < 0.25), isEmpty);
    },
  );

  testWidgets('a value that is not a pick opens in custom mode, showing the '
      'value on file rather than the nearest chip', (tester) async {
    await _open(
      tester,
      roster: const [Member(id: 'm1', displayName: 'Ada', portionFactor: 1.75)],
    );
    // The stepper is up unbidden, reading ×1¾ — and no pick is lit.
    expect(find.byIcon(FLucideIcons.plus), findsOneWidget);
    expect(find.text('×1¾'), findsNWidgets(2)); // beside the name + stepper
    expect(
      find.text(
        'a meal for Ada counts as 1¾ portions — the cook plan, the '
        'shop and the macro lens all read it that way',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the ceiling: 3 is the last step up', (tester) async {
    final repo = await _open(
      tester,
      roster: const [Member(id: 'm1', displayName: 'Ada', portionFactor: 2.75)],
    );
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    expect(repo.factorWrites, [('m1', 3.0)]);
    await tester.tap(find.byIcon(FLucideIcons.plus));
    await tester.pumpAndSettle();
    expect(repo.factorWrites, [('m1', 3.0)], reason: 'clamped at 3');
  });

  group('the week starts on', () {
    testWidgets('offers the two days, with the one on file lit, and says '
        'what the setting means', (tester) async {
      await _openWeekControl(tester);

      expect(find.text('WEEK STARTS ON'), findsOneWidget);
      expect(find.text('Sunday'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      expect(
        find.text(
          'the week you plan, cook and shop — a Monday shop covers that '
          'Monday’s dinner',
        ),
        findsOneWidget,
      );
    });

    testWidgets('asks before it moves the weeks, and the RPC carries the '
        'ISO weekday', (tester) async {
      final household = await _openWeekControl(tester);

      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();

      // The confirm names the consequence in plain words, not in schema
      // words — and nothing has been asked of the server yet.
      expect(find.text('Start the week on Sunday?'), findsOneWidget);
      expect(
        find.textContaining('Every week you have planned moves to match'),
        findsOneWidget,
      );
      expect(household.flips, isEmpty);

      await tester.tap(find.text('Start on Sunday'));
      await tester.pumpAndSettle();

      // 7 is Sunday as an ISO weekday, which is what the column stores.
      expect(household.flips, [DateTime.sunday]);
    });

    testWidgets('cancelling asks the server for nothing', (tester) async {
      final household = await _openWeekControl(tester);

      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(household.flips, isEmpty);
      expect(find.text('Start the week on Sunday?'), findsNothing);
    });

    testWidgets('tapping the day already on file does nothing at all', (
      tester,
    ) async {
      final household = await _openWeekControl(tester);

      await tester.tap(find.text('Monday'));
      await tester.pumpAndSettle();

      expect(find.text('Start the week on Monday?'), findsNothing);
      expect(household.flips, isEmpty);
    });

    testWidgets('offline the chips are inert, and say why', (tester) async {
      final household = await _openWeekControl(tester, reachable: false);

      expect(
        find.text('needs a connection · it moves weeks on both phones at once'),
        findsOneWidget,
      );

      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();

      // No confirm, no call: a control that cannot act does not pretend to.
      expect(find.text('Start the week on Sunday?'), findsNothing);
      expect(household.flips, isEmpty);
    });

    testWidgets('a refused flip leaves the amber line, and the tap', (
      tester,
    ) async {
      final household = await _openWeekControl(tester, fails: true);

      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start on Sunday'));
      await tester.pumpAndSettle();

      expect(household.flips, [DateTime.sunday]);
      expect(find.text('couldn’t move your weeks — try again'), findsOneWidget);
      // Still a control: the retry is the same tap.
      await tester.tap(find.text('Sunday'));
      await tester.pumpAndSettle();
      expect(find.text('Start the week on Sunday?'), findsOneWidget);
    });

    testWidgets('a Sunday household reads its own note', (tester) async {
      await _openWeekControl(tester, shape: WeekShape.sunday);

      expect(
        find.text(
          'the week you plan, cook and shop — a Sunday shop covers that '
          'Sunday’s dinner',
        ),
        findsOneWidget,
      );
    });
  });
}
