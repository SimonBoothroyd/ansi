/// The one answer a glyph gives a pointer (`lib/shared/ansi_tap.dart`).
///
/// The owner's report was that most of the app's glyph controls did nothing at
/// all under a mouse. What follows is the contract that replaced them, asserted
/// on a real glyph control from `lib/` — the `⋯` more-trigger — rather than on
/// a
/// stand-in, so a call site that opts itself back out is caught here too.
///
/// Checked at **both bands**, because the two ends of this change are different
/// claims: on a desk the ground, the ring, the cursor and the 32 px target all
/// have to be there; on a phone none of the interaction states can appear, and
/// the geometry must not move — the whole point of the mouse-only target
/// minimum. The band is set by a real window (`tester.view`) and the *idiom* by
/// a `TargetPlatformVariant`, because they are separate questions: a narrow
/// window on a desk is still driven by a mouse, and this file is the one place
/// that can say so without a device in hand.
library;

import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/theme/ansi_tokens.dart';
import 'package:ansi/shared/ansi_more_trigger.dart';
import 'package:ansi/shared/ansi_tap.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _phone = Size(390, 780);
const _desk = Size(1440, 900);

/// The idiom each group runs under. The window says how much room there is;
/// this says what is doing the pointing.
final _mouse = TargetPlatformVariant.only(TargetPlatform.macOS);
final _finger = TargetPlatformVariant.only(TargetPlatform.iOS);

/// The glyph under test, pumped in a window [size] across, with a second
/// control beside it for the focus to arrive from.
Future<FocusNode> pumpGlyph(WidgetTester tester, {required Size size}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);

  final node = FocusNode();
  addTearDown(node.dispose);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FTheme(
        data: ansiThemeData(),
        child: Align(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Focus(focusNode: node, child: const SizedBox(width: 20)),
              AnsiMoreTrigger.inline(onTap: () {}),
            ],
          ),
        ),
      ),
    ),
  );
  return node;
}

/// The ground the tap is painting right now.
Color? groundOf(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byType(AnsiTap),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color;
}

/// The ink the glyph is drawn in right now.
Color? glyphInkOf(WidgetTester tester) {
  final icon = tester.widget<Icon>(
    find.descendant(of: find.byType(AnsiTap), matching: find.byType(Icon)),
  );
  return icon.color ??
      IconTheme.of(tester.element(find.byType(Icon).last)).color;
}

/// Moves a mouse over the glyph and leaves it there.
Future<void> hover(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(find.byType(AnsiTap)));
  await tester.pumpAndSettle();
}

void main() {
  group('on a desk', () {
    testWidgets('the `⋯` is an AnsiTap, and it is a Forui tappable', (
      tester,
    ) async {
      await pumpGlyph(tester, size: _desk);

      expect(find.byType(AnsiTap), findsOneWidget);
      // Not a bare GestureDetector: the whole point is that the tap wrapper is
      // the thing that carries hover, focus and cursor. By predicate, not by
      // type — Forui's animated tappable is a subclass, and `byType` is exact.
      expect(
        find.descendant(
          of: find.byType(AnsiTap),
          matching: find.byWidgetPredicate((w) => w is FTappable),
        ),
        findsOneWidget,
      );
    }, variant: _mouse);

    testWidgets('hovering grounds it herb-soft and steps the glyph herb-deep', (
      tester,
    ) async {
      await pumpGlyph(tester, size: _desk);

      expect(
        groundOf(tester),
        const Color(0x00000000),
        reason: 'a glyph at rest has no ground',
      );

      await hover(tester);

      expect(
        groundOf(tester),
        AnsiColors.herbSoft,
        reason: 'the hover ground is the theme’s `secondary`',
      );
      expect(
        glyphInkOf(tester),
        AnsiColors.herbDeep,
        reason: 'the hovered glyph is the theme’s `secondaryForeground`',
      );
    }, variant: _mouse);

    testWidgets('it takes focus, and rings when it has it', (tester) async {
      final beside = await pumpGlyph(tester, size: _desk);
      beside.requestFocus();
      await tester.pump();

      final outline = find.descendant(
        of: find.byType(AnsiTap),
        matching: find.byType(FFocusedOutline),
      );
      expect(outline, findsOneWidget);
      expect(
        tester.widget<FFocusedOutline>(outline).focused,
        isFalse,
        reason: 'the ring is not drawn while the focus is elsewhere',
      );

      beside.nextFocus();
      await tester.pumpAndSettle();

      expect(
        tester.widget<FFocusedOutline>(outline).focused,
        isTrue,
        reason: 'tabbing onto the glyph draws the ring',
      );
    }, variant: _mouse);

    testWidgets('it is at least 32 square, so the ground is legible', (
      tester,
    ) async {
      await pumpGlyph(tester, size: _desk);

      final size = tester.getSize(find.byType(AnsiTap));
      expect(size.width, greaterThanOrEqualTo(kAnsiPointerTarget));
      expect(size.height, greaterThanOrEqualTo(kAnsiPointerTarget));
    }, variant: _mouse);
  });

  group('on a phone', () {
    testWidgets('the same control is the same AnsiTap', (tester) async {
      await pumpGlyph(tester, size: _phone);
      expect(find.byType(AnsiTap), findsOneWidget);
    }, variant: _finger);

    testWidgets('it draws no ground at rest, and does not grow', (
      tester,
    ) async {
      await pumpGlyph(tester, size: _phone);

      expect(groundOf(tester), const Color(0x00000000));
      // The 15 px glyph and its padding, and nothing added underneath: the
      // mouse's minimum is deliberately not applied where the pointer is a
      // finger, so no phone row moves (see [kAnsiTouchTarget]).
      expect(tester.getSize(find.byType(AnsiTap)).width, lessThan(20));
      expect(
        tester.getSize(find.byType(AnsiTap)).height,
        lessThan(kAnsiPointerTarget),
      );
    }, variant: _finger);
  });

  group('the theme states the ring and the cursor once', () {
    test('the focus ring is 2 px herb, 2 px clear', () {
      final ring = ansiThemeData().style.focusedOutlineStyle;
      expect(ring.color, AnsiColors.herb);
      expect(ring.width, 2);
      expect(ring.spacing, 2);
    });

    test('a header action hovers herb-deep in both header shapes', () {
      // The back chevron, the header `⋯` and the header `＋`. Forui's
      // `FHeaderActionStyle` has no ground in its contract, so the glyph
      // carries the whole answer here — but it is the same herb-deep an
      // AnsiTap moves its glyph to, and it is stated once on the theme.
      final theme = ansiThemeData();
      for (final shape in [FHeaderVariant.root, FHeaderVariant.nested]) {
        final icon = theme.headerStyles.resolve({shape}).actionStyle.iconStyle;
        expect(icon.resolve({}).color, AnsiColors.ink);
        expect(
          icon.resolve({FTappableVariant.hovered}).color,
          AnsiColors.herbDeep,
          reason: 'a $shape header action must answer a pointer visibly',
        );
      }
    });

    test(
      'an enabled tappable shows a click cursor, a disabled one does not',
      () {
        final cursor = ansiThemeData().style.tappableStyle.cursor;
        expect(cursor.resolve({}), SystemMouseCursors.click);
        expect(
          cursor.resolve({FTappableVariant.hovered}),
          SystemMouseCursors.click,
        );
        expect(
          cursor.resolve({FTappableVariant.disabled}),
          SystemMouseCursors.basic,
        );
      },
    );
  });
}
