/// *was “sausage” · keep the old word* — the app's one-tap revert line.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

/// The line the app prints wherever it changed a **word** a person wrote.
///
/// The app rewrites a word in two places, for the same reason: a method chip
/// whose line was re-matched, and an ingredient name the form recognised as a
/// recipe line. Both are the app deciding it knows the noun better than the
/// typist did, and both owe the same manners — say what the word was, and make
/// putting it back one tap. Casing and spacing changes are *not* this: they
/// alter no word, so they are silent.
///
/// Drawn under the thing that moved: the step card, or the name field.
class WasWordLine extends StatelessWidget {
  const WasWordLine({required this.oldWord, required this.onKeep, super.key});

  /// The word as the person wrote it — printed in quotes.
  final String oldWord;

  /// Puts [oldWord] back. What that means belongs to the caller: the editor
  /// relabels the chip, the ingredient form restores and pins the typed name.
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        // The old word is whatever the page printed — "the sauce and cheese"
        // is a real one — and the revert beside it has to stay reachable
        // whatever its length, on a card as narrow as the review's. So the
        // word yields and the action keeps its width.
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
