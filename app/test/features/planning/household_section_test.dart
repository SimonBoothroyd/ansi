/// The Household section of `/account` (plan 0027 P-D2/D3, moved off the
/// Library `⋯` by 0028 E6): the roster with each member's segment, every tap
/// a write, custom in quarter steps within ¼..3.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
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
  testWidgets('lists every member with their factor on file selected, and '
      'says what a meal for both now counts as (frame a)', (tester) async {
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

  testWidgets('a pick writes through for THAT member — either may set either '
      '(P-D3) — and the sheet shows the write land', (tester) async {
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

  testWidgets('… opens the custom stepper: quarter steps, each a write, '
      'clamped to ¼..3 (P-D2)', (tester) async {
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
  });

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
}
