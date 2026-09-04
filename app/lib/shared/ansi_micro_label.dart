/// The uppercase micro-label that names a field: `YIELD`, `WHO'S EATING`.
///
/// It is [ansiLabel] — mono 11, letter-spaced 1.5 — plus the gap to the field
/// under it, because the gap is part of naming a thing: a label floating
/// equidistant between two fields names neither.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

class AnsiMicroLabel extends StatelessWidget {
  const AnsiMicroLabel(
    this.text, {
    this.suffix,
    this.hint,
    this.suffixColor = AnsiColors.muted,
    this.gap = 8,
    super.key,
  });

  final String text;

  /// The qualifier that rides beside the name (`MAKES · optional`), in a
  /// quieter mono — and in [suffixColor] when it is flagging something.
  final String? suffix;

  /// A qualifier that has grown into a sentence ("enter them as the label
  /// reads"), demoted to its own line UNDER the label. In [ansiLabel]'s
  /// letter-spaced uppercase it would wrap onto two lines on a phone and read
  /// at the same weight as the heading above it; beside the label it would
  /// crowd the name out. So it goes below, one weight down.
  final String? hint;

  final Color suffixColor;

  /// The space between the label and what it names.
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(text.toUpperCase(), style: ansiLabel()),
              if (suffix case final suffix?) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    suffix,
                    style: ansiMono(size: 11, color: suffixColor),
                  ),
                ),
              ],
            ],
          ),
          if (hint case final hint?)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                hint,
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
        ],
      ),
    );
  }
}
