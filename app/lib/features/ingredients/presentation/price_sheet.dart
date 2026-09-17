/// The price sheet — *paid* … *for* … *at* — the one door a price is entered
/// through.
///
/// Three questions and nothing else: what the money was, what it bought, and
/// where. The pack is an amount in a unit this row can already say, picked
/// from **the quantity sheet's own chip row** ([UnitChipRow]) rather than a
/// second picker built for money: the row's measures lead it exactly as they
/// do on a recipe line, so a bag the household has named is one tap and a
/// plain `454 g` works where nothing is named. Same control, same height, same
/// order.
///
/// **The dock states what the two come to before Done.** It is the figure a
/// recipe will read — `= 77¢ / 100 g` — and it is the derivation itself, not a
/// preview of one, so a pack this row cannot weigh says so in the same slot
/// and Done is refused with the reason (`priceRefusal`). A g-basis row bought
/// by the litre prices only through a density; that is the macros' own gate,
/// on the same boundary.
///
/// The store is a **word**, not a row: the chips are what this household has
/// typed before, most recent first, and `＋` names a new one. Nothing about a
/// store is stored anywhere but on the receipt that used it.
///
/// What Save writes is one `manual` receipt with one line — a hand-typed price
/// and a scanned one are the same fact in the same ledger.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../shared/ansi_micro_label.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/unit_chip.dart';
import '../../../shared/write.dart';
import '../../books/presentation/text_prompt.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/price.dart';
import 'ingredient_facts.dart';
import 'unit_chips.dart';

/// The dock's derived line, so a test names it rather than matching prose.
const kPriceDerivedKey = ValueKey('price-derived');

/// Opens the price sheet for [ingredient]; resolves to true when a price was
/// written, and null when the sheet was dismissed.
///
/// Through [showAnsiSheet], which is also what makes it a centred dialog from
/// `medium` up — the same door, in the room the window has for it.
Future<bool?> showPriceSheet(
  BuildContext context, {
  required Ingredient ingredient,
}) {
  return showAnsiSheet<bool>(
    context: context,
    builder: (sheetContext) => PriceEditor(
      ingredient: ingredient,
      onSaved: () => Navigator.of(sheetContext).pop(true),
    ),
  );
}

class PriceEditor extends HookConsumerWidget {
  const PriceEditor({
    required this.ingredient,
    required this.onSaved,
    super.key,
  });

  final Ingredient ingredient;
  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paidCents = useState<int?>(null);
    final packAmount = useState<double?>(null);
    final choice = useState<UnitChoice?>(null);
    final store = useState<String?>(null);
    // A store named through `＋` but not yet written anywhere — it belongs in
    // the chip row from the moment it is typed, and it becomes a remembered
    // word only when Save lands the receipt that used it.
    final coined = useState<List<String>>(const []);
    final busy = useState(false);

    final measures =
        ref.watch(ingredientMeasuresProvider(ingredient.id)).asData?.value ??
        const <Measure>[];
    final prices =
        ref.watch(ingredientPricesProvider(ingredient.id)).asData?.value ??
        const <PriceObservation>[];
    final remembered =
        ref.watch(priceStoresProvider).asData?.value ?? const <String>[];

    // The chip row opens on the row's WHOLE MEASURE where it has one (the
    // measure that weighs what a piece weighs is the row's word for one,
    // ADR-0016) and on its default unit otherwise — the same rule the
    // quantity sheet opens on, because it is the same control. Resolved on
    // every build rather than seeded by an effect: nothing here edits a
    // stored line, so there is no prior choice to preserve.
    final whole = wholeMeasureOf(ingredient, measures);
    final packChoice =
        choice.value ??
        (whole == null
            ? UnitOption(ingredient.defaultUnit)
            : MeasureOption(whole));

    final stores = <String>[
      ...coined.value,
      for (final word in remembered)
        if (!coined.value.contains(word)) word,
    ];
    final pickedStore = store.value ?? (stores.isEmpty ? null : stores.first);

    // Only once both halves are stated: an empty field is a question nobody
    // has answered yet, not a mistake to be named.
    final derived = paidCents.value == null || packAmount.value == null
        ? null
        : priceFromEntry(
            ingredient,
            paidCents: paidCents.value!,
            packAmount: packAmount.value!,
            packChoice: packChoice,
          );
    final canSave =
        !busy.value && pickedStore != null && derived is Ok<PricePer100>;

    Future<void> nameAStore() async {
      final word = await promptForText(
        context,
        title: 'Where',
        hint: 'e.g. Whole Foods',
        confirm: 'Use it',
      );
      // The sheet can be dismissed while the prompt is up; touching hook
      // state then would throw.
      if (word == null || word.trim().isEmpty || !context.mounted) return;
      coined.value = [word.trim(), ...coined.value];
      store.value = word.trim();
    }

