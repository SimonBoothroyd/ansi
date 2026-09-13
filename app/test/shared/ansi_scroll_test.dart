/// The gutter the wide panes keep for the scrollbar
/// (`lib/shared/ansi_scroll.dart`).
///
/// The owner's second report was that the Library's right-most controls
/// *collide
/// with the scroll bar*. They did, and no amount of hover work would have fixed
/// it: on a mouse platform Flutter draws the bar over the content, last, hard
/// against the pane's right edge, so the `⋯` at the end of a ledger row is
/// under
/// the thumb and the click lands on the scrollbar.
///
/// Two claims here, and they have to hold together. **The bar is where the app
/// puts it** — a stated thickness, a stated margin, and only where a mouse is
/// doing the pointing. **The panes leave room for it** — every wide list's
/// padding carries the gutter on its right, and the gutter is wider than the
/// bar, so the last control stops before the thumb starts rather than beside
/// it.
///
/// The second claim is asserted through `ansiScrollPadding` rather than by
/// pumping six screens: that function is the only way a pane states this
/// padding, and a structural check that every wide list calls it is what the
/// third test does.
library;

import 'dart:io';

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_scroll.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

import '../helpers/source_scan.dart';

/// The panes whose right-most control the owner named, and the two beside them.
/// Each must state its scroll padding through [ansiScrollPadding].
const _widePanes = [
  'lib/features/books/presentation/library_view.dart', // the ledger's `⋯`
  'lib/features/books/presentation/book_page_view.dart', // the book page
  'lib/features/planning/presentation/week_wide.dart', // day pane + agenda
  'lib/features/ingredients/presentation/ingredient_list_view.dart',
  'lib/features/shopping/presentation/shopping_view.dart',
  'lib/features/cook_plan/presentation/cook_view.dart', // holds the Cook sheet
];

/// Reads [ansiScrollPadding] the way a pane does, in a window [width] across.
Future<EdgeInsets> paddingAt(
  WidgetTester tester,
  double width,
  EdgeInsets base,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);

  late EdgeInsets read;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FTheme(
        data: ansiThemeData(),
        child: Builder(
          builder: (context) {
            read = ansiScrollPadding(context, base);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return read;
}

void main() {
  const base = EdgeInsets.fromLTRB(20, 8, 12, 24);

  group('the gutter', () {
    test('is wider than the bar it makes room for', () {
      expect(
        kAnsiScrollGutter,
        greaterThan(kAnsiScrollbarThickness + kAnsiScrollbarMargin),
        reason:
            'the gutter has to clear the thumb AND leave air, or the last '
            'control merely touches the bar instead of colliding with it',
      );
    });

    testWidgets('is nothing while the chrome is under the content', (
      tester,
    ) async {
      // A phone, and a half-screen browser window: the bar is a hint over a
      // page that is already gutter-padded, and nothing collides.
      for (final width in [390.0, 900.0]) {
        expect(
          await paddingAt(tester, width, base),
          base,
          reason: 'at ${width}px the page is one column and owes no gutter',
        );
      }
    });

    testWidgets('is added to the pane’s own right padding on wide', (
      tester,
    ) async {
      // An iPad in landscape (the rail) and a desktop window (the sidebar).
      for (final width in [1100.0, 1440.0]) {
        final padding = await paddingAt(tester, width, base);
        expect(
          padding.right,
          base.right + kAnsiScrollGutter,
          reason: 'at ${width}px the pane owes the bar its gutter',
        );
        // The other three edges are the pane's own numbers, untouched: this
        // is a gutter, not a re-statement of the page's padding.
        expect(padding.left, base.left);
        expect(padding.top, base.top);
        expect(padding.bottom, base.bottom);
      }
    });
  });

  group('the scrollbar', () {
    testWidgets('is drawn, at the app’s thickness, on a mouse platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScrollConfiguration(
            behavior: const AnsiScrollBehavior(),
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++) const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      );

      final bar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(bar.thickness, kAnsiScrollbarThickness);
      expect(bar.crossAxisMargin, kAnsiScrollbarMargin);
      expect(
        bar.thumbVisibility,
        isTrue,
        reason:
            'a thumb that appears only once you have scrolled is no use to '
            'someone deciding whether to',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('is not drawn at all where the pointer is a finger', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ScrollConfiguration(
            behavior: const AnsiScrollBehavior(),
            child: ListView(
              children: [
                for (var i = 0; i < 60; i++) const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(RawScrollbar), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    test('drag-to-scroll is left to the wheel and the thumb', () {
      // Not `PointerDeviceKind.mouse`. A mouse drag over the body would take
      // click-drag text selection away from every recipe and ingredient row —
      // see the library doc for what it would and would not have broken.
      expect(
        const AnsiScrollBehavior().dragDevices,
        isNot(contains(PointerDeviceKind.mouse)),
      );
    });
  });

  test('structural: every wide pane states its padding through the gutter', () {
    final missing = <String>[];
    for (final path in _widePanes) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path has moved or gone');
      final code = blankNonCode(file.readAsStringSync());
      if (!code.contains('ansiScrollPadding')) missing.add(path);
    }
    expect(
      missing,
      isEmpty,
      reason:
          'a wide pane states a scroll padding of its own, so its right-most '
          'control sits under the scrollbar. Wrap the padding in '
          'ansiScrollPadding(context, ...):\n${missing.join('\n')}',
    );
  });
}
