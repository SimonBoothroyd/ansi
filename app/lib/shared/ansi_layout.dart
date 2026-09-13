/// **The only file under `lib/` that reads the viewport.**
///
/// Everything else in the app is written for one width and never asks how wide
/// the window is. That is the rule, and it is held by
/// `test/structure/one_viewport_reader_test.dart`, which fails the build if
/// `MediaQuery.sizeOf`, `MediaQuery.of(context).size` or a `LayoutBuilder`
/// appears anywhere else under `lib/`.
///
/// **Why one reader.** A screen that measures itself is a screen that answers
/// the width question its own way, and fifteen screens answer it fifteen ways:
/// one caps at 600, the next at 700, a third forgets and stretches a row of
/// checkboxes across a desktop monitor. Worse, each read is a second source of
/// truth for "what is a phone" — so a breakpoint moves in one file and the app
/// disagrees with itself. Here the question is asked once, in the app's own
/// vocabulary ([AnsiLayout]), and the answer is applied structurally by one
/// widget ([AnsiMeasure]) that every page sits inside.
///
/// **The bands** come from Forui's own `FBreakpoints` on the theme, not from
/// numbers typed here: compact below `sm`, medium up to `lg`, expanded from
/// `lg` up. Change them on the theme and the whole app moves together.
///
/// **The measure** — the width a column of content is ever drawn at — is `sm`
/// itself, the widest a compact window can be. So a page on a desk is the page
/// on a phone, centred, with nothing reflowed and nothing to re-verify: a
/// screen that wants to *use* the width asks for it deliberately, by not
/// sitting in the measure.
///
/// **The shell's form** is the second question this file answers
/// ([AnsiShell.of]): whether the app's navigation is a bar under the content,
/// an icon rail beside it, or a full sidebar. It is a different question from
/// the band — the bar covers two bands, and the rail/sidebar split falls inside
/// one — so it is its own vocabulary rather than a `switch` on [AnsiLayout]
/// repeated in three files.
///
/// What a screen may do with width: nothing. What it may do instead: ask
/// [AnsiLayout.of] for a band, in the rare case where the honest answer differs
/// by band rather than by pixel. See
/// `docs/design-docs/wide-screen.md`.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// The three widths the app designs for.
///
/// Read from the window's width against the theme's `FBreakpoints`:
/// [compact] below `sm` (640), [medium] from `sm` to just under `lg`
/// (640–1023), [expanded] from `lg` (1024) up. A phone in either orientation
/// is [compact]; a tablet in portrait and a half-screen browser are [medium];
/// a landscape tablet and a desktop browser are [expanded].
enum AnsiLayout {
  /// One column, edge to edge — the layout every screen is written for.
  compact,

  /// Wide enough that the phone layout would stretch, not wide enough for a
  /// second region beside it.
  medium,

  /// Room for chrome beside the content.
  expanded;

  /// The band [context]'s window falls in.
  ///
  /// Depends on the media query, so a widget that calls this rebuilds when the
  /// window is resized or the device rotated.
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

/// The form the app's navigation chrome takes at a given width.
///
/// Read from the window's width against the theme's `FBreakpoints`: [bar] below
/// `lg` (1024), [rail] from `lg` to just under `xl` (1024–1279), [sidebar] from
/// `xl` (1280) up.
///
/// Deliberately not a view on [AnsiLayout]: [bar] spans both [AnsiLayout
/// .compact] and [AnsiLayout.medium] — a 900 px window is too wide for the
/// phone layout to stretch but too narrow to spend 188 px on chrome — while
/// [rail] and [sidebar] split [AnsiLayout.expanded] in two. Two questions, two
/// answers, asked in the same file.
enum AnsiShell {
  /// The bottom bar, under the content. The phone's shell, and the one a
  /// half-screen browser window keeps.
  bar,

  /// A 64 px icon rail beside the content, labels as tooltips — an iPad in
  /// landscape, where the labels would cost a sixth of the window.
  rail,

  /// The full sidebar beside the content: icons with their labels, and the
  /// wordmark above them.
  sidebar;

  /// The form [context]'s window calls for.
  ///
  /// Depends on the media query, so a widget that calls this rebuilds when the
  /// window is resized or the device rotated.
  static AnsiShell of(BuildContext context) {
    final breakpoints = context.theme.breakpoints;
    final width = MediaQuery.sizeOf(context).width;
    return switch (width) {
      _ when width < breakpoints.lg => bar,
      _ when width < breakpoints.xl => rail,
      _ => sidebar,
    };
  }

