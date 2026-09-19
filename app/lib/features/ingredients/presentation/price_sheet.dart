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
///
/// **The same sheet fixes a price that is already stored.** A tap on the Price
/// group's *Latest* line or on any row under *Before* opens it **on that
/// line**: the same three answers, filled in as they were entered — the pound
/// as a pound, the bag as the bag — and Done writes an UPDATE rather than a new
/// receipt, so correcting a typo does not leave the mistake behind as history.
/// A **Delete** sits under it, because the other thing a mistyped price needs
/// is to stop existing. There is no second door and no second wording: an edit
/// is the same question asked about a line that has already been answered.
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

/// The sheet's Delete, for the same reason.
const kPriceDeleteKey = ValueKey('price-delete');

/// Opens the price sheet for [ingredient]; resolves to true when a price was
/// written or taken back, and null when the sheet was dismissed.
///
/// [editing] opens it **on a stored line** rather than on a new one: the
/// answers are filled in as they were entered, Done rewrites that line, and a
/// Delete appears under it.
///
/// Through [showAnsiSheet], which is also what makes it a centred dialog from
/// `medium` up — the same door, in the room the window has for it.
Future<bool?> showPriceSheet(
  BuildContext context, {
  required Ingredient ingredient,
  PriceObservation? editing,
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

  /// The stored price this sheet is fixing, or null when it is entering one.
  final PriceObservation? editing;

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
    final paidField = useTextEditingController();
    final packField = useTextEditingController();
    // The stored line is copied into the fields ONCE, and only once the row's
    // measures have arrived: a pack tapped as `bag` cannot be reopened on that
    // chip before the chip exists, and re-seeding on a later frame would
    // overwrite what the person had started typing.
    final seeded = useRef(false);

    final measuresAsync = ref.watch(ingredientMeasuresProvider(ingredient.id));
    final measures = measuresAsync.asData?.value ?? const <Measure>[];
    final prices =
        ref.watch(ingredientPricesProvider(ingredient.id)).asData?.value ??
        const <PriceObservation>[];
    final remembered =
        ref.watch(priceStoresProvider).asData?.value ?? const <String>[];

    final line = editing;
    useEffect(() {
      if (line == null || seeded.value || measuresAsync.asData == null) {
        return null;
      }
      seeded.value = true;
      // The pack as it was ENTERED, where the line kept it and the chip it
      // named still exists; otherwise the basis figure it is derived from,
      // which is the honest reading of a line whose word is gone.
      final asEntered = enteredChoice(line, measures);
      choice.value = asEntered ?? UnitOption(line.basis.baseUnit);
      final amount = asEntered == null
          ? line.packBasisAmount
          : line.packAmount ?? line.packBasisAmount;
      packAmount.value = amount;
      packField.text = switch (choice.value) {
        MeasureOption() => formatAmount(amount),
        UnitOption(:final unit) => formatAmountIn(amount, unit),
        RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
        null => formatAmount(amount),
      };
      // What the line RANG UP as, which is what a person corrects. Its printed
      // deduction is the paper's and is left exactly where it was.
      paidCents.value = line.cents;
      paidField.text = dollarsTyped(line.cents);
      store.value = line.store;
      return null;
    }, [measuresAsync]);

    // The chip row opens on the first chip it offers — the same rule the
    // quantity sheet opens on, because it is the same control. A sheet opened
    // on a stored line opens on the chip that line was entered on instead,
    // seeded above.
    final packChoice = choice.value ?? firstOfferedChoice(ingredient, measures);

    final stores = <String>[
      ...coined.value,
      for (final word in remembered)
        if (!coined.value.contains(word)) word,
    ];
    final pickedStore = store.value ?? (stores.isEmpty ? null : stores.first);

    // Only once both halves are stated: an empty field is a question nobody
    // has answered yet, not a mistake to be named.
    //
    // What was PAID is the typed figure less the deduction the paper printed
    // under it, exactly as the ledger reads it — on a hand-typed price there
    // is none, and on a scanned line it is not this sheet's to restate.
    final derived = paidCents.value == null || packAmount.value == null
        ? null
        : priceFromEntry(
            ingredient,
            paidCents: paidCents.value! - (line?.discountCents ?? 0),
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
      // The pack in BOTH denominations: the basis figure every reader derives
      // from, and the words it was said in, which nothing derives from.
      final entered = packAsEntered(packAmount.value!, packChoice);
      final repository = ref.read(priceRepositoryProvider);
      final saved = await ref.writeOk(
        context,
        line == null ? 'save that price' : 'change that price',
        () => line == null
            ? repository.recordManualPrice(
                ingredientId: ingredient.id,
                cents: paidCents.value!,
                packBasisAmount: pack.value,
                store: pickedStore!,
                packAmount: entered.amount,
                packUnitId: entered.unitId,
                measureId: entered.measureId,
              )
            : repository.updatePrice(
                lineId: line.lineId,
                cents: paidCents.value!,
                packBasisAmount: pack.value,
                store: pickedStore!,
                // An edit is a correction, not a second shop: the price keeps
                // the day it was paid on.
                purchasedAt: line.purchasedAt,
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
      // Captured BEFORE the confirm dialog: this sheet's own row can be gone
      // by the time the answer comes back, and a `ref` that outlives its
      // widget throws.
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      // A photographed receipt is not this sheet's to tear up: the cents were
      // paid, the paper still has to add up, and all that goes is the line's
      // claim to be a price. The confirm says which of the two is about to
      // happen rather than one sentence covering both.
      final photo = line!.source == ReceiptSource.photo;
      final ok = await askAnsi(
        host.context,
        title: photo ? 'Stop pricing from this line?' : 'Delete this price?',
        body: photo
            ? 'The line stays on its receipt and the receipt still adds up. '
                  'It just stops counting towards what anything costs.'
            : 'It stops counting towards what anything costs. What was paid '
                  'before it stays.',
        confirm: photo ? 'Stop pricing' : 'Delete',
        destructive: true,
      );
      if (!ok) return;
      final gone = await container.writeOk(
        host,
        photo ? 'stop pricing from that line' : 'delete that price',
        () => container.read(priceRepositoryProvider).deletePrice(line.lineId),
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
        if (line == null
                ? latestPriceAside(prices.isEmpty ? null : prices.first)
                : editedPriceAside(line)
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
                  controller: packField,
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
        // The way out of a price that should not exist, under the way to fix
        // one — and drawn only where there is something to delete.
        if (line != null) ...[
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
