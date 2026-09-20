/// The quantity + unit-chip sheet for a **component** line (step 8.6 / D2,
/// design board frame d) — the 7.7 sheet's anatomy with batch math on the
/// chips.
///
/// Same dock, the same [UnitChipRow], the same live conversion line, the same
/// Optional row. What differs is the OFFER, and each difference is a
/// consequence of a component being a recipe rather than an ingredient
/// ([componentUnitChoices]):
///
/// - **the target recipe's own words lead it** — `3 blob` of a sauce, a word
///   the household coined on that recipe and nowhere else (ADR-0018). A word
///   is an amount in a unit, so it resolves through the recipe's own `makes`
///   exactly as `¼ cup` does, and the whole-batch word leads even that
///   ([wholeMeasureOfRecipe]);
/// - then `batch`, then **the yields' families**, kitchen-trimmed. `batch` is
///   always sayable, and a family opens only because the recipe states a yield
///   in it. There is no density for a recipe, so a family nobody stated is not
///   offered; the fix is the yield's optional second denomination, not a guess;
/// - the conversion line reads in batches ("0.25 cup = 0.25 of a batch ·
///   makes 1 cup"), and a recipe with no yield gets the *not-an-error* state:
///   the `batch` chip alone, the honest note, and one tap to go set the yield.
///   The link, the page and scaling all work meanwhile — only derived numbers
///   wait. No words either, because a word is an amount and an amount says
///   nothing about a batch until the batch has one too.
///
/// The 7.7 **stored-selection rule carries over** to both kinds: an imported
/// line's printed unit, and a word whose `makes` has been edited out from under
/// it, are admissible chips even when this sheet would not otherwise offer
/// them — marked as outside the filter and rendered with the honest unresolved
/// line, never silently rewritten.
///
/// **A line whose word has GONE selects nothing.** There is no honest
/// denomination to preselect: the word was the only place its amount lived, and
/// a chip lit here would claim the line says something it does not. So the row
/// opens with the offer and no selection, the number is kept, and the pointer
/// is kept with it until somebody picks a chip — which is the repair, the other
/// one being to put the word back under the target recipe's MEASURES.
///
/// **The `+` chip is the second repair, and the door a word is usually coined
/// through** — the household thinks of `blob` while writing the recipe that
/// says it, not while editing the sauce. It swaps the body for
/// [RecipeMeasuresEditor] aimed at the TARGET recipe, which is the one the word
/// belongs to, and that page has no Save of its own (ADR-0011): every tap
/// writes through [RecipeMeasureRepository], and the word is live and
/// selectable the moment it lands. Back returns to the amount with it picked.
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

/// What the component sheet resolved to: the amount, the denomination it counts
/// — **exactly one** of a catalog `unit` and one of the target's own words
/// (`recipeMeasureId`) — and whether the line is optional.
///
/// It is the nullability `LineItem.unit` carries, for the same reason: a line's
/// amount is said in a catalog unit **or** in one of the target recipe's words,
/// never both and never neither (migration 0048). The one case where both are
/// null is a line whose word has gone and whose reader picked nothing, where
/// the caller writes neither and the line keeps the pointer it already had.
typedef ComponentQuantity = ({
  double? quantity,
  Unit? unit,
  String? recipeMeasureId,

  /// The picked word itself, where one was picked. A word coined behind the ＋
  /// is minutes newer than the target the host is holding, so the row that
  /// prints the line has nowhere else to read it from — see
  /// [targetWithMeasure]. Null for a unit, and for a line whose word has gone.
  RecipeMeasure? measure,
  bool optional,
});

