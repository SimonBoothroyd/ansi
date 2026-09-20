/// The MEASURES editor — a recipe's own words for one of what its batch makes,
/// and the form that coins one (design board, the recipe editor's MEASURES
/// frame and the quantity dock's manage state).
///
/// It is `ingredients/presentation/measures_editor.dart` one level up, and
/// deliberately the same shape: the household is stating the same kind of fact
/// — a word, and what one of it comes to — so the row reads the same, the add
/// form is the same [MeasureForm] run at one control height, and the keyboard
/// behaves the same (a landed word clears the slots, KEEPS the unit and goes
/// back to the label; a refused one keeps everything typed and says why under
/// the field).
///
/// **It knows no repository and no host.** Two doors author a word and the
/// difference is whether the host has a Save (ADR-0011): the recipe editor's
/// header form defers into `Recipe.measures`, and the ＋ on a component's
/// quantity dock writes on tap. Both hand this widget the same three callbacks
/// and get the same validation, because the rules are
/// [authorRecipeMeasure]'s rather than either door's — so nothing here may
/// assume it lives inside a form with a Save, or inside a page without one.
///
/// **The gate is drawn, not hidden.** A word is an amount, and an amount says
/// nothing about a batch until the batch has one too, so with no yield stated
/// the add form is replaced by the domain's own sentence
/// ([kRecipeMeasureNoYieldRefusal]) — one sentence, no controls that could only
/// produce a refusal. The words the recipe already has are still listed, each
/// one honest about the gap, because they exist and hiding them would be the
/// lie.
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
import '../../../shared/reorder_grip.dart';
import '../domain/component_math.dart';
import '../domain/recipe_measure_authoring.dart';
import 'component_format.dart';

const _uuid = Uuid();

/// What the host did when the editor asked it to land a word.
///
/// A value rather than an exception, because the two failures belong on two
/// different surfaces: a **refusal** is the authoring contract and belongs
/// inline under the field, while a write that did not happen has already been
/// reported by the host's own write door and must not be said twice.
sealed class RecipeMeasureOutcome {
  const RecipeMeasureOutcome();
}

/// It landed — in the draft for a host with a Save, in the database for one
/// without. Either way the editor may treat [measure] as real.
class RecipeMeasureLanded extends RecipeMeasureOutcome {
  const RecipeMeasureLanded(this.measure);

  final RecipeMeasure measure;
}

