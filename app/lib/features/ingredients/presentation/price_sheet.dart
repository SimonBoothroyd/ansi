/// The price sheet (*paid* … *for* … *at*): the one place a price is typed,
/// and what it types is the row's base price.
///
/// The pack is picked from the quantity sheet's chip row ([UnitChipRow]); the
/// dock shows the derived figure (`= 77¢ / 100 g`) or the refusal
/// (`priceRefusal`); the store is optional, a word from the household's chips
/// ([StoreChipRow], the receipt review's own). Done sets the row's
/// [BasePrice] — never a receipt, and so never a shop in the ledger or the
/// week's spend. Opened on the stored base
/// price, a Delete sits under Done. A price paid on a receipt is corrected on
/// its receipt, never here.
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
import '../../../shared/write.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/price.dart';
import 'ingredient_facts.dart';
import 'price_fields.dart';
import 'unit_chips.dart';

/// The dock's derived line, so a test names it rather than matching prose.
const kPriceDerivedKey = ValueKey('price-derived');

/// The sheet's Delete, for the same reason.
const kPriceDeleteKey = ValueKey('price-delete');

/// Opens the price sheet for [ingredient]'s base price. Resolves to true when
/// it was set or taken back, null when dismissed. [editing] opens it on the
/// stored one. Goes through [showAnsiSheet], so it is a centred dialog from
/// `medium` up.
Future<bool?> showPriceSheet(
  BuildContext context, {
  required Ingredient ingredient,
  BasePrice? editing,
}) {
  return showAnsiSheet<bool>(
    context: context,
    builder: (sheetContext) => PriceEditor(
      ingredient: ingredient,
      editing: editing,
      onSaved: () => Navigator.of(sheetContext).pop(true),
    ),
  );
}

class PriceEditor extends HookConsumerWidget {
  const PriceEditor({
    required this.ingredient,
    required this.onSaved,
    this.editing,
    super.key,
  });

  final Ingredient ingredient;

  /// The stored base price this sheet is changing, or null when there is none.
  final BasePrice? editing;

  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paidCents = useState<int?>(null);
    final packAmount = useState<double?>(null);
    final choice = useState<UnitChoice?>(null);
    final busy = useState(false);
    // Optional: null names no shop. Tapping the picked chip again clears it.
    final store = useState<String?>(null);
    // A store named through `＋` in this sitting joins the chip row at once.
    final coined = useState<List<String>>(const []);
    final paidField = useTextEditingController();
    final packField = useTextEditingController();
    // The stored price is copied into the fields once, after the row's measures
    // arrive: a `bag` chip cannot be selected before it exists, and re-seeding
    // later would overwrite typing.
    final seeded = useRef(false);

    final measuresAsync = ref.watch(ingredientMeasuresProvider(ingredient.id));
    final measures = measuresAsync.asData?.value ?? const <Measure>[];
    final remembered =
        ref.watch(priceStoresProvider).asData?.value ?? const <String>[];
    final prices =
        ref.watch(ingredientPricesProvider(ingredient.id)).asData?.value ??
        const <PriceObservation>[];

    final stored = editing;
    useEffect(() {
      if (stored == null || seeded.value || measuresAsync.asData == null) {
        return null;
      }
      seeded.value = true;
      // The pack as entered, when it was kept and its chip still exists;
      // otherwise the basis figure.
      final asEntered = enteredChoice(stored, measures);
      choice.value = asEntered ?? UnitOption(stored.basis.baseUnit);
      final amount = asEntered == null
          ? stored.packBasisAmount
          : stored.packAmount ?? stored.packBasisAmount;
      packAmount.value = amount;
      packField.text = switch (choice.value) {
        MeasureOption() => formatAmount(amount),
        UnitOption(:final unit) => formatAmountIn(amount, unit),
        RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
        null => formatAmount(amount),
      };
      paidCents.value = stored.cents;
      paidField.text = dollarsTyped(stored.cents);
      store.value = stored.store;
      return null;
    }, [measuresAsync]);

