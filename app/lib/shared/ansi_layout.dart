/// The only file under `lib/` that reads the viewport, held by
/// `test/structure/one_viewport_reader_test.dart`.
///
/// Bands ([AnsiLayout]) and the shell's form ([AnsiShell]) come from the
/// theme's `FBreakpoints`; the measure is `sm`. A screen asks for a band,
/// never a pixel width. See `docs/design-docs/wide-screen.md`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_tokens.dart';

/// The three widths the app designs for, from the theme's `FBreakpoints`:
/// [compact] below `sm` (640), [medium] up to `lg` (1024), [expanded] above.
enum AnsiLayout {
  /// One column, edge to edge.
  compact,

  /// Too wide to stretch the phone layout, too narrow for a second region.
  medium,

  /// Room for chrome beside the content.
  expanded;

  /// The band of [context]'s window. Rebuilds the caller on resize.
  static AnsiLayout of(BuildContext context) {
    final breakpoints = context.theme.breakpoints;
    final width = MediaQuery.sizeOf(context).width;
    return switch (width) {
      _ when width < breakpoints.sm => compact,
      _ when width < breakpoints.lg => medium,
      _ => expanded,
    };
  }
}

/// The form the navigation chrome takes: [bar] below `lg` (1024), [rail] up
/// to `xl` (1280), [sidebar] above.
///
/// Not a view on [AnsiLayout]: [bar] spans two bands, and [rail] and
/// [sidebar] split [AnsiLayout.expanded].
enum AnsiShell {
  /// The bottom bar, under the content.
  bar,

  /// A 64 px icon rail beside the content, labels as tooltips.
  rail,

  /// The full sidebar: icons, labels and the wordmark.
  sidebar;

  /// The form [context]'s window calls for. Rebuilds the caller on resize.
  static AnsiShell of(BuildContext context) {
    final breakpoints = context.theme.breakpoints;
    final width = MediaQuery.sizeOf(context).width;
    return switch (width) {
      _ when width < breakpoints.lg => bar,
      _ when width < breakpoints.xl => rail,
      _ => sidebar,
    };
  }

  /// Whether the chrome sits beside the content, leaving it a pane.
  bool get beside => this != bar;
}

/// The widest a column of content is drawn: the theme's `sm` breakpoint.
double ansiMeasureWidth(BuildContext context) => context.theme.breakpoints.sm;

/// The horizontal gutter a page pads its content by.
const double ansiPageGutter = 20;

/// The cap for a page that is two columns at [AnsiLayout.expanded]: a measure
/// and a half plus the [ansiPageGutter]s. Below expanded, [ansiMeasureWidth].
double ansiWideMeasureWidth(BuildContext context) =>
    AnsiLayout.of(context) == AnsiLayout.expanded
    ? ansiMeasureWidth(context) * 1.5 + ansiPageGutter * 2
    : ansiMeasureWidth(context);

/// Centres its child in a column no wider than the measure; a no-op at
/// [AnsiLayout.compact].
///
/// Applied by the tab shell and by the router's [AnsiPane] only. A screen
/// does not wrap itself.
class AnsiMeasure extends StatelessWidget {
  const AnsiMeasure({required this.child, this.width, super.key});

  final Widget child;

  /// The cap, given the context; [ansiMeasureWidth] when null.
  final double Function(BuildContext context)? width;

  @override
  Widget build(BuildContext context) {
    if (AnsiLayout.of(context) == AnsiLayout.compact) return child;
    // Paint the ground either side of the column; otherwise the platform's
    // root view shows through (black on iOS).
    return ColoredBox(
      color: AnsiColors.paper,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (width ?? ansiMeasureWidth)(context),
          ),
          child: ColoredBox(color: AnsiColors.surface, child: child),
        ),
      ),
    );
  }
}

/// One page's share of the window; the only place a page's width is decided.
///
/// [fullWidth] hands over the whole pane, but only once the chrome is beside
/// the content. [insideShellMeasure] marks a tab root, which the tab shell
/// already measures at [AnsiShell.bar]. [measure] swaps the cap.
class AnsiPane extends StatelessWidget {
  const AnsiPane({
    required this.child,
    this.fullWidth = false,
    this.insideShellMeasure = false,
    this.measure,
    super.key,
  });

  final Widget child;

  /// The page uses the whole content pane instead of the measure.
  final bool fullWidth;

  /// The tab shell already measures this page at [AnsiShell.bar].
  final bool insideShellMeasure;

  /// How wide the wrap caps this page — [ansiMeasureWidth] when null.
  final double Function(BuildContext context)? measure;

  @override
  Widget build(BuildContext context) {
    // Under the content the tab shell owns the wrap; beside it a page may
    // take the whole pane.
    final opensOut = AnsiShell.of(context).beside
        ? fullWidth
        : insideShellMeasure;
    if (opensOut) return child;
    return AnsiMeasure(width: measure, child: child);
  }
}

/// [factor] of the window's height, for a sheet pinned to a share of the
/// screen. Here because viewport reads live in this file.
double ansiViewportHeight(BuildContext context, double factor) =>
    MediaQuery.sizeOf(context).height * factor;
