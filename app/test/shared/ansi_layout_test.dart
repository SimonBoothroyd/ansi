// The one viewport reader: the bands it names, and the column it draws.
//
// The bands come off the theme's FBreakpoints (sm 640, lg 1024), so the
// boundaries are checked on both sides of each one rather than in the middle of
// a band — a band that starts a pixel late is exactly the bug this file exists
// to catch.
//
// The window is a real view (`tester.view`), not a MediaQuery wrapped
// around a SizedBox: AnsiMeasure has to agree with the constraints it is
// actually handed, and a media query that disagrees with the layout would let a
// broken cap pass.
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/shared/ansi_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

const _windowHeight = 600.0;
const _childKey = Key('measured child');

/// Pumps [child] in a window [width] logical pixels across.
Future<void> pumpWindow(WidgetTester tester, double width, Widget child) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, _windowHeight);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: FTheme(data: ansiThemeData(), child: child),
    ),
  );
}

/// The band [width] falls in, read the way a widget reads it.
Future<AnsiLayout> bandAt(WidgetTester tester, double width) async {
  late AnsiLayout band;
  await pumpWindow(
    tester,
    width,
    Builder(
      builder: (context) {
        band = AnsiLayout.of(context);
        return const SizedBox.shrink();
      },
    ),
  );
  return band;
}

void main() {
  group('AnsiLayout.of', () {
    testWidgets('is compact right up to the sm breakpoint', (tester) async {
      expect(await bandAt(tester, 320), AnsiLayout.compact);
      expect(await bandAt(tester, 639), AnsiLayout.compact);
    });

    testWidgets('is medium from sm to just under lg', (tester) async {
      expect(await bandAt(tester, 640), AnsiLayout.medium);
      expect(await bandAt(tester, 1023), AnsiLayout.medium);
    });

    testWidgets('is expanded from lg up', (tester) async {
      expect(await bandAt(tester, 1024), AnsiLayout.expanded);
      expect(await bandAt(tester, 1600), AnsiLayout.expanded);
    });
  });

  group('AnsiMeasure', () {
    Future<Rect> childRect(WidgetTester tester, double width) async {
      await pumpWindow(
        tester,
        width,
        const AnsiMeasure(child: SizedBox.expand(key: _childKey)),
      );
      return tester.getRect(find.byKey(_childKey));
    }

    testWidgets('leaves a compact window alone', (tester) async {
      expect(
        await childRect(tester, 402),
        const Rect.fromLTWH(0, 0, 402, _windowHeight),
      );
    });

    testWidgets('caps and centres from medium up', (tester) async {
      expect(
        await childRect(tester, 800),
        const Rect.fromLTWH(80, 0, 640, _windowHeight),
      );
      expect(
        await childRect(tester, 1440),
        const Rect.fromLTWH(400, 0, 640, _windowHeight),
      );
    });

    testWidgets('draws exactly the measure it reports', (tester) async {
      late double measure;
      await pumpWindow(
        tester,
        1440,
        Builder(
          builder: (context) {
            measure = ansiMeasureWidth(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(measure, (await childRect(tester, 1440)).width);
    });
  });

  testWidgets('ansiViewportHeight is a share of the window', (tester) async {
    late double height;
    await pumpWindow(
      tester,
      402,
      Builder(
        builder: (context) {
          height = ansiViewportHeight(context, 0.5);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(height, _windowHeight / 2);
  });
}
