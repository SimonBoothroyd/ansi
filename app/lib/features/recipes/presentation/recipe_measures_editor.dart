/// The recipe MEASURES editor: a recipe's own words for an amount of what its
/// batch makes, and the form that coins one. The same shape and [MeasureForm]
/// as `ingredients/presentation/measures_editor.dart`.
///
/// It knows no repository and no host. The recipe editor defers words into
/// `Recipe.measures`; the component quantity dock's ＋ writes on tap (ADR-0011).
/// Both pass the same callbacks, and [authorRecipeMeasure] validates for both.
/// With no yield stated the add form is replaced by
/// [kRecipeMeasureNoYieldRefusal]; existing words are still listed.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/measure_form.dart';
import '../domain/component_math.dart';
import '../domain/recipe_measure_authoring.dart';
import 'component_format.dart';

const _uuid = Uuid();

/// What the host did when asked to land a word. A value, not an exception: a
/// refusal shows inline under the field, while a failed write has already been
/// reported by the host's write door.
sealed class RecipeMeasureOutcome {
  const RecipeMeasureOutcome();
}

/// It landed: in the draft for a host with a Save, in the database otherwise.
class RecipeMeasureLanded extends RecipeMeasureOutcome {
  const RecipeMeasureLanded(this.measure);

  final RecipeMeasure measure;
}

/// The host refused it, in words shown under the field. A direct door re-reads
/// the recipe's yields and words in its transaction, so it can refuse what the
/// form let through.
class RecipeMeasureTurnedDown extends RecipeMeasureOutcome {
  const RecipeMeasureTurnedDown(this.reason);

  final String reason;
}

/// Nothing was written and the host has already said so.
class RecipeMeasureNotLanded extends RecipeMeasureOutcome {
  const RecipeMeasureNotLanded();
}

class RecipeMeasuresEditor extends HookWidget {
  const RecipeMeasuresEditor({
    required this.recipeId,
    required this.yields,
    required this.measures,
    required this.onAdd,
    required this.onRestate,
    required this.onDelete,
    this.addLabel = 'Save',
    this.autofocus = false,
    super.key,
  });

  /// The recipe these words belong to, stamped on every one this form mints.
  final String recipeId;

  /// What the recipe says a batch makes, as the host holds it now. It gates the
  /// add form and re-evaluates as MAKES is edited.
  final List<YieldDenomination> yields;

  /// The recipe's words, in list order.
  final List<RecipeMeasure> measures;

  /// Lands a new word. Called only with a measure [authorRecipeMeasure] has
  /// passed against [yields] and [measures]; its id is fresh, and a direct door
  /// may replace it with the written row's.
  final Future<RecipeMeasureOutcome> Function(RecipeMeasure) onAdd;

  /// Re-states an existing word (label, number or unit). It keeps its id, so
  /// every line saying the word follows the correction.
  final Future<RecipeMeasureOutcome> Function(RecipeMeasure) onRestate;

  /// The bin. The host owns the delete gate (`mayDeleteRecipeMeasure`).
  final Future<void> Function(RecipeMeasure) onDelete;

  /// The add button's label: `Save` where the tap commits, `Add` where it only
  /// drafts.
  final String addLabel;

  /// Whether the label slot takes the keyboard on open.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // Held as controllers so the form can clear its own slots after a word
    // lands.
    final label = useTextEditingController();
    final amount = useTextEditingController();
    final labelFocus = useFocusNode();
    // The picked unit, or null while unpicked. An unpicked slot follows what
    // MAKES says; a deliberate pick is never re-aimed by a later MAKES edit.
    final picked = useState<Unit?>(null);
    final error = useState<String?>(null);
    // The row open for editing, by id; one at a time.
    final editing = useState<String?>(null);

    final opening = recipeMeasureOpeningUnit(yields);
    final unit = picked.value ?? opening;
    final choices = recipeMeasureUnitChoices(yields);

