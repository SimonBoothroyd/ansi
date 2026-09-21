/// The chrome every sheet wears: ground, lip, hairline, padding and header.
///
/// The bottom pad is `max(viewInsets.bottom, padding.bottom) + 12`, the
/// keyboard or the home indicator, whichever is up. In the dialog form
/// ([AnsiModalSurface]) the pad is a plain 20, the lip goes, and a pinned
/// sheet fills the dialog's height. Header variants are options here.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';
import 'ansi_layout.dart';
import 'ansi_modals.dart';
import 'ansi_tap.dart';

/// How a sheet offers its way out.
enum AnsiSheetDismiss {
  /// The X glyph, leading the header row.
  x,

  /// A left chevron, leading the header row, for a mode reached from inside
  /// the sheet.
  back,

  /// The word "Close", trailing the header row, for a sheet whose every
  /// control writes through.
  close,

  /// Nothing in the header: the confirm button or the barrier dismisses.
  none,
}

class AnsiSheetShell extends StatelessWidget {
  const AnsiSheetShell({
    required this.children,
    this.title,
    this.subtitle,
    this.centerTitle = true,
    this.dismiss = AnsiSheetDismiss.x,
    this.onDismiss,
    this.heightFactor,
    this.topPadding = 12,
    this.scrollable = false,
    super.key,
  });

  /// The sheet's serif title. Null draws only the dismiss affordance.
  final String? title;

  /// Mono context line under the title ("to · Wednesday, Dinner").
  final String? subtitle;

  /// Centred over the X (the picker idiom) or aligned left beside it.
  final bool centerTitle;

  final AnsiSheetDismiss dismiss;

  /// What the dismiss affordance does. Defaults to popping the sheet's route.
  final VoidCallback? onDismiss;

  /// A fraction of the screen height to pin the sheet to, resolved through
  /// [ansiViewportHeight]. Null sizes it to its content.
  final double? heightFactor;

  final double topPadding;

  /// Scrolls the whole content column.
  final bool scrollable;

  /// The sheet's own rows. They join the shell's [Column] directly, so an
  /// [Expanded] body measures against the sheet's height.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // A centred dialog has no home-indicator strip and clears the keyboard
    // itself.
    final dialog = AnsiModalSurface.isDialog(context);
    final padding = EdgeInsets.only(
      left: 20,
      right: 20,
      top: topPadding,
      bottom: dialog
          ? 20
          : math.max(
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
      // A pinned sheet fills the dialog's own height.
      height: switch ((heightFactor, dialog)) {
        (null, _) => null,
        (_, true) => double.infinity,
        (final factor?, false) => ansiViewportHeight(context, factor),
      },
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        // A dialog has a ring of its own, so the lip and hairline go.
        borderRadius: dialog
            ? null
            : const BorderRadius.vertical(top: Radius.circular(20)),
        border: dialog
            ? null
            : const Border(top: BorderSide(color: AnsiColors.line)),
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
          AnsiTap(
            onTap: onDismiss ?? () => Navigator.of(context).pop(),
            semanticsLabel: dismiss == AnsiSheetDismiss.x ? 'Close' : 'Back',
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
                style: ansiSerif(size: AnsiType.heading),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Balances the leading glyph so the title stays centred.
            if (dismiss != AnsiSheetDismiss.none &&
                dismiss != AnsiSheetDismiss.close)
              const SizedBox(width: 22),
          ] else
            Expanded(
              child: Text(
                name,
                style: ansiSerif(size: AnsiType.heading),
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
