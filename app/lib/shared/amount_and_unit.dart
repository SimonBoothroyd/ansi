/// A number and the unit it is in, as one control inside a line of prose.
///
/// The unit slot is a single selected [UnitChip] that opens
/// [showUnitPickSheet]. Both slots are [kInlineControlHeight] tall, and a host
/// sizes whatever sits beside them to match. The amount text is handed back as
/// typed; parsing is the caller's, as for [InlineAmountField].
library;

import 'package:flutter/widgets.dart';

import '../core/units/units.dart';
import 'inline_amount_field.dart';
import 'unit_chip.dart';

class AmountAndUnitField extends StatelessWidget {
  const AmountAndUnitField({
    required this.unit,
    required this.units,
    required this.onUnit,
    this.amount,
    this.onAmount,
    this.controller,
    this.onSubmit,
    this.amountKey,
    this.unitKey,
    this.amountWidth = 46,
    this.seed = 0,
    this.scrollController,
    super.key,
  });

  /// The amount slot's seed text. Null where the host holds the [controller].
  final String? amount;

  /// The amount slot's controller, for a host that empties the slot after an
  /// entry lands. See [InlineAmountField.controller].
  final TextEditingController? controller;

  final Unit unit;

  /// What the picker offers; the caller decides.
  final List<Unit> units;

  final ValueChanged<String>? onAmount;
  final ValueChanged<Unit> onUnit;

  /// What the keyboard's done key does. Null unfocuses.
  final VoidCallback? onSubmit;

  /// Keys on the field and the chip, so a test can target one slot.
  final Key? amountKey;
  final Key? unitKey;

  final double amountWidth;

  /// Bumped to re-seed the amount slot from [amount].
  final int seed;

  /// See [InlineAmountField.scrollController].
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineAmountField(
        key: ValueKey('amount-$seed-${amountKey ?? ''}'),
        fieldKey: amountKey,
        width: amountWidth,
        // Kitchen amounts: `2/3` must be typeable.
        fractions: true,
        controller: controller,
        scrollController: scrollController,
        initial: amount,
        onChange: onAmount,
        onSubmit:
            onSubmit ?? () => FocusManager.instance.primaryFocus?.unfocus(),
      ),
      const SizedBox(width: 5),
      // The chip sizes to its own label, not to a column width.
      SizedBox(
        height: kInlineControlHeight,
        child: UnitChip(
          key: unitKey,
          label: unit.label,
          // A lone chip shows the current choice.
          selected: true,
          onTap: () async {
            final picked = await showUnitPickSheet(
              context,
              units: units,
              selected: unit,
            );
            if (picked != null) onUnit(picked);
          },
        ),
      ),
    ],
  );
}
