/// *Say what the pack is* — the receipt review's one extra question, asked
/// with the price sheet's own control.
///
/// The paper already said what was paid, so this sheet asks the half it did
/// not print: what the cents bought. It is the price sheet's **for** field —
/// an amount, and the row's own chip row leading with its measures
/// ([UnitChipRow]) — with the same dock stating what the two come to before
/// Done, and the same refusal when the row cannot weigh the pack.
///
/// One thing is here that the price sheet has no use for: **keep as a
/// measure**. What it buys is a WORD — one the household can also say on a
/// recipe line, and one the Shop can say *buy 3* of. It buys nothing about
/// the next receipt: the pack carries over from this row's latest price
/// whether or not a word was minted (`landPack`), so a plain `482 g` lands on
/// the next receipt exactly as `bottle` would.
///
/// That matters because the toggle's old justification said the opposite, and
/// a batch of bare `pack` and `jar` measures was minted on the strength of it
/// — words that then turn up on recipe-line chips and become the Shop's
/// rounding unit on rows that had no measure. So the copy names what minting
/// is for, the hint shows the household's own style (a container word carries
/// its shelf size: `can (14.5 oz)`), and a word the row already says is not
/// minted twice.
///
/// It is minted at Save, on the row, by the person's own tap — the import
/// itself mints nothing, as it never has.
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
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/measure_authoring.dart';
import '../../ingredients/domain/price.dart';
import '../../ingredients/presentation/ingredient_facts.dart';
import '../../ingredients/presentation/unit_chips.dart';

/// The dock's derived line, so a test names it rather than matching prose.
const kReceiptPackDerivedKey = ValueKey('receipt-pack-derived');

/// The *keep as a measure* toggle.
const kKeepAsMeasureKey = ValueKey('receipt-keep-as-measure');

/// The line under the word field: what minting buys, or why this word cannot.
const kKeepAsMeasureNoteKey = ValueKey('receipt-keep-as-measure-note');

/// What the sheet hands back: the pack in both denominations, and the word to
/// mint where the person asked for one.
typedef ReceiptPackAnswer = ({
  double amount,
  UnitChoice choice,
  double basisAmount,
  String? keepAsMeasure,
});

/// Opens the pack door for one line of a receipt.
///
/// [paidCents] is what the paper said the line cost — it is not editable
/// here, because a receipt's figures are the receipt's; this sheet asks only
/// what they bought, and prints what the two come to.
Future<ReceiptPackAnswer?> showReceiptPackSheet(
  BuildContext context, {
  required Ingredient ingredient,
  required int paidCents,
  double? amount,
  UnitChoice? choice,
}) {
  return showAnsiSheet<ReceiptPackAnswer>(
    context: context,
    builder: (sheetContext) => ReceiptPackEditor(
      ingredient: ingredient,
      paidCents: paidCents,
      initialAmount: amount,
      initialChoice: choice,
      onDone: (answer) => Navigator.of(sheetContext).pop(answer),
    ),
  );
}

class ReceiptPackEditor extends HookConsumerWidget {
  const ReceiptPackEditor({
    required this.ingredient,
    required this.paidCents,
    required this.onDone,
    this.initialAmount,
    this.initialChoice,
    super.key,
  });

  final Ingredient ingredient;
  final int paidCents;
  final double? initialAmount;
  final UnitChoice? initialChoice;
  final ValueChanged<ReceiptPackAnswer> onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packAmount = useState<double?>(initialAmount);
    final choice = useState<UnitChoice?>(initialChoice);
    final keeping = useState(false);
    final wordField = useTextEditingController();
    final word = useState('');
    final packField = useTextEditingController(
      text: initialAmount == null ? '' : formatAmount(initialAmount!),
    );

    final measures =
        ref.watch(ingredientMeasuresProvider(ingredient.id)).asData?.value ??
        const <Measure>[];
    final whole = wholeMeasureOf(ingredient, measures);
    final packChoice =
        choice.value ??
        (whole == null
            ? UnitOption(ingredient.defaultUnit)
            : MeasureOption(whole));

    final derived = packAmount.value == null
        ? null
        : priceFromEntry(
            ingredient,
            paidCents: paidCents,
            packAmount: packAmount.value!,
            packChoice: packChoice,
          );
    // A pack already named as one of the row's measures has nothing to mint:
    // the word exists. The toggle is drawn only where there is a word to gain.
    final canKeep = packChoice is UnitOption;
    final named = measureLabelAsAuthored(word.value);
    final basis = packAmount.value == null
        ? null
        : packInBasis(
            ingredient,
            amount: packAmount.value!,
            choice: packChoice,
          );
    final said = basis is Ok<double> ? basis.value : null;
    final base = ingredient.macrosBasis.baseUnit;
    String weighs(double amount) =>
        '${formatAmountIn(amount, base)} ${base.label}';

