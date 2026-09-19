/// A number **and the unit it is in**, as one control inside a line of prose.
///
/// Every sentence in this app that states a quantity states two things, and
/// they were being drawn four different ways: a fixed word beside a field (the
/// density's `g`, the piece weight's basis), a field plus a full-width select
/// (the recipe's yield), a field plus a row of chips. A number whose unit is
/// printed rather than picked is a number the person has to convert in their
/// head before typing — "density is in science, not on some packages" — so
/// wherever an amount has a unit, the unit is part of the control.
///
/// **The unit is picked the way units are picked everywhere else**: the slot is
/// a single [UnitChip], drawn selected and carrying the unit's own label, and
/// tapping it opens [showUnitPickSheet] — the same chips the quantity sheet
/// docks over its keypad, in a room the size of one question. Two text boxes
/// side by side, one of them a dropdown, made the sentence read as a form.
///
/// It is built from [InlineAmountField] and so inherits its discipline: the
/// slot is as tall as a line of digits and as wide as a plausible value, and
/// the chip is trimmed to the same [kInlineControlHeight], so the sentence
/// around it stays a sentence at 402 pt rather than becoming three rows. That
/// height is the control's contract with its hosts: whatever a host puts
/// beside it — a label field, an Add button, a remove glyph — sits at the same
/// height, or the run reads as two.
///
/// The text is handed back **exactly as typed** — the parse
/// belongs to the caller, for the reason [InlineAmountField] documents.
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
    super.key,
  });

  /// The amount slot's text, as it should be seeded. Null where the host
  /// holds the [controller] — the controller is then the slot's text.
  final String? amount;

  /// The amount slot's controller, for a host that has to **empty** the slot
  /// after an entry lands rather than merely read it. See
  /// [InlineAmountField.controller].
  final TextEditingController? controller;

  final Unit unit;

  /// What the picker offers. The caller decides — a serving may be said in any
  /// kitchen unit, a piece weight only in something its basis can reach, a
  /// component only in its sub-recipe's own denominations.
  final List<Unit> units;

  final ValueChanged<String>? onAmount;
  final ValueChanged<Unit> onUnit;

  /// What the keyboard's done key does. Null unfocuses.
  final VoidCallback? onSubmit;

  /// Keyed on the field and the chip themselves, so a test targets one slot
  /// of a sentence that has two.
  final Key? amountKey;
  final Key? unitKey;

  final double amountWidth;

  /// Bumped to re-seed the amount slot from [amount] — the field seeds its
  /// controller once, so new text needs a new field to seed it into.
  final int seed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineAmountField(
        key: ValueKey('amount-$seed-${amountKey ?? ''}'),
        fieldKey: amountKey,
        width: amountWidth,
        // Every amount with a unit is a kitchen amount: `2/3` must be typeable.
        fractions: true,
        controller: controller,
        initial: amount,
        onChange: onAmount,
        onSubmit:
            onSubmit ?? () => FocusManager.instance.primaryFocus?.unfocus(),
      ),
      const SizedBox(width: 5),
      // The chip sizes to its own label rather than to a column width: a
      // sentence saying `tbsp` should not reserve the room `fl oz` needs.
      SizedBox(
        height: kInlineControlHeight,
        child: UnitChip(
          key: unitKey,
          label: unit.label,
          // Always the chosen one — a lone chip is not an offer, it is what
          // this sentence currently says.
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