    Future<void> save() async {
      if (unit == null) return;
      final RecipeMeasure word;
      switch (authorRecipeMeasure(
        id: _uuid.v4(),
        recipeId: recipeId,
        label: label.text,
        amount: parseAmount(amount.text),
        unit: unit,
        yields: yields,
        measures: measures,
        sortOrder: measures.length,
      )) {
        // The authoring refusal shows under the field, and everything typed
        // stays.
        case Err(:final failure):
          error.value = failure.message;
          return;
        case Ok(:final value):
          word = value;
      }
      error.value = null;
      final outcome = await onAdd(word);
      // The host can be dismissed while the write is in flight.
      if (!context.mounted) return;
      switch (outcome) {
        case RecipeMeasureTurnedDown(:final reason):
          error.value = reason;
        // The host's write door has already reported it.
        case RecipeMeasureNotLanded():
          return;
        case RecipeMeasureLanded():
          // The label and figure clear for the next word; the unit stays, since
          // consecutive words usually share one.
          label.clear();
          amount.clear();
          // Refocus the first slot, but only while this form is still on
          // screen.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) labelFocus.requestFocus();
          });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // An empty list says nothing while the no-yield gate below is showing.
        if (measures.isEmpty)
          if (unit != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'No measures yet — a component line can still say “0.5 batch”.',
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            )
          else
            const SizedBox.shrink()
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in measures)
                if (editing.value == m.id)
                  _EditRecipeMeasureForm(
                    key: ValueKey('edit-recipe-measure-${m.id}'),
                    measure: m,
                    yields: yields,
                    measures: measures,
                    onRestate: onRestate,
                    onDone: () {
                      // Unfocus first: a focused field leaving the tree keeps a
                      // frame callback on a dead render object.
                      FocusManager.instance.primaryFocus?.unfocus();
                      editing.value = null;
                    },
                  )
                else
                  RecipeMeasureRow(
                    key: ValueKey('recipe-measure-${m.id}'),
                    measure: m,
                    resolves: recipeMeasureResolvesAgainst(m, yields),
                    onDelete: onDelete,
                    onTap: () => editing.value = m.id,
                  ),
            ],
          ),
        const SizedBox(height: 12),
        if (unit == null)
          // No form without a yield: it could only refuse (ADR-0018).
          Text(
            kRecipeMeasureNoYieldRefusal,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          )
        else
          MeasureForm(
            icon: FLucideIcons.plus,
            headline: 'ADD MEASURE',
            saveLabel: addLabel,
            slot: 'add-word',
            hint: 'label — “blob”',
            // The person's own pick is always offered back, even when MAKES no
            // longer states its family.
            units: [...choices, if (!choices.contains(unit)) unit],
            unit: unit,
            error: error.value,
            autofocus: autofocus,
            label: label,
            labelFocus: labelFocus,
            amount: amount,
            onUnit: (u) => picked.value = u,
            onSave: save,
            footer: Text(
              'one of them, weighed — another recipe can then say “3 blob” of '
              'this one',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
      ],
    );
  }
}

/// One word as a row. The row is the tap target for re-stating it, because
/// delete-and-re-add would mint a new id and strand every line pointing at the
/// old one.
class RecipeMeasureRow extends StatelessWidget {
  const RecipeMeasureRow({
    required this.measure,
    required this.onDelete,
    this.resolves = true,
    this.onTap,
    super.key,
  });

  final RecipeMeasure measure;
  final Future<void> Function(RecipeMeasure) onDelete;

  /// Whether the recipe's MAKES still supports this word; false draws the gap
  /// under it.
  final bool resolves;

  /// Opens the row for re-stating. Null where the list is read-only.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AnsiColors.line)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // The word and its number read as one sentence (`blob · 15 g`);
                // the bin stays outside it.
                Expanded(
                  child: Semantics(
                    label: recipeMeasureListText(measure),
                    container: true,
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            measure.label,
                            style: ansiSans(size: 14, weight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          recipeMeasureAmountText(measure),
                          style: ansiMono(size: 11, color: AnsiColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnsiTap(
                  onTap: () => onDelete(measure),
                  semanticsLabel: 'Delete the measure',
                  color: AnsiColors.muted,
                  child: const Icon(FLucideIcons.trash2, size: 15),
                ),
              ],
            ),
            if (!resolves)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  recipeMeasureOrphanedRowNote(measure),
                  style: ansiMono(size: 10, color: AnsiColors.aging),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The add form's shape seeded from an existing row, with Save and a cancel. It
/// holds its own draft, so editing a row never eats a half-typed new word.
class _EditRecipeMeasureForm extends HookWidget {
  const _EditRecipeMeasureForm({
    required this.measure,
    required this.yields,
    required this.measures,
    required this.onRestate,
    required this.onDone,
    super.key,
  });

  final RecipeMeasure measure;
  final List<YieldDenomination> yields;
  final List<RecipeMeasure> measures;
  final Future<RecipeMeasureOutcome> Function(RecipeMeasure) onRestate;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    // Opens in the unit the word was stated in.
    final picked = useState<Unit>(measure.unit);
    final label = useTextEditingController(text: measure.label);
    final amount = useTextEditingController(
      text: formatAmountIn(measure.amount, measure.unit),
    );
    final error = useState<String?>(null);
    final choices = recipeMeasureUnitChoices(yields);

    Future<void> save() async {
      final RecipeMeasure restated;
      switch (authorRecipeMeasure(
        // The row's id, so this is a re-statement and lines saying the word
        // follow.
        id: measure.id,
        recipeId: measure.recipeId,
        label: label.text,
        amount: parseAmount(amount.text),
        unit: picked.value,
        yields: yields,
        measures: measures,
        sortOrder: measure.sortOrder,
      )) {
        case Err(:final failure):
          error.value = failure.message;
          return;
        case Ok(:final value):
          restated = value;
      }
      error.value = null;
      final outcome = await onRestate(restated);
      if (!context.mounted) return;
      switch (outcome) {
        case RecipeMeasureTurnedDown(:final reason):
          error.value = reason;
        case RecipeMeasureNotLanded():
          return;
        case RecipeMeasureLanded():
          onDone();
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MeasureForm(
        icon: FLucideIcons.pencil,
        headline: 'EDIT MEASURE',
        saveLabel: 'Save',
        slot: 'edit-word',
        hint: 'label — “blob”',
        units: [...choices, if (!choices.contains(picked.value)) picked.value],
        unit: picked.value,
        label: label,
        amount: amount,
        error: error.value,
        autofocus: false,
        onUnit: (u) => picked.value = u,
        onSave: save,
        footer: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDone,
          child: Text(
            'leave it as it was',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
      ),
    );
  }
}