    // Opens on the first chip offered, as the quantity sheet does, or on the
    // stored price's chip seeded above.
    final packChoice = choice.value ?? firstOfferedChoice(ingredient, measures);

    // Derived only once both halves are stated; an empty field is not an error.
    final derived = paidCents.value == null || packAmount.value == null
        ? null
        : priceFromEntry(
            ingredient,
            paidCents: paidCents.value!,
            packAmount: packAmount.value!,
            packChoice: packChoice,
          );
    final canSave = !busy.value && derived is Ok<PricePer100>;

    final stores = <String>[
      ...coined.value,
      for (final word in remembered)
        if (!coined.value.contains(word)) word,
    ];
    // A stored store the chips no longer offer is still drawn, so it can be
    // seen and cleared.
    if (store.value case final word? when !stores.contains(word)) {
      stores.insert(0, word);
    }

    void nameAStore(String word) {
      // The sheet can be dismissed while the prompt is up; touching hook
      // state then would throw.
      if (!context.mounted) return;
      coined.value = [word, ...coined.value];
      store.value = word;
    }

    Future<void> save() async {
      final pack = packInBasis(
        ingredient,
        amount: packAmount.value!,
        choice: packChoice,
      );
      if (pack is! Ok<double>) return;
      busy.value = true;
      // The pack in BOTH denominations: the basis figure every reader derives
      // from, and the words it was said in, which nothing derives from.
      final entered = packAsEntered(packAmount.value!, packChoice);
      final repository = ref.read(priceRepositoryProvider);
      final saved = await ref.writeOk(
        context,
        stored == null ? 'save that price' : 'change that price',
        () => repository.setBasePrice(
          ingredientId: ingredient.id,
          cents: paidCents.value!,
          store: store.value,
          packBasisAmount: pack.value,
          packAmount: entered.amount,
          packUnitId: entered.unitId,
          measureId: entered.measureId,
        ),
      );
      if (!context.mounted) return;
      busy.value = false;
      if (saved) onSaved();
    }

    Future<void> remove() async {
      // Captured before the confirm dialog: this sheet's row can be gone by the
      // time it answers, and a `ref` that outlives its widget throws.
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      final ok = await askAnsi(
        host.context,
        title: 'Delete the base price?',
        body:
            'A cost then reads only what a receipt says was paid. Receipts '
            'stay as they are.',
        confirm: 'Delete',
        destructive: true,
      );
      if (!ok) return;
      final gone = await container.writeOk(
        host,
        'delete that price',
        () => container
            .read(priceRepositoryProvider)
            .clearBasePrice(ingredient.id),
      );
      if (gone) onSaved();
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
        if (stored == null
                ? latestPriceAside(prices.isEmpty ? null : prices.first)
                : editedBasePriceAside(stored)
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
            controller: paidField,
            onChange: (v) => paidCents.value = parseMoney(v.text),
          ),
        ),

        const SizedBox(height: 16),
        PackField(
          ingredient: ingredient,
          measures: measures,
          controller: packField,
          choice: packChoice,
          onAmount: (amount) => packAmount.value = amount,
          onSelect: (picked) => choice.value = picked,
        ),

        const SizedBox(height: 16),
        const AnsiMicroLabel('AT'),
        StoreChipRow(
          stores: stores,
          selected: store.value,
          onSelect: (word) => store.value = store.value == word ? null : word,
          onCoined: nameAStore,
        ),

        const SizedBox(height: 18),
        PriceDerivedLine(
          derived: derived,
          ingredient: ingredient,
          textKey: kPriceDerivedKey,
        ),
        const SizedBox(height: 12),
        FButton(onPress: canSave ? save : null, child: const Text('Done')),
        // The way out of a price that should not exist, under the way to fix
        // one — and drawn only where there is something to delete.
        if (stored != null) ...[
          const SizedBox(height: 8),
          FButton(
            key: kPriceDeleteKey,
            variant: FButtonVariant.destructive,
            onPress: busy.value ? null : remove,
            child: const Text('Delete'),
          ),
        ],
      ],
    );
  }
}
