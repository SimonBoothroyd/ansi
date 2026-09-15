/// The app's Forui theme, built from the Ansi design tokens.
///
/// The Ansi visual identity lives in the [FThemeData] returned by
/// [ansiThemeData]; `app.dart` applies it via Forui's `FTheme`. A tiny Material
/// [ansiHostTheme] tints the `MaterialApp.router` host (the WidgetsApp
/// go_router needs) so nothing flashes un-themed behind the Forui tree.
///
/// Typography follows the design board's three roles:
/// * **serif** ([ansiSerif]) — recipe titles and lowercase group headers, at
///   the five sizes [AnsiType] names,
/// * **sans** (Forui's default) — all interface text,
/// * **mono** ([ansiMono]) — data: quantities, units, scale factors, and the
///   letter-spaced uppercase micro-labels ([ansiLabel]).
///
/// The exact faces (Spectral / Inter / IBM Plex Mono) are named first in each
/// fallback list; when they aren't bundled the platform's generic families take
/// over, preserving the hierarchy without any runtime font download.
library;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import 'ansi_tokens.dart';

/// The real Ansi theme: Forui's Zinc light theme recoloured with [AnsiColors].
FThemeData ansiThemeData() {
  final colors = FColors.zincLight.copyWith(
    background: AnsiColors.surface,
    foreground: AnsiColors.ink,
    primary: AnsiColors.herb,
    primaryForeground: AnsiColors.paper,
    secondary: AnsiColors.herbSoft,
    secondaryForeground: AnsiColors.herbDeep,
    muted: AnsiColors.herbSoft,
    mutedForeground: AnsiColors.muted,
    border: AnsiColors.line,
    card: AnsiColors.surface,
  );
  final typography = FTypography.inherit(colors: colors, touch: true);
  final base = FThemeData(
    colors: colors,
    touch: true,
    typography: typography,
    style: _style(colors, typography),
    debugLabel: 'Ansi',
  );
  return base.copyWith(
    bottomNavigationBarStyle: _bottomNavStyle(),
    headerStyles: _headerStyles(),
    toasterStyle: _toasterStyle(base),
  );
}

/// The two answers every tappable thing in the app owes a mouse and a keyboard,
/// stated once on the theme rather than fifty times at the call sites.
///
/// **A click cursor.** Forui's [FTappableStyle] defaults to
/// `MouseCursor.defer`, which on the web means the arrow never changes — so a
/// `⋯`, a sidebar item and a ghost button all read as text. Every Forui
/// tappable resolves its cursor from here, so one line gives the whole app a
/// pointer; a disabled one keeps the plain arrow, which is the honest word for
/// *not a door*.
///
/// **A ring you can see.** Forui's default is 1 px, 3 px clear. At 1 px, herb
/// on paper, a focused control is a rumour. 2 px at 2 px clear is the board's
/// ring: thick enough to find by eye while tabbing, tight enough that it does
/// not read as a second selected state. `AnsiTap` (`shared/ansi_tap.dart`)
/// inherits it and re-states only the radius.
FStyle _style(FColors colors, FTypography typography) =>
    FStyle.inherit(
      colors: colors,
      typography: typography,
      touch: true,
    ).copyWith(
      focusedOutlineStyle: const FFocusedOutlineStyleDelta.delta(
        width: 2,
        spacing: 2,
      ),
      tappableStyle: FTappableStyleDelta.delta(
        cursor: FVariantsValueDelta.delta([
          FVariantValueDeltaOperation.base(SystemMouseCursors.click),
          FVariantValueDeltaOperation.exact({
            FTappableVariantConstraint.disabled,
          }, SystemMouseCursors.basic),
        ]),
      ),
    );

/// The header's own glyphs — the back chevron, the `⋯`, the `＋` — answering a
/// pointer in the same two colours as everything else.
///
/// `FHeaderAction` is an `FTappable` already: it hovers, it rings, and after
/// [_style] it has a cursor. What it hovered *with* was `colors.hover(ink)`, a
/// lightening of near-black that on paper is invisible — the owner's "no
/// response" — and `FHeaderActionStyle` has no ground in its contract to tint
/// instead. So here the glyph carries the whole answer: its ink steps to
/// `secondaryForeground`, the same herb-deep an `AnsiTap` moves its glyph to.
/// Deliberately not a fork of Forui's header action with a ground bolted on:
/// the two tokens *are* the shared style, and this is them in the one shape
/// that cannot hold a ground.
FVariantsDelta<
  FHeaderVariantConstraint,
  FHeaderVariant,
  FHeaderStyle,
  FHeaderStyleDelta