  /// Whether the chrome sits **beside** the content rather than under it, which
  /// is what makes the window's remainder a *pane* instead of the whole window.
  bool get beside => this != bar;
}

/// The widest a column of content is drawn: the theme's `sm` breakpoint, which
/// is also the ceiling of [AnsiLayout.compact].
///
/// The toast reads the same number off the theme rather than through this
/// function, because it is styled where there is no context to ask
/// (`core/theme/ansi_theme.dart`).
double ansiMeasureWidth(BuildContext context) => context.theme.breakpoints.sm;

/// The horizontal gutter a page pads its content by.
///
/// It lives beside the measure because the two are read together: a cap that
/// wants the *columns* inside a page to be a stated width has to add the
/// gutters back on.
const double ansiPageGutter = 20;

/// The cap for a page whose [AnsiLayout.expanded] form is **two columns**.
///
/// Below expanded it is [ansiMeasureWidth]: such a page is the phone's page,
/// centred, exactly like every other one. At expanded it is a measure and a
/// half of content plus the page's own [ansiPageGutter]s — two columns of Ansi
/// text side by side, together no wider than the app has ever read at, and the
/// number is still the theme's rather than a literal.
double ansiWideMeasureWidth(BuildContext context) =>
    AnsiLayout.of(context) == AnsiLayout.expanded
    ? ansiMeasureWidth(context) * 1.5 + ansiPageGutter * 2
    : ansiMeasureWidth(context);

/// Centres its child in a column no wider than the measure.
///
/// A **no-op at [AnsiLayout.compact]** — it returns the child untouched, so on
/// a phone this widget costs nothing and changes no layout at all. From
/// [AnsiLayout.medium] up it pins the child to [ansiMeasureWidth] and centres
/// it horizontally, leaving it at the top of whatever space it was given.
///
/// It is applied in two places, and should stay that way: the tab shell wraps
/// everything it owns while the bar is under the content
/// (`shared/ansi_tab_shell.dart`), and the router wraps every route in an
/// [AnsiPane] (`core/router/app_router.dart`). A screen does not wrap itself.
class AnsiMeasure extends StatelessWidget {
  const AnsiMeasure({required this.child, this.width, super.key});

  final Widget child;

  /// How wide this page is capped, given the band — [ansiMeasureWidth] when
  /// null, which is what every page that is a column by nature wants.
  ///
  /// A page whose expanded form uses the width passes [ansiWideMeasureWidth]
  /// instead. It is a function of the context rather than a number because the
  /// answer is the band's, and the band is read here.
  final double Function(BuildContext context)? width;

  @override
  Widget build(BuildContext context) {
    if (AnsiLayout.of(context) == AnsiLayout.compact) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (width ?? ansiMeasureWidth)(context),
        ),
        child: child,
      ),
    );
  }
}

/// One page's share of the window: the measure, unless the page is one of the
/// few that uses the width.
///
/// This is where [AnsiMeasure] is applied from, and the only place a page's
/// width is decided — `core/router/app_router.dart` wraps every route in one,
/// so the decision is a fact about the route rather than something a screen
/// does to itself.
///
/// [fullWidth] is the opt-out, for a view whose honest form spreads across the
/// pane (the Week's matrix, the Library's shelf). It applies only once the
/// chrome is beside the content: at [AnsiShell.bar] there is no pane to fill —
/// the window *is* the pane — so a full-width page still sits in the measure,
/// which is what keeps a 900 px browser window one column.
///
/// [insideShellMeasure] is for the four tab roots. At [AnsiShell.bar] the tab
/// shell wraps everything it owns — the branches *and* the bottom bar — in one
/// measure, because a bar stretched over a monitor above a 640-wide page is two
/// layouts; so a branch root must not wrap itself there. Once the chrome is
/// beside the content that single wrap is gone (there is no bar to keep company
/// with) and the branch root measures its own pane like any other page.
///
/// [measure] is the third answer, between the other two: a page that still sits
/// in one wrap but is not one column at its widest passes a resolver —
/// [ansiWideMeasureWidth] — and is capped by that instead of by
/// [ansiMeasureWidth]. It is a cap, not an opt-out, so it applies at every band
/// the wrap does.
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
    // Which flag is the opt-out depends on where the chrome is: under the
    // content the window IS the pane and the tab shell owns the one wrap;
    // beside it, the pane is the page's own and a page may ask for all of it.
    final opensOut = AnsiShell.of(context).beside
        ? fullWidth
        : insideShellMeasure;
    if (opensOut) return child;
    return AnsiMeasure(width: measure, child: child);
  }
}

/// A fraction [factor] of the window's height, for a sheet that is pinned to a
/// share of the screen rather than sized to its content.
///
/// This lives here for one reason: it reads the viewport, and reads of the
/// viewport live in this file. `shared/ansi_sheet_shell.dart` is its only
/// caller.
double ansiViewportHeight(BuildContext context, double factor) =>
    MediaQuery.sizeOf(context).height * factor;