/// The host's own layer refused it, in words meant for the person: shown under
/// the field, not in a toast. The direct door's repository re-reads the
/// recipe's yields and words inside its transaction, so it can still refuse
/// what this form let through — a form's copy of the world is minutes old.
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
    this.onReorder,
    this.addLabel = 'Save',
    this.autofocus = false,
    super.key,
  });

  /// The recipe these words belong to — stamped on every one this form mints,
  /// because a word is a word for ONE recipe.
  final String recipeId;

  /// What the recipe says a batch makes, **as the host holds it right now**. It
  /// is the gate: passed from a draft it re-evaluates the whole section on the
  /// same keystroke that edits MAKES, which is the point of the section sitting
  /// under it.
  final List<YieldDenomination> yields;

  /// The recipe's words, in list order — the draft's for a deferred host, the
  /// watched rows for a direct one.
  final List<RecipeMeasure> measures;

  /// A word was authored and may be landed. Called only with a measure
  /// [authorRecipeMeasure] has already passed against [yields] and [measures],
  /// so a host that has nothing else to check can land it unconditionally; the
  /// id is a fresh one, which a direct door is free to ignore in favour of the
  /// row it writes.
  final Future<RecipeMeasureOutcome> Function(RecipeMeasure) onAdd;

  /// An existing word was re-stated — a new label, a new number, a new unit, or
  /// any two. **It keeps its id**, which is the whole reason this is not a
  /// delete and a re-add: every line already saying the word follows the
  /// correction.
  final Future<RecipeMeasureOutcome> Function(RecipeMeasure) onRestate;

  /// The bin. The host owns the delete gate — a word lines still say cannot go
  /// (`mayDeleteRecipeMeasure`), and only the host knows whether the row is a
  /// draft one or a live one.
  final Future<void> Function(RecipeMeasure) onDelete;

  /// The list in the order the drag left it, by id. **Null draws no grip and no
  /// drag**: `sort_order` is stored and read, but the gesture is a later pass
  /// (ADR-0018, "out of the first slice") — the order a household types their
  /// words in is already the order they get.
  final Future<void> Function(List<String> ids)? onReorder;

  /// What the add form's button says. `Save` in a host that commits on tap, and
  /// `Add` where the tap only puts the word in a draft — a button reading Save
  /// that saves nothing would give the form's own docked Save a rival.
  final String addLabel;

  /// Whether the label slot takes the keyboard on open. True for a door that
  /// opened to ask this one question; false inside a screen somebody is
  /// scrolling.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // The add form's draft, held as the CONTROLLERS its slots are drawn from
    // rather than as values beside them: a word landing is the start of the
    // next one, so this form has to be able to empty its own slots.
    final label = useTextEditingController();
    final amount = useTextEditingController();
    final labelFocus = useFocusNode();
    // What the person picked, and null while they have not. The distinction is
    // load-bearing: an unpicked slot FOLLOWS what MAKES says, so setting a
    // yield after opening the form seats the right unit, while a deliberate
    // pick is never silently re-aimed by a later MAKES edit — it stands, and
    // the Save says in the domain's own words why it cannot be held.
    final picked = useState<Unit?>(null);
    final error = useState<String?>(null);
    // Which row is open for editing, by id — one at a time, because the form it
    // opens into is the add form's own shape and two of them stacked would read
    // as two drafts of the same list.
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
        // The refusal is the authoring rule's own sentence, under the field
        // that caused it, and everything typed stays where it is: the fix for
        // every one of them is an edit to what is already on screen.
        case Err(:final failure):
          error.value = failure.message;
          return;
        case Ok(:final value):
          word = value;
      }
      error.value = null;
      final outcome = await onAdd(word);
      // The host can be dismissed while the write is in flight — touching its
      // state after that throws.
      if (!context.mounted) return;
      switch (outcome) {
        case RecipeMeasureTurnedDown(:final reason):
          error.value = reason;
        // The host's own guard has already said so; saying it twice is worse
        // than saying it once.
        case RecipeMeasureNotLanded():
          return;
        case RecipeMeasureLanded():
          // The words and the figure clear, ready for the next one — a
          // household names a blob, a ladle and a loaf in one sitting. **The
          // unit stays where they left it**: those three usually come off one
          // scale, so it is the one part of the last word that is also true of
          // the next.
          label.clear();
          amount.clear();
          // And the keyboard goes back to the first slot, but only where this
          // form is still on screen: a field that is leaving must not take the
          // keyboard with it over the surface behind it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) labelFocus.requestFocus();
          });
      }
    }

    Widget row(RecipeMeasure m, int index) => RecipeMeasureRow(
      key: ValueKey('recipe-measure-${m.id}'),
      measure: m,
      resolves: recipeMeasureResolvesAgainst(m, yields),
      dragIndex: onReorder == null ? null : index,
      onDelete: onDelete,
      onTap: () => editing.value = m.id,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nothing to say about an empty list while the gate below is the whole
        // section: two sentences where one is the answer reads as two problems.
        if (measures.isEmpty)
          if (unit != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'No words yet — a component line can still say “0.5 batch”.',
                style: ansiMono(size: 12, color: AnsiColors.muted),
              ),
            )
          else
            const SizedBox.shrink()
        else if (editing.value != null || onReorder == null)
          // A row open for editing is not a row you can drag, and the plain
          // column is also what keeps the form out of a scrollable of its own:
          // a field inside the list scrolling ITSELF into view, in a subtree
          // Save is about to remove, is an animation pointed at a render object
          // that has gone.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, m) in measures.indexed)
                if (editing.value == m.id)
                  _EditRecipeMeasureForm(
                    key: ValueKey('edit-recipe-measure-${m.id}'),
                    measure: m,
                    yields: yields,
                    measures: measures,
                    onRestate: onRestate,
                    onDone: () {
                      // The keyboard goes with the form: a focused field whose
                      // row is about to leave the tree keeps a frame callback
                      // pointed at a render object that no longer exists.
                      FocusManager.instance.primaryFocus?.unfocus();
                      editing.value = null;
                    },
                  )
                else
                  row(m, i),
            ],
          )
        else
          ReorderableList(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: measures.length,
            proxyDecorator: liftedRow,
            onReorderItem: (oldIndex, newIndex) {
              final ids = [for (final m in measures) m.id];
              ids.insert(newIndex, ids.removeAt(oldIndex));
              onReorder!(ids);
            },
            itemBuilder: (context, index) => row(measures[index], index),
          ),
        const SizedBox(height: 12),
        if (unit == null)
          // The honest cost of the ruling, paid at the door and naming the fix
          // (ADR-0018): no form, because a form here could only refuse.
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
            // The person's own pick is always offered back, even where MAKES
            // has stopped stating its family: a chip that silently re-aimed
            // itself would change the sentence they typed.
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

/// One word as a line in the editor — and the door to re-stating it.
///
/// The row itself is the tap target, for the ingredient list's reason: a word
/// and its number are both things a household gets wrong the first time (a
/// `blob` that turns out to be 18 g), and the only fix without this is
/// delete-and-re-add, which mints a new id and strands every line already
/// pointing at the old one.
///
/// No source dot and no legend: an ingredient's measures arrive from USDA, a
/// borrow or an estimate, and a recipe's only ever come from the household that
/// wrote the recipe.
class RecipeMeasureRow extends StatelessWidget {
  const RecipeMeasureRow({
    required this.measure,
    required this.onDelete,
    this.resolves = true,
    this.dragIndex,
    this.onTap,
    super.key,
  });

  final RecipeMeasure measure;
  final Future<void> Function(RecipeMeasure) onDelete;

  /// Whether the recipe can still hold this word — false draws the gap under
  /// it, in its own words. Never a refusal: the word is alive, and it is MAKES
  /// that has stopped saying enough.
  final bool resolves;

  /// The row's position in the reorderable list it drags within. Null where the
  /// list does not reorder.
  final int? dragIndex;

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
                if (dragIndex case final index?) DragGrip(index: index),
                // The two spans are a word and its number, read as ONE
                // sentence — `blob · 15 g`, the way this app says the pair —
                // because a reader who gets no columns gets no gap between
                // them either. The grip and the bin stay outside it: they are
                // controls, and a control merged into a sentence loses its own
                // name.
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

/// The add form's shape, seeded from an existing row: the word, what one of it
/// comes to in the unit it was stated in, Save — and a way back out that
/// changes nothing.
///
/// It holds its own draft rather than borrowing the add form's, so opening a
/// row for editing never eats a half-typed new word.
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
    // A stored word opens in the unit it was stated in — re-stating it in
    // another family the recipe makes is a pick away.
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
        // The id is the row's, which is what makes this a re-statement: every
        // line already saying the word follows the number.
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
