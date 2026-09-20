/// *Say what the pack is*: the receipt review's one extra question, asked
/// with the price sheet's own *for* field and derived line.
///
/// *Keep as a measure* mints a measure on the row at Save, by the person's own
/// tap. The pack carries to the next receipt whether or not one is kept, so
/// the copy says a measure is for recipe lines and the Shop, not for that.
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
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/measure_authoring.dart';
import '../../ingredients/domain/price.dart';
import '../../ingredients/presentation/price_fields.dart';

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
/// what they bought, and prints what the two come to. [count] is how many of
/// that pack the line rang up, so the derived line reads the price of ONE.
Future<ReceiptPackAnswer?> showReceiptPackSheet(
  BuildContext context, {
  required Ingredient ingredient,
  required int paidCents,
  int count = 1,
  double? amount,
  UnitChoice? choice,
  List<Measure> pendingMeasures = const [],
}) {
  return showAnsiSheet<ReceiptPackAnswer>(
    context: context,
    builder: (sheetContext) => ReceiptPackEditor(
      ingredient: ingredient,
      paidCents: paidCents,
      count: count,
      initialAmount: amount,
      initialChoice: choice,
      pendingMeasures: pendingMeasures,
      onDone: (answer) => Navigator.of(sheetContext).pop(answer),
    ),
  );
}

class ReceiptPackEditor extends HookConsumerWidget {
  const ReceiptPackEditor({
    required this.ingredient,
    required this.paidCents,
    required this.onDone,
    this.count = 1,
    this.initialAmount,
    this.initialChoice,
    this.pendingMeasures = const [],
    super.key,
  });

  final Ingredient ingredient;
  final int paidCents;

  /// How many of this pack the line rang up — the receipt's own count. The
  /// derived line divides by it, so the figure on screen is what ONE costs.
  final int count;

  final double? initialAmount;
  final UnitChoice? initialChoice;

  /// Measures other lines of this receipt will mint for this row at Save, so
  /// the same word at another size is refused here rather than written.
  final List<Measure> pendingMeasures;

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
    // A line already priced reopens on the pack it was bought in ([choice]);
    // a fresh one opens on the first chip the row offers, like every other
    // quantity surface.
    final packChoice = choice.value ?? firstOfferedChoice(ingredient, measures);

    final derived = packAmount.value == null
        ? null
        : priceFromEntry(
            ingredient,
            paidCents: paidCents,
            packAmount: packAmount.value!,
            packChoice: packChoice,
            count: count,
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

    // A word the row already says at this weight is that measure, and the
    // line points at it. The same word at another size, on the row or on
    // another line of this receipt, is refused.
    final kept = canKeep && keeping.value;
    final taken = kept ? measureAlreadyNamed(named, measures) : null;
    final clash =
        taken ?? (kept ? measureAlreadyNamed(named, pendingMeasures) : null);
    final takenWord = taken == null ? '' : measureLabelAsAuthored(taken.label);
    final isThatMeasure =
        taken != null &&
        said != null &&
        isSameMeasureWeight(said, taken.amount);
    final refusal =
        clash == null ||
            (said != null && isSameMeasureWeight(said, clash.amount))
        ? null
        : measureWordTakenRefusal(
            label: measureLabelAsAuthored(clash.label),
            said: said == null ? 'a different size' : weighs(said),
            taken: weighs(clash.amount),
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
        PackField(
          ingredient: ingredient,
          measures: measures,
          controller: packField,
          choice: packChoice,
          autofocus: true,
          onAmount: (amount) => packAmount.value = amount,
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
                  'The pack carries over either way. Keep one you would say '
                      'on a recipe or a shopping list, with its size in it: '
                      '“can (14.5 oz)”.',
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
        PriceDerivedLine(
          derived: derived,
          ingredient: ingredient,
          textKey: kReceiptPackDerivedKey,
        ),
        const SizedBox(height: 12),
        FButton(onPress: canDone ? done : null, child: const Text('Done')),
      ],
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