    Future<void> save() async {
      final pack = packInBasis(
        ingredient,
        amount: packAmount.value!,
        choice: packChoice,
      );
      if (pack is! Ok<double>) return;
      busy.value = true;
      final saved = await ref.writeOk(
        context,
        'save that price',
        () => ref
            .read(priceRepositoryProvider)
            .recordManualPrice(
              ingredientId: ingredient.id,
              cents: paidCents.value!,
              packBasisAmount: pack.value,
              store: pickedStore!,
              // The pack's WORD, only where one was picked: a `piece` or a
              // plain `454 g` points at no row, and the weight is already in
              // the amount above.
              measureId: switch (packChoice) {
                MeasureOption(:final measure) => measure.id,
                UnitOption() => null,
              },
            ),
      );
      if (!context.mounted) return;
      busy.value = false;
      if (saved) onSaved();
    }

    return AnsiSheetShell(
      scrollable: true,
      children: [
        const SizedBox(height: 6),
        Text(
          ingredient.canonicalName,
          style: ansiSerif(size: AnsiType.heading),
          overflow: TextOverflow.ellipsis,
        ),
        if (latestPriceAside(prices.isEmpty ? null : prices.first)
            case final aside?)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              aside,
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),

        const SizedBox(height: 18),
        const AnsiMicroLabel('PAID'),
        FTextField(
          autofocus: true,
          hint: '0.00',
          prefixBuilder: (context, style, variants) => Padding(
            // The symbol starts where the text would have started without it,
            // the way the search field seats its magnifier.
            padding: EdgeInsetsDirectional.only(
              start: style.contentPadding
                  .resolve(Directionality.of(context))
                  .left,
            ),
            child: Text(r'$', style: ansiMono(size: 15)),
          ),
          // The decimal pad, not the text keyboard the amount fields take: a
          // sum of money is never typed as a fraction.
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          control: FTextFieldControl.managed(
            onChange: (v) => paidCents.value = parseMoney(v.text),
          ),
        ),

        const SizedBox(height: 16),
        const AnsiMicroLabel('FOR', hint: 'what the money bought'),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                hint: 'pack',
                // A TEXT keyboard: a pack can be said as `1½ lb`, and iOS's
                // numeric pads carry no `/`.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  onChange: (v) => packAmount.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                packChoice.label,
                style: ansiMono(size: 15, color: AnsiColors.herbDeep),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        UnitChipRow(
          ingredient: ingredient,
          measures: measures,
          selected: packChoice,
          // No manage chip: the pack is a purchase, not a vocabulary edit.
          // Naming a measure belongs to the quantity sheet and the form.
          onSelect: (picked) => choice.value = picked,
        ),

        const SizedBox(height: 16),
        const AnsiMicroLabel('AT'),
        _StoreChips(
          stores: stores,
          selected: pickedStore,
          onSelect: (word) => store.value = word,
          onNew: nameAStore,
        ),

        const SizedBox(height: 18),
        _Derived(derived: derived, ingredient: ingredient),
        const SizedBox(height: 12),
        FButton(onPress: canSave ? save : null, child: const Text('Done')),
      ],
    );
  }
}

/// The dock's one line: what the two fields come to, or why they come to
/// nothing.
///
/// It keeps its slot whether or not there is anything to say, so the button
/// under it does not move as the fields fill.
class _Derived extends StatelessWidget {
  const _Derived({required this.derived, required this.ingredient});

  final Result<PricePer100>? derived;
  final Ingredient ingredient;

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
          key: kPriceDerivedKey,
          textAlign: TextAlign.center,
          style: muted
              ? ansiMono(size: 11, color: AnsiColors.muted)
              : ansiMono(size: 13, color: AnsiColors.herbDeep),
        ),
      ),
    );
  }
}

/// The store words this household has used, as chips, with a `＋` that names a
/// new one. The same pill the units wear — a store is picked, never typed into
/// a field of its own.
class _StoreChips extends StatelessWidget {
  const _StoreChips({
    required this.stores,
    required this.selected,
    required this.onSelect,
    required this.onNew,
  });

  final List<String> stores;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Future<void> Function() onNew;

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
          // A real icon, never a `＋` glyph — the bundled fonts carry no
          // U+FF0B and it would render as tofu.
          UnitChip(
            icon: const Icon(
              FLucideIcons.plus,
              size: 13,
              color: AnsiColors.herb,
            ),
            accent: true,
            onTap: onNew,
          ),
        ],
      ),
    ),
  );
}