    // A word the row already says is not minted a second time. Where the two
    // weigh the same, this pack IS that measure and the line points at it;
    // where they do not, the word is taken and the sheet says so rather than
    // quietly making a second row of it.
    final taken = !canKeep || !keeping.value
        ? null
        : measureAlreadyNamed(named, measures);
    final takenWord = taken == null ? '' : measureLabelAsAuthored(taken.label);
    final isThatMeasure =
        taken != null &&
        said != null &&
        isSameMeasureWeight(said, taken.amount);
    final refusal = taken == null || isThatMeasure
        ? null
        : measureWordTakenRefusal(
            label: takenWord,
            said: said == null ? 'a different size' : weighs(said),
            taken: weighs(taken.amount),
          );

    final canDone =
        derived is Ok<PricePer100> &&
        refusal == null &&
        (!canKeep || !keeping.value || named.isNotEmpty);

    void done() {
      if (said == null) return;
      onDone((
        // The pack keeps the FIGURE the person typed either way: what this
        // shop bought is what they read off the paper, not what the row says
        // the word weighs today.
        amount: isThatMeasure ? 1 : packAmount.value!,
        choice: isThatMeasure ? MeasureOption(taken) : packChoice,
        basisAmount: said,
        keepAsMeasure:
            canKeep && keeping.value && named.isNotEmpty && !isThatMeasure
            ? named
            : null,
      ));
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
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            'the receipt says ${formatMoney(paidCents)}',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ),

        const SizedBox(height: 18),
        const AnsiMicroLabel('FOR', hint: 'what the money bought'),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                autofocus: true,
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
          onSelect: (picked) => choice.value = picked,
        ),

        if (canKeep) ...[
          const SizedBox(height: 16),
          _KeepAsMeasure(
            value: keeping.value,
            onChanged: (next) => keeping.value = next,
          ),
          if (keeping.value) ...[
            const SizedBox(height: 8),
            FTextField(
              hint: 'e.g. can (14.5 oz)',
              control: FTextFieldControl.managed(
                controller: wordField,
                onChange: (v) => word.value = v.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              refusal ??
                  'The next receipt lands on this pack either way. Mint a word '
                      'only for one you would also say on a recipe line, or '
                      'want the shop to say “buy 3” of — and put the shelf '
                      'size in it, like “can (14.5 oz)”, because two sizes of '
                      'one container are two words.',
              key: kKeepAsMeasureNoteKey,
              style: ansiSans(
                size: 11.5,
                color: refusal == null ? AnsiColors.muted : AnsiColors.aging,
                height: 1.35,
              ),
            ),
            if (isThatMeasure)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'this row already says “$takenWord” at this weight — '
                  'the line will point at it',
                  style: ansiMono(size: 10.5, color: AnsiColors.herbDeep),
                ),
              ),
          ],
        ],

        const SizedBox(height: 18),
        _Derived(derived: derived, ingredient: ingredient),
        const SizedBox(height: 12),
        FButton(onPress: canDone ? done : null, child: const Text('Done')),
      ],
    );
  }
}

/// The dock's one line — what the paper's cents and the typed pack come to,
/// or why they come to nothing. It keeps its slot whether or not there is
/// anything to say, so the button under it does not move as the field fills.
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
          key: kReceiptPackDerivedKey,
          textAlign: TextAlign.center,
          style: muted
              ? ansiMono(size: 11, color: AnsiColors.muted)
              : ansiMono(size: 13, color: AnsiColors.herbDeep),
        ),
      ),
    );
  }
}

/// The toggle, in the card's own flag geometry — off it is an outline, on it
/// is the herb pill the line will wear.
class _KeepAsMeasure extends StatelessWidget {
  const _KeepAsMeasure({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Semantics(
      container: true,
      button: true,
      label: value
          ? 'keeping the pack as a measure · tap to stop'
          : 'not kept as a measure · tap to keep it',
      child: GestureDetector(
        key: kKeepAsMeasureKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: value ? AnsiColors.herbSoft : null,
            border: value ? null : Border.all(color: AnsiColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'keep as a measure',
              style: ansiMono(
                size: 10.5,
                color: value ? AnsiColors.herbDeep : AnsiColors.muted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
