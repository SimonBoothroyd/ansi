/// The one muted line under the macro fields that says a panel argues with
/// itself.
///
/// It sits in the derivation's slot and wears its clothes — same size, same
/// muted mono — because it is the same kind of remark: something the app
/// noticed about the figures on screen, said before Save rather than
/// discovered in a week's totals afterwards. **It blocks nothing.** The
/// refusal voice belongs to the dock, and a panel a person read off a pack is
/// theirs whatever the arithmetic thinks of it.
///
/// The rule itself is [macrosDoubt], in `core/units` — this file is only how
/// a person hears it.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/macros_consistency.dart';
import 'macros_format.dart';

class MacrosDoubtLine extends StatelessWidget {
  const MacrosDoubtLine({required this.stored, super.key});

  /// What Save would STORE, per 100 of the basis — the figures the doubt is
  /// about. Null while the panel is blank, half-typed, or waiting on a
  /// serving amount, and the line then says nothing: there is no arithmetic
  /// to doubt yet.
  final Macros? stored;

  @override
  Widget build(BuildContext context) {
    final line = switch (macrosDoubt(stored)) {
      MacrosAllZero() =>
        'the label’s macros are all zero for a food with calories',
      MacrosEnergyGap(:final impliedKcal) =>
        'these numbers don’t add up: about ${formatKcal(impliedKcal)} kcal '
            'from the macros',
      null => null,
    };
    if (line == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(line, style: ansiMono(size: 10, color: AnsiColors.aging)),
    );
  }
}
