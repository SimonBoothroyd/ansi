/// The chrome every sheet in the app wears, in one place.
///
/// [showAnsiSheet] is the only door onto the root navigator; this is the room
/// behind it. A sheet supplies its content and its header wording — the paper
/// ground, the radius-20 lip, the hairline above it, the side padding and the
/// bottom inset are not a per-sheet decision.
///
/// **The bottom pad is the reason this is shared.** It is
/// `max(viewInsets.bottom, padding.bottom) + 12`: the keyboard OR the home
/// indicator, whichever is up. A sheet that adds only `viewInsets.bottom`
/// looks right with a keyboard open and puts its confirm button under the
/// home-indicator gesture strip without one, where a tap either does nothing
/// or leaves the app.
///
/// **Header variants are options, not copies.** Centred serif 20 over an X is
/// the default; the meal sheets draw a left-aligned serif 22, the timer and
/// chip sheets a left 18 beside the X, the meal editor a text "Close" instead
/// of the glyph, and the filing sheet no dismiss glyph at all. Those are
/// designed differences, so they are named here rather than re-rolled.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_modals.dart';

/// How a sheet offers its way out.
enum AnsiSheetDismiss {
  /// The X glyph, leading the header row.
  x,

  /// A left chevron, leading the header row — for a sheet whose header is
  /// showing a mode reached from inside it, where the way out is back to the
  /// mode that opened it rather than out of the sheet.
  back,

  /// The word "Close", trailing the header row — for a sheet whose every
  /// control writes through, where "Close" is honest and "Save" would lie.
  close,

  /// Nothing in the header: the sheet is dismissed by its own confirm button
  /// or by the barrier.
  none,
}

class AnsiSheetShell extends StatelessWidget {
  const AnsiSheetShell({
    required this.children,
    this.title,
    this.subtitle,
    this.titleSize = 20,
    this.centerTitle = true,
    this.dismiss = AnsiSheetDismiss.x,
    this.onDismiss,
    this.heightFactor,
    this.topPadding = 12,
    this.scrollable = false,
    super.key,
  });

  /// The sheet's serif title. Null draws a header row holding only the
  /// dismiss affordance, for sheets that name themselves further down.
  final String? title;

  /// Mono context line under the title ("to · Wednesday, Dinner").
  final String? subtitle;

  final double titleSize;

  /// Centred over the X (the picker idiom) or aligned left beside it.
  final bool centerTitle;

  final AnsiSheetDismiss dismiss;

  /// What the dismiss affordance does. Defaults to popping the sheet's route,
  /// which is the modal itself — see [showAnsiSheet].
  final VoidCallback? onDismiss;

  /// A fraction of the screen height to pin the sheet to. Null sizes it to its
  /// content, which is what all but the search-driven sheets want.
  final double? heightFactor;

  final double topPadding;

  /// Scrolls the whole content column rather than expecting the sheet to lay
  /// out an [Expanded] or [Flexible] scroller of its own.
  final bool scrollable;

  /// The sheet's own rows, appended under the header. They join the shell's
  /// [Column] directly, so an [Expanded] body still measures against the
  /// sheet's height rather than against a nested column's.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.only(
      left: 20,
      right: 20,
      top: topPadding,
      bottom:
          math.max(
            MediaQuery.viewInsetsOf(context).bottom,
            MediaQuery.paddingOf(context).bottom,
          ) +
          12,
    );
    final column = Column(
      mainAxisSize: heightFactor == null ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [..._header(context), ...children],
    );

    return Container(
      height: heightFactor == null
          ? null
          : MediaQuery.sizeOf(context).height * heightFactor!,
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: scrollable
          ? SingleChildScrollView(padding: padding, child: column)
          : Padding(padding: padding, child: column),
    );
  }

  List<Widget> _header(BuildContext context) {
    final name = title;
    final row = Row(
      children: [
        if (dismiss == AnsiSheetDismiss.x ||
            dismiss == AnsiSheetDismiss.back) ...[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss ?? () => Navigator.of(context).pop(),
            child: Icon(
              dismiss == AnsiSheetDismiss.x
                  ? FLucideIcons.x
                  : FLucideIcons.chevronLeft,
              size: 22,
            ),
          ),
          if (name != null && !centerTitle) const SizedBox(width: 12),
        ],
        if (name != null)
          if (centerTitle) ...[
            Expanded(
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: ansiSerif(size: titleSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Balances the leading glyph so the title sits on the sheet's
            // centre line.
            if (dismiss != AnsiSheetDismiss.none &&
                dismiss != AnsiSheetDismiss.close)
              const SizedBox(width: 22),
          ] else
            Expanded(
              child: Text(
                name,
                style: ansiSerif(size: titleSize),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        if (dismiss == AnsiSheetDismiss.close)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss ?? () => Navigator.of(context).pop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                'Close',
                style: ansiSans(size: 14, color: AnsiColors.herbDeep),
              ),
            ),
          ),
      ],
    );

    return [
      if (row.children.isNotEmpty) row,
      if (subtitle != null) ...[
        const SizedBox(height: 6),
        Text(
          subtitle!,
          textAlign: centerTitle ? TextAlign.center : TextAlign.start,
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
      ],
    ];
  }
}
