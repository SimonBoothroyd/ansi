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
import 'package:ansi/core/theme/ansi_tokens.dart';
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

/// The shell form [width] calls for, read the way a widget reads it.
Future<AnsiShell> shellAt(WidgetTester tester, double width) async {
  late AnsiShell form;
  await pumpWindow(
    tester,
    width,
    Builder(
      builder: (context) {
        form = AnsiShell.of(context);
        return const SizedBox.shrink();
      },
    ),
  );
  return form;
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
  _groundTests();
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

  group('AnsiShell.of', () {
    testWidgets('is the bar through compact AND medium, up to lg', (
      tester,
    ) async {
      expect(await shellAt(tester, 390), AnsiShell.bar);
      expect(await shellAt(tester, 800), AnsiShell.bar);
      expect(await shellAt(tester, 1023), AnsiShell.bar);
    });

    testWidgets('is the icon rail from lg to just under xl', (tester) async {
      expect(await shellAt(tester, 1024), AnsiShell.rail);
      expect(await shellAt(tester, 1279), AnsiShell.rail);
    });

    testWidgets('is the full sidebar from xl up', (tester) async {
      expect(await shellAt(tester, 1280), AnsiShell.sidebar);
      expect(await shellAt(tester, 1920), AnsiShell.sidebar);
    });

    testWidgets('beside is the question a layout actually asks', (
      tester,
    ) async {
      expect(await shellAt(tester, 1023), isNot(predicate(_beside)));
      expect(await shellAt(tester, 1024), predicate(_beside));
    });
  });

  group('AnsiPane', () {
    Future<Rect> paneRect(
      WidgetTester tester,
      double width, {
      bool fullWidth = false,
      bool insideShellMeasure = false,
      double Function(BuildContext context)? measure,
    }) async {
      await pumpWindow(
        tester,
        width,
        AnsiPane(
          fullWidth: fullWidth,
          insideShellMeasure: insideShellMeasure,
          measure: measure,
          child: const SizedBox.expand(key: _childKey),
        ),
      );
      return tester.getRect(find.byKey(_childKey));
    }

    testWidgets('measures a pushed page at every width', (tester) async {
      expect((await paneRect(tester, 402)).width, 402);
      expect((await paneRect(tester, 800)).width, 640);
      expect((await paneRect(tester, 1440)).width, 640);
    });

    testWidgets('leaves a tab root to the shell while the bar is under it', (
      tester,
    ) async {
      // The shell wraps the branches AND the bar in one measure there; a second
      // wrap inside it would be the screen measuring itself.
      expect(
        (await paneRect(tester, 800, insideShellMeasure: true)).width,
        800,
      );
      // Beside the content there is no bar to keep company with, so the branch
      // root measures its own pane.
      expect(
        (await paneRect(tester, 1440, insideShellMeasure: true)).width,
        640,
      );
    });

    testWidgets('a full-width page takes the pane, but only once there IS a '
        'pane', (tester) async {
      // At bar the window IS the pane: a 900 px browser window stays one
      // column, which is what keeps the phone layout honest at every width.
      expect((await paneRect(tester, 900, fullWidth: true)).width, 640);
      expect((await paneRect(tester, 1440, fullWidth: true)).width, 1440);
    });

    testWidgets('a full-width TAB ROOT is the same page, still left to the '
        'shell under the bar', (tester) async {
      // The four tab roots pass both flags: the shell's one wrap holds while
      // the bar is under the content, and the pane is the root's own above it.
      expect(
        (await paneRect(
          tester,
          800,
          fullWidth: true,
          insideShellMeasure: true,
        )).width,
        800,
      );
      expect(
        (await paneRect(
          tester,
          1440,
          fullWidth: true,
          insideShellMeasure: true,
        )).width,
        1440,
      );
    });

    testWidgets('a wider cap is a cap, not an opt-out — it holds at every '
        'width the wrap does', (tester) async {
      // `/recipes/:id` asks for this: two columns read together, capped at a
      // measure and a half plus the page's gutters, never stretched.
      expect(
        (await paneRect(tester, 402, measure: ansiWideMeasureWidth)).width,
        402,
      );
      expect(
        (await paneRect(tester, 800, measure: ansiWideMeasureWidth)).width,
        640,
      );
      expect(
        (await paneRect(tester, 1440, measure: ansiWideMeasureWidth)).width,
        640 * 1.5 + ansiPageGutter * 2,
      );
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

bool _beside(AnsiShell form) => form.beside;

// The ground past the measure is the board's paper, and the page inside it
// keeps its surface. Nothing else paints there: on iOS the root view is black,
// on the web it is the document body, and a centred page must not show either.
void _groundTests() {
  testWidgets('the measure paints paper past the page and surface under it', (
    tester,
  ) async {
    await pumpWindow(
      tester,
      800,
      const AnsiMeasure(
        child: SizedBox(key: _childKey, width: double.infinity, height: 40),
      ),
    );
    final boxes = tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .map((b) => b.color)
        .toList();
    expect(boxes, containsAll([AnsiColors.paper, AnsiColors.surface]));
    final paper = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == AnsiColors.paper,
    );
    expect(tester.getSize(paper).width, 800);
    final surface = find.byWidgetPredicate(
      (w) => w is ColoredBox && w.color == AnsiColors.surface,
    );
    expect(tester.getSize(surface).width, 640);
  });

  testWidgets('a phone is not painted over: the child comes back bare', (
    tester,
  ) async {
    await pumpWindow(
      tester,
      402,
      const AnsiMeasure(child: SizedBox(key: _childKey, height: 40)),
    );
    expect(find.byType(ColoredBox), findsNothing);
  });
}
