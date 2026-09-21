/// The quantity and unit-chip sheet for a component line. See ADR-0018.
///
/// The offer is [componentUnitChoices]; a recipe with no yield offers `batch`,
/// a note and a link to set the yield. A stored unit or word outside the offer
/// is still shown, marked. A line whose word has gone opens unselected and
/// keeps its number and pointer. The `+` chip swaps the body for
/// [RecipeMeasuresEditor], which writes through [RecipeMeasureRepository] on
/// tap (ADR-0011).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_choice.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/format.dart';
import '../../../shared/write.dart';
import '../../ingredients/presentation/unit_chips.dart';
import '../data/recipe_providers.dart';
import '../domain/component_math.dart' show YieldDenomination;
import '../domain/component_units.dart';
import '../domain/recipe.dart';
import '../domain/recipe_measure_repository.dart';
import 'component_format.dart';
import 'recipe_chip.dart';
import 'recipe_measure_delete.dart';
import 'recipe_measures_editor.dart';

/// What the component sheet resolved to: the amount, exactly one of a catalog
/// `unit` and a target word (`recipeMeasureId`), and whether the line is
/// optional. Both are null only for a line whose word has gone and nothing was
/// picked; the caller then writes neither.
typedef ComponentQuantity = ({
  double? quantity,
  Unit? unit,
  String? recipeMeasureId,

  /// The picked word itself, where one was picked. A word just coined behind
  /// the ＋ is not yet in the host's target; see [targetWithMeasure].
  RecipeMeasure? measure,
  bool optional,
});

/// [target] with [word] among its measures, so a line said in a word coined
/// behind the ＋ prints before the next load.
SubRecipeTarget targetWithMeasure(SubRecipeTarget target, RecipeMeasure word) {
  final known = target.measures.any((m) => m.id == word.id);
  return target.copyWith(
    measures: [
      for (final m in target.measures)
        if (m.id == word.id) word else m,
      if (!known) word,
    ],
  );
}

