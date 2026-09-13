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

/// The widest a column of content is drawn: the theme's `sm` breakpoint, which
/// is also the ceiling of [AnsiLayout.compact].
///
/// The toast reads the same number off the theme rather than through this
/// function, because it is styled where there is no context to ask
/// (`core/theme/ansi_theme.dart`).
double ansiMeasureWidth(BuildContext context) => context.theme.breakpoints.sm;

/// Centres its child in a column no wider than the measure.
///
/// A **no-op at [AnsiLayout.compact]** — it returns the child untouched, so on
/// a phone this widget costs nothing and changes no layout at all. From
/// [AnsiLayout.medium] up it pins the child to [ansiMeasureWidth] and centres
/// it horizontally, leaving it at the top of whatever space it was given.
///
/// It is applied in two places, and should stay that way: the tab shell wraps
/// everything it owns (`shared/ansi_tab_shell.dart`), and the router wraps
/// every page pushed over the shell (`core/router/app_router.dart`). A screen
/// does not wrap itself.
class AnsiMeasure extends StatelessWidget {
  const AnsiMeasure({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AnsiLayout.of(context) == AnsiLayout.compact) return child;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ansiMeasureWidth(context)),
        child: child,
      ),
    );
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
