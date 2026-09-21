/// `−  value  +`: the row that changes a number by a step.
///
/// One Forui icon button either side, disabled where the step is not
/// available. The middle is a widget the caller draws.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

class AnsiStepperRow extends StatelessWidget {
  const AnsiStepperRow({
    required this.value,
    required this.onDecrement,
    required this.onIncrement,
    this.leading,
    this.trailing,
    this.small = false,
    super.key,
  });

  /// What the row reads, between the two buttons.
  final Widget value;

  /// Null at the floor or the ceiling, which disables the button.
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  /// What the row names, before the minus.
  final Widget? leading;

  /// What follows the plus, usually a unit word.
  final Widget? trailing;

  /// The compact size, for a row that holds two steppers side by side.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? FButtonSizeVariant.sm : FButtonSizeVariant.md;
    return Row(
      mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (leading case final leading?) leading,
        FButton.icon(
          size: size,
          onPress: onDecrement,
          child: const Icon(FLucideIcons.minus),
        ),
        value,
        FButton.icon(
          size: size,
          onPress: onIncrement,
          child: const Icon(FLucideIcons.plus),
        ),
        if (trailing case final trailing?) trailing,
      ],
    );
  }
}