/// Opens the component quantity sheet for [target]; resolves to the chosen
/// amount, or null if dismissed.
///
/// [onSetYield] is the no-yield state's "Set the yield" link; null also hides
/// the `+` while the target states no yield. [initialMeasureId] is
/// `LineItem.recipeMeasureId`; the word is looked up on [target].
/// [mayCoinWords] draws the `+`; see [ComponentQuantityEditor.mayCoinWords].
Future<ComponentQuantity?> showComponentQuantitySheet(
  BuildContext context, {
  required SubRecipeTarget target,
  double? initialQuantity,
  Unit? initialUnit,
  String? initialMeasureId,
  bool initialOptional = false,
  bool mayCoinWords = false,
  VoidCallback? onSetYield,
}) {
  return showAnsiSheet<ComponentQuantity>(
    context: context,
    builder: (sheetContext) => ComponentQuantityEditor(
      target: target,
      initialQuantity: initialQuantity,
      initialUnit: initialUnit,
      initialMeasureId: initialMeasureId,
      initialOptional: initialOptional,
      mayCoinWords: mayCoinWords,
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

class ComponentQuantityEditor extends HookConsumerWidget {
  const ComponentQuantityEditor({
    required this.target,
    required this.onDone,
    this.initialQuantity,
    this.initialUnit,
    this.initialMeasureId,
    this.initialOptional = false,
    this.mayCoinWords = false,
    this.onSetYield,
    super.key,
  });

  final SubRecipeTarget target;
  final double? initialQuantity;

  /// The line's stored unit — always an admissible chip.
  final Unit? initialUnit;

  /// The line's `recipe_measure_id`, when it says one of the target's words.
  /// The word itself is read off [target].
  final String? initialMeasureId;

  /// Whether the line already says it may be left out.
  final bool initialOptional;

  /// Whether this host can say a line in one of the target's words: whether the
  /// chip row has the `+` and the sheet watches the target's live words.
  ///
  /// False in the import review, where a line has no column for a measure
  /// pointer (ADR-0018).
  final bool mayCoinWords;

  final ValueChanged<ComponentQuantity> onDone;
  final VoidCallback? onSetYield;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yields = target.yields;
    // The chip the sheet opens on. Null only for a line whose word has gone.
    final quantity = useState<double?>(initialQuantity);
    final optional = useState<bool>(initialOptional);
    final managing = useState(false);
    // Set when the manage state retired the selected word and the choice was
    // reconciled: Done must never write a tombstoned pointer.
    final retiredNote = useState<String?>(null);

    // The target's live words, so a word coined behind the `+` reaches this
    // chip row. The caller's snapshot stands until the watch has a value; an
    // empty list is a value.
    final watched = mayCoinWords && target.id.isNotEmpty
        ? ref.watch(recipeMeasuresProvider(target.id)).asData?.value
        : null;
    final measures = watched ?? target.measures;
    // The watch hands out the merged offer, but a line may point at a
    // merge-hidden twin, so pointers resolve against the live words plus those
    // twins.
    final known = _withHiddenTwins(measures, target.measures);

    // Read against the live words, so a stored pointer whose word was just
    // retired stops being an admissible chip.
    final stored = _openingChoice(known);
    final choice = useState<UnitChoice?>(stored);

    // The selection is re-read from the live list, so a re-stated word is
    // current and a retired one lights no chip.
    final picked = _seated(choice.value, known);
    final word = picked is RecipeMeasureOption ? picked.measure : null;
    final unit = switch (picked) {
      UnitOption(:final unit) => unit,
      RecipeMeasureOption() || null => null,
      MeasureOption(:final measure) => notAWordForARecipe(measure),
    };
    // The pointer the line will carry: the picked word, or the one it arrived
    // with while nothing is picked. Picking a unit clears it.
    final measureId = word?.id ?? (picked == null ? initialMeasureId : null);

    // A measure counts something, so the line has to say how many.
    final amountless =
        measureId != null && (quantity.value == null || quantity.value == 0);

    // The offer, with the opening choice always admitted. It gets the list with
    // twins so a live twin is not marked as outside the filter.
    final offer = componentUnitChoices(target, known, current: stored);

    final note = componentConversionLine(
      quantity: quantity.value,
      unit: unit,
      yields: yields,
      recipeMeasureId: measureId,
      // The live words, not the resolution's: a live but unresolvable word must
      // still read "3 blob — unresolved".
      measures: known,
    );

    // The manage state is its own page, so the amount surface below is the
    // sheet's body only while nothing is being authored.
    if (managing.value) {
      return AnsiSheetShell(
        title: 'Measures',
        subtitle: target.title,
        dismiss: AnsiSheetDismiss.back,
        // Drop the keyboard with the body: a focused field in a departing
        // subtree keeps a frame callback on a dead render object.
        onDismiss: () {
          FocusManager.instance.primaryFocus?.unfocus();
          managing.value = false;
        },
        children: [
          const SizedBox(height: 14),
          _TargetMeasures(
            target: target,
            measures: measures,
            onSetYield: onSetYield,
            // This door was opened mid-sentence, so the new measure is picked
            // and the sheet returns to the amount, as the ingredient dock does.
            onCoined: (m) {
              FocusManager.instance.primaryFocus?.unfocus();
              choice.value = RecipeMeasureOption(m);
              retiredNote.value = null;
              managing.value = false;
            },
            // Retiring the selected word reconciles the choice, so Done never
            // writes a tombstoned pointer.
            onRetired: (m) {
              if (choice.value case RecipeMeasureOption(
                measure: final sel,
              ) when sel.id == m.id) {
                final fallback = _defaultUnit(yields);
                choice.value = UnitOption(fallback);
                retiredNote.value =
                    '“${m.label}” retired — back to ${fallback.label}';
              }
            },
          ),
        ],
      );
    }

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
                // A text keyboard: iOS's numeric pads have no `/`, so `1/2`
                // could not be typed.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    // A number counting words prints by the kitchen rule, like
                    // every unitless amount.
                    text: unit == null
                        ? formatQuantity(quantity.value)
                        : formatQuantityIn(quantity.value, unit),
                  ),
                  onChange: (v) => quantity.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                // The picked word says what one of it comes to; nothing for a
                // gone word.
                word != null
                    ? recipeMeasureChipText(word)
                    : (unit?.label ?? ''),
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
        UnitChipRow(
          offer: offer,
          selected: picked,
          onSelect: (c) => choice.value = c,
          // The `+` opens the target recipe's words. No chip when the target
          // has no id (its row has not synced), or when it states no yield and
          // the host has no door to set one.
          onManage:
              mayCoinWords &&
                  target.id.isNotEmpty &&
                  (yields.isNotEmpty || onSetYield != null)
              ? () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  managing.value = true;
                }
              : null,
        ),
        if (retiredNote.value case final note?) ...[
          const SizedBox(height: 8),
          Text(
            note,
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        if (measureId != null && word == null) ...[
          const SizedBox(height: 8),
          Text(
            kGoneWordKeepsItsNumber,
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        // The no-yield state is not an error state: the link, the page and
        // scaling all work: only the derived numbers wait, one tap away.
        if (yields.isEmpty && onSetYield != null) ...[
          const SizedBox(height: 10),
          _SetYieldDoor(onTap: onSetYield!),
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
        if (amountless) ...[
          const SizedBox(height: 10),
          Text(
            kMeasuredLineNeedsANumber,
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        const SizedBox(height: 14),
        FButton(
          // A measured line with no number is refused by the server, and a
          // refused row drops the whole upload, so Done waits for the number.
          onPress: amountless
              ? null
              : () => onDone((
                  quantity: quantity.value,
                  unit: unit,
                  recipeMeasureId: measureId,
                  measure: word,
                  optional: optional.value,
                )),
          child: const Text('Done'),
        ),
      ],
    );
  }

  /// Which chip the sheet opens on.
  ///
  /// An edited line opens on its stored word (where the target still holds it)
  /// or unit; a line whose word has gone opens on nothing. A fresh amount opens
  /// on [firstComponentChoice] when that is one of the recipe's words,
  /// otherwise on the yield's own unit.
  UnitChoice? _openingChoice(List<RecipeMeasure> measures) {
    if (initialMeasureId case final id?) {
      final word = recipeMeasureById(id, measures);
      return word == null ? null : RecipeMeasureOption(word);
    }
    if (initialUnit case final unit?) return UnitOption(unit);
    final first = firstComponentChoice(target, measures);
    return first is RecipeMeasureOption
        ? first
        : UnitOption(_defaultUnit(target.yields));
  }

  /// Said while a measure is picked and the number is missing.
  static const kMeasuredLineNeedsANumber =
      'Say how many — a measure counts something.';

  /// Said on a line whose measure was deleted on the target recipe, or has not
  /// synced here yet.
  static const kGoneWordKeepsItsNumber =
      'This line’s measure is gone from that recipe — pick a chip to say it '
      'again.';
}

/// The one-tap way to the target's own editor, where MAKES is stated.
class _SetYieldDoor extends StatelessWidget {
  const _SetYieldDoor({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
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
  );
}

/// The manage state: the target recipe's own words, authored in place. No Save:
/// every tap writes through [RecipeMeasureRepository]. With no `makes` stated
/// it adds the door to where MAKES is set.
class _TargetMeasures extends ConsumerWidget {
  const _TargetMeasures({
    required this.target,
    required this.measures,
    required this.onSetYield,
    required this.onCoined,
    required this.onRetired,
  });

  final SubRecipeTarget target;
  final List<RecipeMeasure> measures;

  /// The way to the target's own editor, offered while it states no yield.
  final VoidCallback? onSetYield;

  /// A measure landed — the sheet picks it and returns to the amount.
  final ValueChanged<RecipeMeasure> onCoined;

  /// A word went — the sheet reconciles its selection if that was it.
  final ValueChanged<RecipeMeasure> onRetired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yields = target.yields;

    // A word that lines still say cannot be retired. The container and host are
    // captured before the gate's dialog, because this row can be gone by the
    // time it answers.
    Future<void> retire(RecipeMeasure m) async {
      final container = ProviderScope.containerOf(context, listen: false);
      final host = hostContextOf(context);
      if (!await mayDeleteRecipeMeasure(context, ref, m)) return;
      final gone = await container.writeOk(
        host,
        'retire “${m.label}”',
        () => container
            .read(recipeMeasureRepositoryProvider)
            .softDeleteRecipeMeasure(m.id),
      );
      if (gone) onRetired(m);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecipeMeasuresEditor(
          recipeId: target.id,
          // The TARGET's stored yields — what the sauce says a batch makes,
          // never the recipe being written.
          yields: yields,
          measures: measures,
          // Each write is wrapped at its call site, where the structural scan
          // reads it. The repository's refusal is shown under the field; other
          // throws are reported by the write door.
          onAdd: (m) async {
            final outcome = await ref.write(
              context,
              'coin “${m.label}”',
              () async {
                try {
                  final coined = await ref
                      .read(recipeMeasureRepositoryProvider)
                      .addRecipeMeasure(
                        recipeId: target.id,
                        label: m.label,
                        amount: m.amount,
                        unit: m.unit,
                      );
                  onCoined(coined);
                  return RecipeMeasureLanded(coined) as RecipeMeasureOutcome;
                } on RecipeMeasureRefused catch (e) {
                  return RecipeMeasureTurnedDown(e.message);
                }
              },
            );
            return outcome ?? const RecipeMeasureNotLanded();
          },
          onRestate: (m) async {
            final outcome = await ref.write(
              context,
              'save “${m.label}”',
              () async {
                try {
                  await ref
                      .read(recipeMeasureRepositoryProvider)
                      .restateRecipeMeasure(
                        measureId: m.id,
                        label: m.label,
                        amount: m.amount,
                        unit: m.unit,
                      );
                  return RecipeMeasureLanded(m) as RecipeMeasureOutcome;
                } on RecipeMeasureRefused catch (e) {
                  return RecipeMeasureTurnedDown(e.message);
                }
              },
            );
            return outcome ?? const RecipeMeasureNotLanded();
          },
          onDelete: retire,
          autofocus: true,
        ),
        if (onSetYield case final setYield? when yields.isEmpty) ...[
          const SizedBox(height: 10),
          _SetYieldDoor(onTap: setYield),
        ],
      ],
    );
  }
}

/// What a fresh component line counts on a recipe with no words: the yield's
/// own unit, else `batch`.
Unit _defaultUnit(List<YieldDenomination> yields) =>
    yields.isEmpty ? batches : yields.first.unit;

/// [live] (the watched, merged offer) plus every word of [loaded] the merge hid
/// behind one of them. Re-admitted by label, so a word retired behind the ＋
/// stays gone.
List<RecipeMeasure> _withHiddenTwins(
  List<RecipeMeasure> live,
  List<RecipeMeasure> loaded,
) {
  if (identical(live, loaded)) return live;
  final shown = {for (final m in live) m.id};
  final said = {for (final m in live) m.label};
  return [
    ...live,
    for (final m in loaded)
      if (!shown.contains(m.id) && said.contains(m.label)) m,
  ];
}

/// [picked], re-read from [measures] when it is one of the recipe's words, so a
/// selection follows a re-statement. A word no longer in the list selects
/// nothing.
UnitChoice? _seated(UnitChoice? picked, List<RecipeMeasure> measures) {
  if (picked is! RecipeMeasureOption) return picked;
  final live = recipeMeasureById(picked.measure.id, measures);
  return live == null ? null : RecipeMeasureOption(live);
}
