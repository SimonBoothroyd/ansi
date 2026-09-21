/// The app's Forui theme ([ansiThemeData]) and the Material host theme
/// ([ansiHostTheme]) behind it.
///
/// Three type roles: serif ([ansiSerif]) for titles, sans ([ansiSans]) for
/// interface text, mono ([ansiMono]) for data. All faces are bundled. Every
/// role names its own family: a style with only a fallback list inherits its
/// primary family from the nearest [DefaultTextStyle].
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
  final typography = FTypography.inherit(
    colors: colors,
    touch: true,
    // The same string Forui defaults to, stated so the interface face does
    // not depend on Forui's default.
    // ignore: avoid_redundant_argument_values
    fontFamily: ansiSansFamily,
  );
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

/// Every Forui tappable's pointer and focus answers, stated once.
///
/// Forui's cursor defaults to `MouseCursor.defer`, which on the web never
/// leaves the arrow; here an enabled tappable gets the click cursor. The
/// focus ring is 2 px at 2 px clear, where Forui's 1 px is hard to see.
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

/// The header's glyphs on hover: the ink steps to `secondaryForeground`.
///
/// `FHeaderActionStyle` has no ground to tint, and Forui's default hover
/// lightens near-black, which is invisible on paper.
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

/// The toast: bottom-centre, clear of header actions, and capped at the
/// measure (`breakpoints.sm`).
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

/// The bottom bar's selected item in herbDeep, so it is separable from the
/// muted unselected items at a glance. Weight and the unselected state stay
/// Forui's. `test/core/theme/ansi_theme_test.dart` measures the contrast.
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

/// The interface face. Inter is bundled by Forui, and a package's font is
/// registered as `packages/<package>/<family>`; plain `Inter` finds nothing.
const String ansiSansFamily = 'packages/forui/Inter';

const List<String> _serifStack = ['Spectral', 'Georgia', 'serif'];
const List<String> _monoStack = ['IBM Plex Mono', 'Menlo', 'monospace'];
const List<String> _sansStack = [
  ansiSansFamily,
  'Helvetica Neue',
  'sans-serif',
];

/// The serif's sizes, one per role.
///
/// Pass one of these to [ansiSerif]:
/// `test/structure/serif_sizes_come_from_the_scale_test.dart` fails on a
/// numeric literal outside this file.
abstract final class AnsiType {
  /// A page's in-body hero title, and the wordmark on the gate screens.
  static const double display = 33;

  /// A title over a body: a book page's name, the wide Week's day name.
  static const double title = 24;

  /// Header bar, sheet and dialog titles ([ansiHeaderTitle]), a book's name
  /// over its recipes, and an empty screen's lead sentence.
  static const double heading = 20;

  /// A recipe's name in a list, a dish on the Week, a day heading on the
  /// phone, a form's section title.
  static const double row = 17;

  /// A dense line that is one of many: a ledger recipe row, an index entry,
  /// a section label.
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

/// The serif's face and size as a delta, for text drawn by a Forui component.
/// It leaves the component's own colours alone.
TextStyleDelta ansiSerifDelta({required double size}) => TextStyleDelta.delta(
  fontFamily: 'Spectral',
  fontFamilyFallback: _serifStack,
  fontSize: size,
  height: 1.15,
);

/// The header bar title, for every `FHeader`. The recipe page uses an
/// in-body hero title instead.
TextStyle ansiHeaderTitle() => ansiSerif(size: AnsiType.heading);

/// A sans style for interface text and body copy. Names [ansiSansFamily]
/// itself so the face does not depend on where it is drawn.
TextStyle ansiSans({
  required double size,
  Color color = AnsiColors.ink,
  FontWeight weight = FontWeight.w400,
  double height = 1.3,
}) => TextStyle(
  fontFamily: ansiSansFamily,
  fontFamilyFallback: _sansStack,
  fontSize: size,
  height: height,
  color: color,
  fontWeight: weight,
);

/// IBM Plex Mono's cap height as a fraction of the font size
/// (`OS/2.sCapHeight`). A glyph set among figures is centred on it, because
/// `PlaceholderAlignment.middle` sits above the digits and moves with
/// [TextStyle.height].
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

/// [ansiMono] with no colour or weight, so an ancestor [DefaultTextStyle]
/// (a Forui bottom nav item, say) can drive both.
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