>
_headerStyles() {
  const hover = IconThemeDataDelta.delta(color: AnsiColors.herbDeep);
  return FVariantsDelta.delta([
    FVariantOperation.all(
      FHeaderStyleDelta.delta(
        actionStyle: FHeaderActionStyleDelta.delta(
          iconStyle: FVariantsDelta.delta([
            FVariantOperation.exact({
              FTappableVariantConstraint.hovered,
            }, hover),
            FVariantOperation.exact({
              FTappableVariantConstraint.pressed,
            }, hover),
          ]),
        ),
      ),
    ),
  ]);
}

/// The toast: bottom-centre, and never wider than the measure.
///
/// Both are facts about the app rather than about one call site, so they are
/// stated here once — `showFToast` falls back to `toastAlignment` when a caller
/// names no alignment, and the cap rides on every toast variant.
///
/// **Bottom-centre**, because a toast at the top of the window would sit over a
/// screen's header, which is where every header action lives. **Capped at the
/// measure** — `breakpoints.sm`, the width every page is drawn in
/// (`shared/ansi_layout.dart`) — because a toast wider than the column it
/// reports on reads as a second, competing layout. On a phone neither this cap
/// nor Forui's own is ever reached.
FToasterStyleDelta _toasterStyle(FThemeData base) => FToasterStyleDelta.delta(
  toastAlignment: FToastAlignment.bottomCenter,
  toastStyles: FVariantsDelta.delta([
    FVariantOperation.all(
      FToastStyleDelta.delta(
        constraints: base.toasterStyle.toastStyles.primary.constraints.copyWith(
          maxWidth: base.breakpoints.sm,
        ),
      ),
    ),
  ]),
);

/// The bottom bar's selected item, stepped herb → herbDeep.
///
/// With the week switcher as every tab's title, the lit tab carries the whole
/// "where am I", so the two states have to be separable at a glance. Forui's
/// default puts them 1.31:1 apart (selected = primary, herb 6.50:1 on the bar's
/// white; unselected = mutedForeground, muted 4.97:1). herbDeep is 9.34:1 on
/// surface and 1.88:1 from muted — the same darkening `secondaryForeground`
/// already uses, so no new colour enters the palette. Only the selected
/// variant's colour changes; its weight (700 / bold) and the unselected state
/// stay Forui's. `test/core/theme/ansi_theme_test.dart` measures both ratios.
FBottomNavigationBarStyleDelta _bottomNavStyle() =>
    FBottomNavigationBarStyleDelta.delta(
      itemStyle: FBottomNavigationBarItemStyleDelta.delta(
        iconStyle: FVariantsDelta.delta([
          FVariantOperation.exact({
            FTappableVariantConstraint.selected,
          }, const IconThemeDataDelta.delta(color: AnsiColors.herbDeep)),
        ]),
        textStyle: FVariantsDelta.delta([
          FVariantOperation.exact({
            FTappableVariantConstraint.selected,
          }, const TextStyleDelta.delta(color: AnsiColors.herbDeep)),
        ]),
      ),
    );

/// A minimal Material theme for the `MaterialApp.router` host so the window
/// paints paper, not white, behind the Forui components.
ThemeData ansiHostTheme() => ThemeData(
  scaffoldBackgroundColor: AnsiColors.surface,
  canvasColor: AnsiColors.surface,
  useMaterial3: true,
);

const List<String> _serifStack = ['Spectral', 'Georgia', 'serif'];
const List<String> _monoStack = ['IBM Plex Mono', 'Menlo', 'monospace'];
// Inter comes from Forui (its default family), not a separate bundle.
const List<String> _sansStack = ['packages/forui/Inter'];

/// The serif's sizes, one per **role** rather than one per call site.
///
/// A title's size follows from *what the title is*, so two screens showing
/// the same kind of thing cannot drift a pixel apart. A number chosen at a
/// call site says how big this one is and nothing about why, which gives the
/// next screen to draw a recipe's name nothing to copy but a guess.
///
/// Pass one of these to [ansiSerif] and nothing else:
/// `test/structure/serif_sizes_come_from_the_scale_test.dart` fails on a
/// numeric literal anywhere outside this file. A new size is a new role, and a
/// new role is a line here with the places it is used.
abstract final class AnsiType {
  /// The one big in-body hero title a page is named by: the recipe page, the
  /// ingredient page, and the wordmark on the sign-in and connecting screens.
  static const double display = 33;

