/// The quantity + unit-chip sheet for a **component** line (step 8.6 / D2,
/// design board frame d) — the 7.7 sheet's anatomy with batch math on the
/// chips.
///
/// Same dock, same [UnitChip]s, same live conversion line, same Optional row.
/// Three things differ, and each is a consequence of a component being a
/// recipe rather than an ingredient:
///
/// - the chips are **`batch` ∪ the yields' families**, kitchen-trimmed
///   ([componentUnitChips]) — `batch` is always sayable, and a family opens
///   only because the recipe states a yield in it. There is no density for a
///   recipe, so a family nobody stated is not offered; the fix is the yield's
///   optional second denomination, not a guess;
/// - the conversion line reads in batches ("0.25 cup = 0.25 of a batch ·
///   makes 1 cup"), and a recipe with no yield gets the *not-an-error* state:
///   the `batch` chip alone, the honest note, and one tap to go set the yield.
///   The link, the page and scaling all work meanwhile — only derived numbers
///   wait;
/// - there is **no `+` manage-measures chip**: a measure is an ingredient
///   concept ("potato, medium = 213 g" says nothing about a recipe), which is
///   the same reason a component line never carries a `measure_id`.
///
/// The 7.7 **stored-selection rule carries over**: an imported line's printed
/// unit is an admissible chip even when this sheet would not offer it, marked
/// as outside the filter and rendered with the honest unresolved line — never
/// silently rewritten.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/format.dart';
import '../../ingredients/presentation/unit_chips.dart' show UnitChip;
import '../domain/component_math.dart';
import '../domain/component_units.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'recipe_chip.dart';

/// What the component sheet resolved to: the amount, the unit it counts, and
/// whether the line is optional.
typedef ComponentQuantity = ({double? quantity, Unit unit, bool optional});

/// Opens the component quantity sheet for [target]; resolves to the chosen
/// amount, or null if dismissed.
///
/// [onSetYield] is the deep link the no-yield state offers ("Set the yield").
/// Null where there is nowhere to send the user (a host with no router).
Future<ComponentQuantity?> showComponentQuantitySheet(
  BuildContext context, {
  required SubRecipeTarget target,
  double? initialQuantity,
  Unit? initialUnit,
  bool initialOptional = false,
  VoidCallback? onSetYield,
}) {
  return showAnsiSheet<ComponentQuantity>(
    context: context,
    builder: (sheetContext) => ComponentQuantityEditor(
      target: target,
      initialQuantity: initialQuantity,
      initialUnit: initialUnit,
      initialOptional: initialOptional,
      onSetYield: onSetYield == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onSetYield();
            },
      onDone: (result) => Navigator.of(sheetContext).pop(result),
    ),
  );
}

class ComponentQuantityEditor extends HookWidget {
  const ComponentQuantityEditor({
    required this.target,
    required this.onDone,
    this.initialQuantity,
    this.initialUnit,
    this.initialOptional = false,
    this.onSetYield,
    super.key,
  });

  final SubRecipeTarget target;
  final double? initialQuantity;

  /// The line's stored unit — always an admissible chip (the 7.7 rule).
  final Unit? initialUnit;

  /// Whether the line already says it may be left out.
  final bool initialOptional;

  final ValueChanged<ComponentQuantity> onDone;
  final VoidCallback? onSetYield;

  @override
  Widget build(BuildContext context) {
    final yields = target.yields;
    final quantity = useState<double?>(initialQuantity);
    final unit = useState<Unit>(initialUnit ?? _defaultUnit(yields));
    final optional = useState<bool>(initialOptional);
    final offer = componentUnitChips(yields: yields, stored: initialUnit);

    final note = componentConversionLine(
      quantity: quantity.value,
      unit: unit.value,
      yields: yields,
    );

    return AnsiSheetShell(
      children: [
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: RecipeChip(title: target.title, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          yields.isEmpty
              ? 'no yield set · your recipe'
              : '${yields.map(yieldText).join(' · ')} · your recipe',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 16),
        Text('QUANTITY', style: ansiLabel()),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                autofocus: true,
                hint: 'qty',
                // A TEXT keyboard, not the decimal pad: iOS's numeric pads
                // carry no `/`, so `1/2` could not be typed on one — and a
                // fraction is how a recipe says this number.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    text: formatQuantityIn(quantity.value, unit.value),
                  ),
                  onChange: (v) => quantity.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                unit.value.label,
                style: ansiMono(size: 15, color: AnsiColors.herbDeep),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          note ??
              (yields.isEmpty ? 'no yield set — amounts in batches only' : ''),
          textAlign: TextAlign.center,
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final u in offer.chips)
                  UnitChip(
                    label: u.label,
                    suffix: u == offer.offFilter ? 'not in filter' : null,
                    selected: unit.value == u,
                    onTap: () => unit.value = u,
                  ),
              ],
            ),
          ),
        ),
        // The no-yield state is not an error state: the link, the page and
        // scaling all work: only the derived numbers wait, one tap away.
        if (yields.isEmpty && onSetYield != null) ...[
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSetYield,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AnsiColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Set the yield',
                textAlign: TextAlign.center,
                style: ansiMono(size: 12),
              ),
            ),
          ),
        ],
        // The Optional row is the ingredient sheet's, word for word: a
        // sub-recipe may be left out of a total exactly as a garnish may.
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Optional', style: ansiSans(size: 15)),
          value: optional.value,
          onChange: (on) => optional.value = on,
        ),
        const SizedBox(height: 4),
        Text(
          'left out of macros and the shop list, and named where it left',
          style: ansiMono(size: 11, color: AnsiColors.muted),
        ),
        const SizedBox(height: 14),
        FButton(
          onPress: () => onDone((
            quantity: quantity.value,
            unit: unit.value,
            optional: optional.value,
          )),
          child: const Text('Done'),
        ),
      ],
    );
  }

  /// What a fresh component line counts before anyone picks a chip: the
  /// yield's own unit when the recipe states one ("¼ cup" of a `makes 1 cup`
  /// aioli is the line a page prints), and `batch` otherwise — the one
  /// denomination that never needs a yield.
  static Unit _defaultUnit(List<YieldDenomination> yields) =>
      yields.isEmpty ? batches : yields.first.unit;
}
