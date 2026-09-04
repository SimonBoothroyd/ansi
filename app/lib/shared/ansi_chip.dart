/// A pill you can pick: a label in a rounded outline that fills in when it is
/// the chosen one.
///
/// The app picks with pills in four places — the week's per-eater lens, the
/// portion-factor picks, the picker tabs, and the add-item sheet's two modes —
/// and they were four widgets drawing the same shape with four paddings. The
/// shape is here; what stays a caller's business is the wording, the tone and
/// whether the row shares its width.
///
/// **Two tones, and they mean different things.** [AnsiChipTone.herb] is a
/// *filter*: the herb wash says "this is what you are looking at", and the
/// unpicked chips beside it are still live choices. [AnsiChipTone.ink] is a
/// *tab*: solid ink says "this is the page you are on", and the others are
/// where you are not. A filter that painted itself like a tab would claim the
/// screen belongs to it.
///
/// Not every pill in the app is one of these: a unit chip and the mode chip
/// carry their own trailing anatomy, and they stay their own widgets.
library;

import 'package:flutter/widgets.dart';

import '../core/theme/ansi_theme.dart';
import '../core/theme/ansi_tokens.dart';

enum AnsiChipTone { herb, ink }

class AnsiChip extends StatelessWidget {
  const AnsiChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tone = AnsiChipTone.herb,
    this.icon,
    this.mono = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final AnsiChipTone tone;

  /// Something small in front of the label — an eater's avatar, not a glyph
  /// the label could have said itself.
  final Widget? icon;

  /// Mono for a chip whose label is a number or a machine word (`×¾`,
  /// `Recent`); sans for a chip that names a person or a thing.
  final bool mono;

  /// Takes an equal share of its row rather than sizing to the label — the
  /// two-mode row, where the pair reads as one control.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final solid = tone == AnsiChipTone.ink;
    final fill = selected
        ? (solid ? AnsiColors.ink : AnsiColors.herbSoft)
        : AnsiColors.surface;
    final edge = selected
        ? (solid ? AnsiColors.ink : AnsiColors.herb)
        : AnsiColors.line;
    final ink = selected
        ? (solid ? AnsiColors.surface : AnsiColors.ink)
        : AnsiColors.muted;
    final weight = selected && !solid ? FontWeight.w600 : FontWeight.w400;
    final text = Text(
      label,
      textAlign: expand ? TextAlign.center : null,
      style: mono
          ? ansiMono(size: expand ? 11.5 : 12, color: ink, weight: weight)
          : ansiSans(size: 13, color: ink, weight: weight),
    );

    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: _padding,
        alignment: expand ? Alignment.center : null,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: edge),
          borderRadius: BorderRadius.circular(AnsiRadii.pill),
        ),
        child: icon == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [icon!, const SizedBox(width: 6), text],
              ),
      ),
    );
    return expand ? Expanded(child: chip) : chip;
  }

  EdgeInsets get _padding {
    if (expand) return const EdgeInsets.symmetric(vertical: 9);
    if (tone == AnsiChipTone.ink) {
      return const EdgeInsets.symmetric(horizontal: 16, vertical: 7);
    }
    // An avatar sits closer to its edge than a word does.
    return mono
        ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
        : EdgeInsets.fromLTRB(icon == null ? 12 : 5, 5, 12, 5);
  }
}