  /// A title over a body that is not the app bar's: a book page's name, the
  /// wide Week's day name.
  static const double title = 24;

  /// A header bar's title ([ansiHeaderTitle]), a sheet's or dialog's title, a
  /// book's name wherever it heads its recipes, the sidebar's wordmark, and
  /// the sentence an empty or failed screen leads with.
  static const double heading = 20;

  /// A recipe's name in a list, a dish on the Week, a planned slot, a day
  /// heading on the phone, a section title inside a form, and the italic
  /// heading that names a group of ingredient lines.
  static const double row = 17;

  /// A dense line that is one of many: the Library ledger's recipe row, a
  /// book page's index entry, the wide Week agenda's day, a pickable row in a
  /// filing sheet, and the italic label that divides a list into sections.
  static const double small = 15;
}

/// A serif style for titles and group headers. [size] comes from [AnsiType].
TextStyle ansiSerif({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w600,
}) => TextStyle(
  fontFamily: 'Spectral',
  fontFamilyFallback: _serifStack,
  fontSize: size,
  height: 1.15,
  color: color,
  fontWeight: weight,
);

/// The serif's face and metrics as a *delta*, for the few places the text is
/// drawn by a Forui component rather than by a [Text] of ours.
///
/// A component owns the ink of its own content and hint — a text field greys
/// its placeholder, lights its value — so a style that replaced them wholesale
/// would flatten those states. This changes the face and the size and leaves
/// every colour the component chose alone.
TextStyleDelta ansiSerifDelta({required double size}) => TextStyleDelta.delta(
  fontFamily: 'Spectral',
  fontFamilyFallback: _serifStack,
  fontSize: size,
  height: 1.15,
);

/// The app-bar page title — one consistent serif across every screen's header
/// (design board `.ttl`), so the top bars read as one family. Use it for the
/// `FHeader`/`FHeader.nested` title on every screen. The recipe page is the
/// deliberate exception: a large in-body hero title instead of a bar title.
TextStyle ansiHeaderTitle() => ansiSerif(size: AnsiType.heading);

/// A sans style for interface text and ingredient/step body copy.
TextStyle ansiSans({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w400,
  double height = 1.3,
}) => TextStyle(
  fontFamilyFallback: _sansStack,
  fontSize: size,
  height: height,
  color: color,
  fontWeight: weight,
);

/// IBM Plex Mono's cap height, as a fraction of the font size (the face's own
/// `OS/2.sCapHeight`, 698/1000 em). A digit's ink runs from the baseline up to
/// exactly this.
///
/// It is the measurement a glyph set among figures is centred on. The
/// alternative — the font's ascent/descent midpoint, which is what
/// `PlaceholderAlignment.middle` uses — sits above the digits and moves with
/// [TextStyle.height], so one glyph rides at a different altitude on every
/// line the app draws.
const double kMonoCapHeight = 0.698;

/// A monospace style for data (quantities, units, scale factors).
TextStyle ansiMono({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w400,
  double letterSpacing = 0,
}) => ansiMonoInherit(
  size: size,
  letterSpacing: letterSpacing,
).copyWith(color: color, fontWeight: weight);

/// [ansiMono] with no colour and no weight of its own, so both are inherited
/// from an ancestor [DefaultTextStyle].
///
/// A [Text]'s own style wins over the inherited one field by field, so a widget
/// whose selected/unselected colouring is driven from above — a Forui bottom
/// nav item, say — must leave those two fields unset or it opts itself out.
TextStyle ansiMonoInherit({required double size, double letterSpacing = 0}) =>
    TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontFamilyFallback: _monoStack,
      fontSize: size,
      letterSpacing: letterSpacing,
    );

/// The letter-spaced uppercase micro-label ("FIND AN INGREDIENT", "SERVES").
TextStyle ansiLabel({Color color = AnsiColors.muted}) => ansiMono(
  size: 11,
  color: color,
  weight: FontWeight.w500,
  letterSpacing: 1.5,
);
