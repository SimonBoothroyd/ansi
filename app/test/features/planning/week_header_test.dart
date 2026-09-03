// The week switcher as a shared title (plan 0025 D7a/D7b): what changes per
// host tab, and what a derived tab must never touch.
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/planning/domain/planning.dart';
import 'package:ansi/features/planning/presentation/week_format.dart';
import 'package:ansi/features/planning/presentation/week_header.dart';
import 'package:ansi/features/planning/presentation/week_view_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

Widget _host(WeekSwitcher switcher, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: FTheme(
          data: ansiThemeData(),
          child: FScaffold(
            header: FHeader.nested(title: switcher),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

void main() {
  final monday = mondayOf(DateTime.now());
  final title = formatWeekTitle(monday, monday);
  final titleText = '${title.label} · ${title.date}';

  testWidgets('showCopyLastWeek: false hides the Week write — and the derived '
      'tab never reads the planning repository', (tester) async {
    // No planning repository override: reading it would reach for the
    // database provider and throw, so the item's absence is structural.
    await tester.pumpWidget(_host(const WeekSwitcher(showCopyLastWeek: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text(titleText));
    await tester.pumpAndSettle();
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Next week'), findsOneWidget);
    expect(find.text('Last week'), findsOneWidget);
    expect(find.text('Jump to today'), findsOneWidget);
    expect(find.text('Copy last week into this one'), findsNothing);
  });

  testWidgets('the Week keeps "copy last week" when there is one to copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const WeekSwitcher(),
        overrides: [
          lastWeekProvider.overrideWith(
            (ref) async => WeekPlan(
              id: 'w0',
              weekStart: monday.subtract(const Duration(days: 7)),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(titleText));
    await tester.pumpAndSettle();
    expect(find.text('Copy last week into this one'), findsOneWidget);
  });

  testWidgets("detailFor labels the row it answers for, in the host's words", (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        WeekSwitcher(
          showCopyLastWeek: false,
          detailFor: (weekStart) => weekStart == monday ? '2 cooks' : null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(titleText));
    await tester.pumpAndSettle();
    expect(find.text('2 cooks'), findsOneWidget);
  });
}
