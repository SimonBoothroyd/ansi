/// The uppercase micro-label that names a field: `YIELD`, `WHO'S EATING`.
/// It is [ansiLabel] plus the gap to the field under it.
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

  /// The qualifier beside the name (`MAKES · optional`), in a quieter mono,
  /// or in [suffixColor] when it flags something.
  final String? suffix;

  /// A sentence-length qualifier, on its own line under the label, where it
  /// neither wraps in uppercase nor crowds the name.
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
