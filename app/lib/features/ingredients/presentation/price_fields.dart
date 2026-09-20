/// The parts every price door shares: the store chips, the *for* field and the
/// derived line. The price sheet, the receipt's pack sheet and the receipt
/// review draw these, so a store or a pack is picked the same way everywhere.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/unit_chip.dart';
import '../../books/presentation/text_prompt.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/price.dart';
import 'ingredient_facts.dart';
import 'unit_chips.dart';

/// The household's store words as chips, with a plus that names a new one.
///
/// [onCoined] receives the trimmed word. It can fire after this widget is
/// unmounted, so a host must not touch a disposed `ref` or hook inside it.
class StoreChipRow extends StatelessWidget {
  const StoreChipRow({
    required this.stores,
    required this.selected,
    required this.onSelect,
    required this.onCoined,
    super.key,
  });

  final List<String> stores;
  final String? selected;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onCoined;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kUnitChipHeight,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final word in stores)
            UnitChip(
              label: word,
              selected: word == selected,
              onTap: () => onSelect(word),
            ),
          // An icon, not a `＋` glyph: the bundled fonts carry no U+FF0B.
          UnitChip(
            icon: const Icon(
              FLucideIcons.plus,
              size: 13,
              color: AnsiColors.herb,
            ),
            accent: true,
            onTap: () async {
              final typed = await promptForText(
                context,
                title: 'Where',
                hint: 'e.g. Whole Foods',
                confirm: 'Use it',
              );
              final word = typed?.trim() ?? '';
              if (word.isNotEmpty) onCoined(word);
            },
          ),
        ],
      ),
    ),
  );
}

/// The *for* field: the pack as an amount, in a unit picked from the row's own
/// chip row.
class PackField extends StatelessWidget {
  const PackField({
    required this.ingredient,
    required this.measures,
    required this.controller,
    required this.choice,
    required this.onAmount,
    required this.onSelect,
    this.autofocus = false,
    super.key,
  });

  final Ingredient ingredient;
  final List<Measure> measures;
  final TextEditingController controller;
  final UnitChoice choice;
  final ValueChanged<double?> onAmount;
  final ValueChanged<UnitChoice> onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const AnsiMicroLabel('FOR', hint: 'what the money bought'),
      Row(
        children: [
          SizedBox(
            width: 132,
            child: FTextField(
              autofocus: autofocus,
              hint: 'pack',
              // A text keyboard: a pack can be said as `1½ lb`, and iOS's
              // numeric pads carry no `/`.
              keyboardType: TextInputType.text,
              control: FTextFieldControl.managed(
                controller: controller,
                onChange: (v) => onAmount(parseAmount(v.text)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              choice.label,
              style: ansiMono(size: 15, color: AnsiColors.herbDeep),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // No manage chip: a pack is a purchase, not a vocabulary edit.
      UnitChipRow(
        offer: allowedUnitChoicesFor(ingredient, measures, current: choice),
        selected: choice,
        pieceLabel: pieceChipLabel(ingredient),
        onSelect: onSelect,
      ),
    ],
  );
}

/// What the money and the pack come to, or why they come to nothing. It keeps
/// its height while empty so the button under it does not move.
class PriceDerivedLine extends StatelessWidget {
  const PriceDerivedLine({
    required this.derived,
    required this.ingredient,
    required this.textKey,
    super.key,
  });

  final Result<PricePer100>? derived;
  final Ingredient ingredient;

  /// The key on the text, so a test names the line rather than its prose.
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    final (text, muted) = switch (derived) {
      null => ('', true),
      Ok(:final value) => ('= ${formatPricePer100(value)}', false),
      Err(:final failure) => (priceRefusal(failure, ingredient), true),
    };
    return SizedBox(
      height: 32,
      child: Center(
        child: Text(
          text,
          key: textKey,
          textAlign: TextAlign.center,
          style: muted
              ? ansiMono(size: 11, color: AnsiColors.muted)
              : ansiMono(size: 13, color: AnsiColors.herbDeep),
        ),
      ),
    );
  }
}
