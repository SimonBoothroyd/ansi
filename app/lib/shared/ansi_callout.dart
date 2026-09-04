/// A tinted note beside an icon: the app's one way of saying "read this".
///
/// Two shapes, one anatomy. The default is a **boxed** callout — the amber
/// block under a gap card, the blue freezer note — bordered and rounded,
/// living inside the content it comments on. [AnsiCallout.banner] is the
/// **full-bleed** one the shell hangs at the top of the app: edge to edge, a
/// hairline underneath instead of a border around, because it is a fact about
/// the app rather than about the card it happens to sit above.
///
/// The [AnsiTone] carries the palette, so a caution is the same amber
/// everywhere and a hold is the same blue. The wording is the caller's; the
/// wash, the border, the icon size and the indent are not.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

class AnsiCallout extends StatelessWidget {
  const AnsiCallout({
    required this.tone,
    required this.icon,
    required this.body,
    this.title,
    this.action,
    this.onAction,
    super.key,
  }) : _full = false;

  /// The shell's own band: full width, a hairline under it, and its action as
  /// a word at the end of the row rather than a button below the text.
  const AnsiCallout.banner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    super.key,
  }) : _full = true;

  final AnsiTone tone;
  final IconData icon;

  /// The headline, in the tone's ink. Null leaves [body] alone beside the
  /// icon — the one-line note shape.
  final String? title;

  final String body;

  /// The one thing to do about it, if there is one — "Set the yield", "Try
  /// now". Drawn under the text when boxed, at the end of the row when full.
  final String? action;
  final VoidCallback? onAction;

  final bool _full;

  @override
  Widget build(BuildContext context) {
    final heading = title;
    final label = action;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (heading != null) ...[
          Text(
            heading,
            style: ansiSans(
              size: _full ? 13 : 12.5,
              color: tone.ink,
              weight: FontWeight.w600,
            ),
          ),
          SizedBox(height: _full ? 2 : 4),
          Text(
            body,
            style: _full
                ? ansiMono(size: 10.5, color: AnsiColors.muted)
                : ansiMono(size: 11, color: tone.ink).copyWith(height: 1.5),
          ),
        ] else
          Text(body, style: ansiSans(size: 12, color: tone.ink)),
      ],
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: _full ? 2 : 1),
          child: Icon(icon, size: _full ? 15 : 14, color: tone.ink),
        ),
        SizedBox(width: _full ? 10 : 8),
        Expanded(child: text),
        if (_full && label != null) ...[
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(label, style: ansiMono(size: 11, color: tone.ink)),
            ),
          ),
        ],
      ],
    );

    if (_full) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: BoxDecoration(
          color: tone.fill,
          border: Border(bottom: BorderSide(color: tone.line)),
        ),
        child: row,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: tone.fill,
        border: Border.all(color: tone.line),
        borderRadius: BorderRadius.circular(AnsiRadii.box),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (label != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: tone.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: ansiMono(size: 12, color: tone.ink),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
