/// The muted line under the macro fields that says a panel disagrees with
/// itself. It sits in the derivation's slot and blocks nothing. The rule is
/// [macrosDoubt], in `core/units`.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/macros_consistency.dart';
import 'macros_format.dart';

class MacrosDoubtLine extends StatelessWidget {
  const MacrosDoubtLine({required this.stored, super.key});

  /// What Save would store, per 100 of the basis. Null while the panel is
  /// blank, half-typed or waiting on a serving amount; the line then says
  /// nothing.
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
