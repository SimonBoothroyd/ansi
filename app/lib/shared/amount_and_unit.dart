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
/// It is built from [InlineAmountField] and so inherits its discipline: the
/// slot is as tall as a line of digits and as wide as a plausible value, and
/// the select is trimmed to the same height, so the sentence around it stays a
/// sentence at 402 pt rather than becoming three rows.
///
/// The text is handed back **exactly as typed** — the parse
/// belongs to the caller, for the reason [InlineAmountField] documents.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../core/units/units.dart';
import 'inline_amount_field.dart';

class AmountAndUnitField extends StatelessWidget {
  const AmountAndUnitField({
    required this.amount,
    required this.unit,
    required this.units,
    required this.onAmount,
    required this.onUnit,
    this.onSubmit,
    this.amountKey,
    this.unitKey,
    this.amountWidth = 46,
    this.unitWidth = 96,
    this.seed = 0,
    super.key,
  });

  /// The amount slot's text, as it should be seeded.
  final String amount;

  final Unit unit;

  /// What the picker offers. The caller decides — a serving may be said in any
  /// kitchen unit, a piece weight only in something its basis can reach, a
  /// component only in its sub-recipe's own denominations.
  final List<Unit> units;

  final ValueChanged<String> onAmount;
  final ValueChanged<Unit> onUnit;

  /// What the keyboard's done key does. Null unfocuses.
  final VoidCallback? onSubmit;

  /// Keyed on the field and the select themselves, so a test targets one slot
  /// of a sentence that has two.
  final Key? amountKey;
  final Key? unitKey;

  final double amountWidth;
  final double unitWidth;

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
        initial: amount,
        onChange: onAmount,
        onSubmit:
            onSubmit ?? () => FocusManager.instance.primaryFocus?.unfocus(),
      ),
      const SizedBox(width: 5),
      SizedBox(
        width: unitWidth,
        child: FSelect<Unit>.rich(
          key: unitKey,
          size: FTextFieldSizeVariant.sm,
          // The small variant still floors at Forui's touch height; trim it to
          // the inline slot's 32 pt so the sentence sits at one height.
          style: FSelectStyleDelta.delta(
            fieldStyles: FVariantsDelta.delta([
              FVariantOperation.match(
                {FTextFieldSizeVariant.sm},
                const FTextFieldStyleDelta.delta(
                  constraints: BoxConstraints(minHeight: 32),
                  contentPadding: EdgeInsetsGeometryDelta.value(
                    EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  ),
                ),
              ),
            ]),
          ),
          format: (u) => u.label,
          control: FSelectControl<Unit>.lifted(
            value: unit,
            onChange: (u) => onUnit(u ?? unit),
          ),
          children: [
            for (final u in units) FSelectItem(title: Text(u.label), value: u),
          ],
        ),
      ),
    ],
  );
}
