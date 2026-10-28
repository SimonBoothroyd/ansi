import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/core/week_shape.dart';
import 'package:ansi/shared/week_strip.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _none = WeekStripDay();
const _cook = WeekStripDay(fill: WeekStripFill.cooked, eats: true);
const _keep = WeekStripDay(fill: WeekStripFill.keeps);
const _frozenMe = WeekStripDay(
  fill: WeekStripFill.frozen,
  thisMeal: true,
  eats: true,
);
const _gone = WeekStripDay(fill: WeekStripFill.gone);

Future<void> _pump(WidgetTester tester, Widget strip) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: SizedBox(width: 320, child: strip)),
  ),
);

List<String> _labels(WidgetTester tester) => [
  for (final cell in tester.widgetList<WeekStripCell>(
    find.byType(WeekStripCell),
  ))
    cell.label,
];

void main() {
  group('mergeStripDays', () {
    test('the strongest fill wins a day, and marks from either batch show', () {
      final merged = mergeStripDays([
        [_cook, _keep, _gone, _gone, _gone, _gone, _gone],
        [_none, _none, _none, _none, _none, _cook, _frozenMe],
      ]);
      expect(
        [for (final d in merged) d.fill],
        [
          WeekStripFill.cooked,
          WeekStripFill.keeps,
          WeekStripFill.gone,
          WeekStripFill.gone,
          WeekStripFill.gone,
          WeekStripFill.cooked,
          WeekStripFill.frozen,
        ],
      );
      expect(merged[6].thisMeal, isTrue);
      expect(merged[5].eats, isTrue);
    });

    test('no batches is seven empty days', () {
      expect(mergeStripDays(const []), List.filled(7, _none));
    });
  });

  test('cookDaysOnly keeps the cook and the freezer, nothing else', () {
    final days = cookDaysOnly(const [
      _cook,
      _keep,
      _gone,
      _none,
      _none,
      _frozenMe,
      _none,
    ]);
    expect(
      [for (final d in days) d.fill],
      [
        WeekStripFill.cooked,
        WeekStripFill.none,
        WeekStripFill.none,
        WeekStripFill.none,
        WeekStripFill.none,
        WeekStripFill.frozen,
        WeekStripFill.none,
      ],
    );
    expect(days[5].thisMeal, isTrue);
    expect(days[0].eats, isTrue);
  });

  testWidgets('full size labels seven days in the week order of the shape', (
    tester,
  ) async {
    await _pump(
      tester,
      WeekStrip(days: List.filled(7, _none), shape: WeekShape.sunday),
    );
    expect(_labels(tester), ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
    // Seven cells share the width: never a calendar, never a second row.
    final first = tester.getRect(find.byKey(const ValueKey('week-strip-0')));
    final last = tester.getRect(find.byKey(const ValueKey('week-strip-6')));
    expect(first.top, last.top);
    expect(first.width, closeTo(last.width, 0.01));
  });

  testWidgets('compact and line sizes speak in initials', (tester) async {
    await _pump(
      tester,
      WeekStrip(
        days: List.filled(7, _none),
        shape: WeekShape.monday,
        size: WeekStripSize.compact,
      ),
    );
    expect(_labels(tester), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);

    await _pump(
      tester,
      WeekStrip(
        days: List.filled(7, _none),
        shape: WeekShape.monday,
        size: WeekStripSize.line,
      ),
    );
    expect(_labels(tester), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
    // The line takes only what its seven initials need.
    final left = tester.getRect(find.byKey(const ValueKey('week-strip-0')));
    final right = tester.getRect(find.byKey(const ValueKey('week-strip-6')));
    expect(right.right - left.left, 7 * 18);
  });

  testWidgets('one caption at most, in the freezer ink when this meal is '
      'frozen', (tester) async {
    await _pump(
      tester,
      const WeekStrip(
        days: [_cook, _keep, _keep, _none, _none, _frozenMe, _none],
        shape: WeekShape.monday,
        caption: 'from Monday’s batch, frozen',
      ),
    );
    final caption = tester.widget<Text>(
      find.text('from Monday’s batch, frozen'),
    );
    expect(caption.style?.color, AnsiColors.chillInk);

    await _pump(
      tester,
      const WeekStrip(
        days: [_cook, _keep, _keep, _none, _none, _none, _none],
        shape: WeekShape.monday,
        caption: 'from Monday’s batch',
      ),
    );
    expect(
      tester.widget<Text>(find.text('from Monday’s batch')).style?.color,
      AnsiColors.herbDeep,
    );
  });

  testWidgets('a screen reader hears the days that carry something', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const WeekStrip(
        days: [_cook, _keep, _none, _none, _none, _frozenMe, _none],
        shape: WeekShape.monday,
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Monday cooked a meal, Tuesday in the fridge, '
        'Saturday from the freezer this meal',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });
}
