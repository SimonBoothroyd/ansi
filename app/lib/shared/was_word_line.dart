/// *was “sausage” · keep the old word* — the app's one-tap revert line.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

/// The line printed wherever the app changed a word a person wrote: it says
/// what the word was and puts it back in one tap.
///
/// Used under a re-matched method chip and under a recognised ingredient
/// name. Casing and spacing changes are silent.
class WasWordLine extends StatelessWidget {
  const WasWordLine({required this.oldWord, required this.onKeep, super.key});

  /// The word as the person wrote it, printed in quotes.
  final String oldWord;

  /// Puts [oldWord] back; what that means belongs to the caller.
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        // The old word can be long, so it yields and the action keeps its
        // width.
        Expanded(
          child: Text(
            'was “$oldWord”',
            style: ansiMono(size: 11, color: AnsiColors.aging),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        FButton(
          variant: FButtonVariant.ghost,
          size: FButtonSizeVariant.sm,
          onPress: onKeep,
          child: const Text('keep the old word'),
        ),
      ],
    ),
  );
}