/// [target] with [word] among its measures.
///
/// A row says `3 blob` by looking the line's pointer up in
/// [SubRecipeTarget.measures] — the target the caller loaded. A word coined
/// behind the ＋ is not in that list, so the line it was coined for would read
/// a bare `3` until the recipe was saved and re-opened. Putting it there is the
/// whole of the fix; the next load reads the same word from the database.
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
/// [onSetYield] is the deep link the no-yield state offers ("Set the yield").
/// Null where there is nowhere to send the user (a host with no router).
///
/// [initialMeasureId] is `LineItem.recipeMeasureId` — the pointer the line
/// actually carries. Pass it whenever the line has one: the word itself is
/// looked up on [target], because that is where it lives.
///
/// [mayCoinWords] draws the `+` — see [ComponentQuantityEditor.mayCoinWords].
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

  /// The line's stored unit — always an admissible chip (the 7.7 rule).
  final Unit? initialUnit;

  /// The line's `recipe_measure_id`, when it says one of the target's own
  /// words. The word itself is read off [target] — never joined onto the line,
  /// which is what makes a re-stated `blob` follow through everywhere at once.
  final String? initialMeasureId;

  /// Whether the line already says it may be left out.
  final bool initialOptional;

  /// Whether this host can say a line in one of the target's own words — and
  /// so whether the chip row wears the `+` that coins one, and whether the
  /// sheet watches the target's live words at all.
  ///
  /// True wherever the line is a stored component line: both recipe-editor
  /// doors, the method editor's, and week mode's. **False in the import
  /// review**, whose two doors hand over a target with its words stripped: a
  /// review line stores a unit id and has no column for a pointer, so a word
  /// coined or picked there could only land as a whole batch (ADR-0018). A
  /// host with no words also has no vocabulary to manage, which is the same
  /// answer the price sheet gives the ingredient row.
  final bool mayCoinWords;

  final ValueChanged<ComponentQuantity> onDone;
  final VoidCallback? onSetYield;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yields = target.yields;
    // The chip the sheet opens on. Null is the one line with nothing honest to
    // preselect — a word that has gone — and it is the reason [UnitChipRow]'s
    // selection is nullable at all.
    final quantity = useState<double?>(initialQuantity);
    final optional = useState<bool>(initialOptional);
    final managing = useState(false);
    // Set when the manage state retired the selected word and the choice was
    // reconciled to the wordless denomination — the ingredient sheet's
    // deleted-note, for the same reason: Done must never write a tombstone.
    final retiredNote = useState<String?>(null);

    // **The target's LIVE words, not the caller's snapshot.** `target.measures`
    // was read when the host built its row, and a word coined behind the `+`
    // one tap ago has to reach this chip row without anybody reloading the
    // screen underneath. The snapshot stays the answer until the watch has
    // one — an errored or still-loading stream must not blank a row that was
    // drawing chips a frame ago, and an empty list IS an answer.
    final watched = mayCoinWords && target.id.isNotEmpty
        ? ref.watch(recipeMeasuresProvider(target.id)).asData?.value
        : null;
    final measures = watched ?? target.measures;
    // The watch hands out the MERGED offer; the loaded target also carries the
    // twins the merge hides, and a line written in one of those still means
    // what it said. So the words a pointer is resolved against are the live
    // ones plus those twins, while the chips stay one per word.
    final known = _withHiddenTwins(measures, target.measures);

    // Read against the LIVE words, so the 7.7 admission expires with the row:
    // a stored pointer whose word has just been retired behind the ＋ stops
    // being an admissible chip, instead of sitting there marked *not in
    // filter* where one tap would write the tombstone.
    final stored = _openingChoice(known);
    final choice = useState<UnitChoice?>(stored);

    // A word follows its row: the selection is re-read from the live list, so
    // a `blob` re-stated to 18 ml behind the `+` is the one the conversion
    // line speaks, and one retired out from under this sheet lights no chip.
    final picked = _seated(choice.value, known);
    final word = picked is RecipeMeasureOption ? picked.measure : null;
    final unit = switch (picked) {
      UnitOption(:final unit) => unit,
      RecipeMeasureOption() || null => null,
      MeasureOption(:final measure) => notAWordForARecipe(measure),
    };
    // The pointer the line will carry: the word that is picked, or — while
    // nothing has been picked at all — the one it arrived with, which is the
    // gone-word case. Picking any chip replaces it, and picking a unit clears
    // it: a line is denominated once (the repository refuses the other two
    // shapes outright).
    final measureId = word?.id ?? (picked == null ? initialMeasureId : null);

    // A measure counts something, so the line has to say how many.
    final amountless =
        measureId != null && (quantity.value == null || quantity.value == 0);

    // The offer, with the opening choice always admitted: a word whose `makes`
    // has been edited into another family is not in the honest filter, and must
    // still read as itself, marked, with the refusal under it.
    // The list with the twins, because the offer itself says each word once
    // and lets the line's own row win it — handing it the merged list instead
    // would mark a live twin as outside the filter.
    final offer = componentUnitChoices(target, known, current: stored);

    final note = componentConversionLine(
      quantity: quantity.value,
      unit: unit,
      yields: yields,
      recipeMeasureId: measureId,
      // The LIVE words, never the resolution's: a word can be perfectly alive
      // and still unresolvable (a `makes` restated into another family under
      // it), and that line must read "3 blob — unresolved — …" rather than a
      // bare "3 — unresolved".
      measures: known,
    );

    // The manage state is its own page, so the amount surface below is the
    // sheet's body only while nothing is being authored.
    if (managing.value) {
      return AnsiSheetShell(
        title: 'Measures',
        subtitle: target.title,
        dismiss: AnsiSheetDismiss.back,
        // The keyboard goes with the body: a focused field whose subtree is
        // about to leave keeps a frame callback pointed at a render object
        // that no longer exists.
        onDismiss: () {
          FocusManager.instance.primaryFocus?.unfocus();
          managing.value = false;
        },
        children: [
          const SizedBox(height: 14),
          _TargetMeasures(
            target: target,
            measures: measures,
            // The word is chosen the moment it exists: this door was opened
            // mid-sentence, and the sentence was "3 blob". Back then returns
            // to an amount already counting it.
            onCoined: (m) {
              choice.value = RecipeMeasureOption(m);
              retiredNote.value = null;
            },
            // Retiring the SELECTED word reconciles the choice, for the reason
            // the ingredient sheet's delete does: Done must never write a
            // tombstoned pointer. The note is the pending-note pattern.
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
                // A TEXT keyboard, not the decimal pad: iOS's numeric pads
                // carry no `/`, so `1/2` could not be typed on one — and a
                // fraction is how a recipe says this number.
                keyboardType: TextInputType.text,
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    // A number counting WORDS prints by the kitchen rule, like
                    // every other unitless amount: the unit lives on the
                    // measure, not on the line.
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
                // The picked word says what one of it comes to, exactly as a
                // picked ingredient measure does: the chip row carries the bare
                // word, the sentence beside the number carries its size.
                // Nothing at all for a gone word — the number is all this line
                // honestly says.
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
          // The `+` opens the TARGET recipe's own words — the sauce being
          // measured, not the recipe being written. A target with no id is a
          // component whose recipe row has not synced here: there is nothing
          // to stamp a word onto, so no chip rather than one that refuses.
          onManage: mayCoinWords && target.id.isNotEmpty
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
          // A line said in a measure with no number is a row the server
          // refuses — and a refused row drops the whole upload, not just
          // itself. So the door waits for the number rather than handing one
          // back that cannot be saved.
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
  /// A line being EDITED opens on its own stored denomination — its word where
  /// the target still holds it, else its unit — and a line whose word has gone
  /// opens on nothing at all. A FRESH amount opens on the first thing the offer
  /// leads with while that is one of the recipe's own words
  /// ([firstComponentChoice]: the whole-batch word, else the first word the
  /// recipe can still hold), and otherwise on the yield's own unit, which is
  /// the line a page prints — `¼ cup` of a `makes 1 cup` aioli — and the
  /// denomination this sheet has always opened wordless recipes on.
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

  /// What the sheet says about a line whose word has been retired on the target
  /// recipe, or has not synced here yet — one sentence, in the app's refusal
  /// voice: name the fact, and name both ways out.
  /// What the sheet says while a measure is picked and the number is not
  /// there — one fact, one way out.
  static const kMeasuredLineNeedsANumber =
      'Say how many — a measure counts something.';

  static const kGoneWordKeepsItsNumber =
      'The word this line was written in is gone from that recipe, so there is '
      'nothing counting it. The number is kept — put the word back under that '
      'recipe’s MEASURES, or say this line in one of the chips below.';
}

/// The manage state: the TARGET recipe's own words, authored in place.
///
/// It is `_MeasureManager` on the ingredient sheet, and it holds the same
/// posture — **this host has no Save**, so every tap is a write through
/// [RecipeMeasureRepository] and the word is live at once. What it adds is the
/// gate's own sentence: with no `makes` stated the editor draws its one
/// refusal instead of a form, and MAKES is set on the target's own editor,
/// named here in one muted line rather than built a second time.
class _TargetMeasures extends ConsumerWidget {
  const _TargetMeasures({
    required this.target,
    required this.measures,
    required this.onCoined,
    required this.onRetired,
  });

  final SubRecipeTarget target;
  final List<RecipeMeasure> measures;

  /// A word landed — the sheet selects it, so back returns to `3 blob`.
  final ValueChanged<RecipeMeasure> onCoined;

  /// A word went — the sheet reconciles its selection if that was it.
  final ValueChanged<RecipeMeasure> onRetired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yields = target.yields;

    // The bin, behind the gate: a word lines still say cannot go, and the
    // refusal is a sentence with a door rather than a failed write. The
    // container and the host are captured BEFORE the gate's dialog, because
    // this row can be gone by the time it answers.
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
          // Each write is wrapped where it is made rather than behind a
          // helper: the structural scan reads the call site, and so does a
          // person. The three endings are the editor's own — the repository's
          // refusal is the authoring contract and belongs under the field, a
          // write that threw for any other reason has already been said by the
          // write door, and anything else landed.
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
        if (yields.isEmpty) ...[
          const SizedBox(height: 10),
          // Where the gate above is lifted. One line, not a door: MAKES is
          // stated on the target's own editor, and a second place to set it
          // would be a second answer to one question.
          Text(
            'MAKES is stated on ${target.title}’s own editor — say what a '
            'batch makes there and this form opens.',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ],
      ],
    );
  }
}

/// What a fresh component line counts before anyone picks a chip, on a recipe
/// that coins no word: the yield's own unit when it states one, and `batch`
/// otherwise — the one denomination that never needs a yield.
Unit _defaultUnit(List<YieldDenomination> yields) =>
    yields.isEmpty ? batches : yields.first.unit;

/// [live] — the watched, merged offer — plus every word of [loaded] the merge
/// hid behind one of them.
///
/// A line is resolved by id, and the merge hides a duplicate word rather than
/// deleting it, so a line written in the hidden half of a `blob`/`blob` pair
/// must still read as `blob` in this sheet. The label is the merge's own key,
/// so a snapshot word is re-admitted only while a live word still says it: a
/// word RETIRED behind the ＋ leaves none, and goes on reading as gone.
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

/// [picked], re-read from [measures] when it is one of the recipe's own words.
///
/// A word is a row, and the row is what the conversion line and Done speak —
/// so a selection held across a re-statement must follow the number rather
/// than keep the copy it was picked from. A word that is no longer in the list
/// selects nothing, which is the sheet's honest gone-word state.
UnitChoice? _seated(UnitChoice? picked, List<RecipeMeasure> measures) {
  if (picked is! RecipeMeasureOption) return picked;
  final live = recipeMeasureById(picked.measure.id, measures);
  return live == null ? null : RecipeMeasureOption(live);
}
