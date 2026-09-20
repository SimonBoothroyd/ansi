/// The manage-measures editor (design board `pv2-b2`, step 7.7/7.8) —
/// extracted from the quantity sheet's second state so the step-8.5 flesh-out
/// form shares it rather than growing a second one, exactly as `DensityEntry`
/// was extracted before it.
///
/// What it owns: the ingredient's live measure rows with their provenance
/// read in words, their order, deletion, and the add/edit form — a label and
/// an amount **with the unit it was weighed in**, converted into the row's
/// basis on save (g for a per-100 g row, ml for per-100 ml, ADR-0008). The
/// unit is offered rather than printed for the reason every other sentence
/// here offers it: a scale prints ounces, and dividing by 28.35 in your head
/// before you can type is arithmetic the app is for.
///
/// What it deliberately does **not** own is the density: a
/// volume-named label ("cup") is not a measure at all — that mapping *is* a
/// density (ADR-0008 §2) — so the form refuses it and hands the resolved
/// spoon back through [MeasuresEditor.onVolumeLabel], leaving the host to
/// point its own density entry at it. Two hosts, one door, and no second
/// density widget.
///
/// It asks nothing about `piece` (ADR-0015): whether a row may say `piece` is
/// a fact about the row — its default unit and its piece weight — never about
/// which measures it happens to carry.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/format.dart';
import '../../../shared/measure_form.dart';
import '../../../shared/reorder_grip.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/serving_measure.dart';

/// What the host did when the editor asked it to add a measure.
///
/// A value rather than an exception, because the two failures belong on two
/// different surfaces: a **refusal** is the repository's documented validation
/// contract and belongs inline under the field, while a write that did not
/// happen has already been reported by the host's own guard and must not be
/// said twice.
sealed class AddMeasureOutcome {
  const AddMeasureOutcome();
}

/// It landed — or, once the form defers (lane B), it is in the draft and will.
/// Either way the editor may treat [measure] as real: it has an id and can be
/// handed to `onAdded`.
class MeasureAdded extends AddMeasureOutcome {
  const MeasureAdded(this.measure);

  final Measure measure;
}

/// The repository refused it, in words meant for the person: shown under the
/// field, not in a toast.
class MeasureRefused extends AddMeasureOutcome {
  const MeasureRefused(this.reason);

  final String reason;
}

/// Nothing was written and the host has already said so.
class MeasureNotAdded extends AddMeasureOutcome {
  const MeasureNotAdded();
}

class MeasuresEditor extends HookWidget {
  const MeasuresEditor({
    required this.ingredient,
    required this.measures,
    required this.onDelete,
    required this.onAdd,
    required this.onEdit,
    required this.onReorder,
    required this.onAdded,
    required this.onVolumeLabel,
    this.addLabel = 'Save',
    this.autofocus = false,
    super.key,
  });

  final Ingredient ingredient;

  /// The ingredient's live measures, as the host already watches them (the
  /// quantity sheet needs the same list for its chip row).
  final List<Measure> measures;

  /// Deletion runs through the host: the quantity sheet has to reconcile a
  /// selection pointing at the row being tombstoned.
  final Future<void> Function(Measure) onDelete;

  /// A measure was authored. The quantity sheet selects it; the flesh-out form
  /// has nothing to select and ignores it. **The host decides when a measure
  /// lands** (ADR-0011). This widget validates the label and the amount —
  /// including the ADR-0008 §2 volume-label redirect — and then asks. It does
  /// not know a repository.
  ///
  /// The quantity sheet's host writes immediately; the flesh-out form's host
  /// will hold it in a draft until Save (lane B). The outcome is a value
  /// rather than an exception because the two failures belong on two
  /// different surfaces: a **refusal** is the repository's documented
  /// validation contract and belongs inline under the field, while a write
  /// that simply did not happen has already been reported by the host's own
  /// guard and must not be repeated here.
  final Future<AddMeasureOutcome> Function(String label, double amount) onAdd;

  /// An existing measure was re-stated: a new label, a new amount, or both.
  /// The row keeps its id, so every line already pointing at it follows the
  /// correction rather than being orphaned by a delete-and-re-add.
  ///
  /// Same outcome vocabulary as [onAdd], and for the same reason: a
  /// [MeasureRefused] is the repository's validation contract and belongs
  /// under the field, while a write that did not happen has already been
  /// reported by the host.
  final Future<AddMeasureOutcome> Function(Measure, String label, double amount)
  onEdit;

  /// The list, in the order the drag left it. **The first measure is the
  /// ingredient's typical one** — it fronts the picker's measure chips and it
  /// is what the shop's whole-unit hint rounds an unattributed total to — so
  /// the order is the household saying which one that is, rather than a flag
  /// that would have to be explained.
  final Future<void> Function(List<String> ids) onReorder;

  final ValueChanged<Measure> onAdded;

  /// A volume-named label was refused and resolved to that catalog unit —
  /// the host points its density entry at it (the "volume-label redirect").
  final ValueChanged<Unit> onVolumeLabel;

  /// What the add form's button says. `Save` in a host that commits on tap —
  /// the quantity sheet — and `Add` on the flesh-out form, where the tap only
  /// puts it in the draft. A button reading Save that saves nothing is the
  /// confusion this plan exists to remove, and it would give the form's own
  /// docked Save a rival again.
  final String addLabel;

  /// The quantity sheet opens straight into this state with the keyboard up;
  /// the flesh-out form must not steal focus from a screen the user is
  /// scrolling.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // The add form's draft, held as the CONTROLLERS its slots are drawn from
    // rather than as values beside them. A Forui managed control seeds itself
    // once, so a form whose only handle is the text it was told about can
    // read its slots but never put them back — and this form has to put them
    // back, because a measure landing is the start of the next one.
    final label = useTextEditingController();
    final amount = useTextEditingController();
    final labelFocus = useFocusNode();
    // What the form opens on: the row's own basis unit, every time the form
    // is opened fresh. A landed measure does NOT put the unit back to it —
    // see the reset in `save`.
    final openingUnit = ingredient.macrosBasis.baseUnit;
    final amountUnit = useState<Unit>(openingUnit);
    final error = useState<String?>(null);
    // Which row is open for editing, by id — one at a time, because the form
    // it opens into is the add form's own shape and two of them stacked would
    // read as two drafts of the same list.
    final editing = useState<String?>(null);

    final baseLabel = ingredient.macrosBasis.baseUnit.label;
    // The row's SERVING is not one of its measures (it is stated in the
    // nutrition section, beside the figures it is printed per) and a
    // volume-named label is a density in disguise. Neither belongs in a list
    // of this ingredient's own count words.
    final listed = measures
        .where((m) => !isVolumeUnitLabel(m.label) && !isServingMeasure(m))
        .toList();

    Future<void> save() async {
      final name = label.text.trim();
      final weight = parseAmount(amount.text);
      if (name.isEmpty) {
        error.value = 'give the measure a name';
        return;
      }
      final volumeUnit = volumeUnitFromLabel(name);
      if (volumeUnit != null) {
        // Density owns volume conversion (ADR-0008 §2: a volume-named
        // weight mapping IS a density) — offer the right door instead of
        // just refusing.
        onVolumeLabel(volumeUnit);
        error.value =
            '“$name” is a unit — that mapping is the density; '
            'enter it in the density section and the ${volumeUnit.label} '
            'chip unlocks';
        return;
      }
      if (weight == null || !(weight > 0)) {
        error.value =
            'measure it: ${amountUnit.value.label} must be a positive number';
        return;
      }
      final inBasis = _inBasis(ingredient, weight, amountUnit.value);
      if (inBasis == null) {
        error.value = _noBridge(amountUnit.value, baseLabel);
        return;
      }
      error.value = null;
      final outcome = await onAdd(name, inBasis);
      // The host can be dismissed while the write is in flight — touching its
      // state after that throws (every sibling path guards).
      if (!context.mounted) return;
      switch (outcome) {
        // The repository's documented validation contract, in the form's own
        // words, under the field that caused it.
        case MeasureRefused(:final reason):
          error.value = reason;
          return;
        // The host's guard has already said so; saying it twice is worse than
        // saying it once.
        case MeasureNotAdded():
          return;
        case MeasureAdded(:final measure):
          // The host takes it FIRST, so nothing the reset does can lose a
          // measure that has already landed.
          onAdded(measure);
          // Then the words and the figure clear, ready for the next one: a
          // household names a size, a fragment and a container in one
          // sitting, and a form still holding the last one asks the person to
          // clear two controls before the second — or lets them add "half
          // cheek" twice without noticing.
          //
          // **The unit stays where they left it** (owner). Three measures
          // usually come off one scale reading, so the unit is the one part
          // of the last measure that is also true of the next; putting it
          // back to the basis unit made the person re-pick ounces for every
          // row. A fresh open still starts on the row's basis unit.
          label.clear();
          amount.clear();
          // And the keyboard goes back to the first slot — but only where
          // this form is still on screen. The quantity sheet's host closes
          // the manage state on an add, and a field that is leaving must not
          // take the keyboard with it over the surface behind it.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) labelFocus.requestFocus();
          });
      }
    }

    Widget editForm(Measure m) => Padding(
      key: ValueKey('edit-measure-${m.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _EditMeasureForm(
        ingredient: ingredient,
        measure: m,
        onEdit: (l, a) => onEdit(m, l, a),
        // The keyboard goes with the form: a focused field whose row is about
        // to leave the tree keeps a frame callback pointed at a render object
        // that no longer exists.
        onDone: () {
          FocusManager.instance.primaryFocus?.unfocus();
          editing.value = null;
        },
        onVolumeLabel: onVolumeLabel,
      ),
    );

    Widget row(Measure m, int index) => MeasureRow(
      key: ValueKey('measure-${m.id}'),
      measure: m,
      dragIndex: index,
      onDelete: onDelete,
      onTap: () => editing.value = m.id,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No measures yet — name one below.',
              style: ansiMono(size: 12, color: AnsiColors.muted),
            ),
          )
        else if (editing.value != null)
          // A row open for editing is not a row you can drag, and the plain
          // column is also what keeps the form out of a scrollable of its own:
          // a field inside the list scrolling ITSELF into view, in a subtree
          // Save is about to remove, is an animation pointed at a render
          // object that has gone.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, m) in listed.indexed)
                if (editing.value == m.id) editForm(m) else row(m, i),
            ],
          )
        else
          // The list is draggable because **the first row is the typical
          // measure**: it fronts the chip row, and the shop rounds to it. The
          // grip is the only thing that starts a move — the rows are tap
          // targets, and a long-press anywhere would turn a scroll into an
          // accidental reorder. It shrink-wraps and never scrolls itself: it
          // is a short list inside a page that already scrolls.
          ReorderableList(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listed.length,
            proxyDecorator: liftedRow,
            onReorderItem: (oldIndex, newIndex) {
              final ids = [for (final m in listed) m.id];
              ids.insert(newIndex, ids.removeAt(oldIndex));
              onReorder(ids);
            },
            itemBuilder: (context, index) => row(listed[index], index),
          ),
        const SizedBox(height: 12),
        MeasureForm(
          icon: FLucideIcons.plus,
          headline: 'ADD MEASURE',
          saveLabel: addLabel,
          slot: 'add',
          units: basisConvertibleUnits(ingredient),
          unit: amountUnit.value,
          error: error.value,
          autofocus: autofocus,
          label: label,
          labelFocus: labelFocus,
          amount: amount,
          onUnit: (u) => amountUnit.value = u,
          onSave: save,
          footer: Row(
            children: [
              const SourceDot(kind: MeasureSourceKind.manual),
              const SizedBox(width: 5),
              Text(
                'saved as yours — synced & editable',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One measure as a line in the editor — and the door to re-stating it.
///
/// The row itself is the tap target: a measure is a label and a weight, both
/// of which a household gets wrong the first time (a `can (400 g)` that turns
/// out to hold 380, a `clove` somebody meant to call `clove, fat`), and the
/// only fix before this was delete-and-re-add, which mints a new id and
/// orphans every line already pointing at the old one.
class MeasureRow extends StatelessWidget {
  const MeasureRow({
    required this.measure,
    required this.onDelete,
    this.dragIndex,
    this.onTap,
    super.key,
  });

  final Measure measure;
  final Future<void> Function(Measure) onDelete;

  /// The row's position in the reorderable list it drags within. Null where
  /// the list does not reorder.
  final int? dragIndex;

  /// Opens the row for editing. Null where the list is read-only.
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
        child: Row(
          children: [
            if (dragIndex case final index?) DragGrip(index: index),
            SourceDot(kind: measure.sourceKind),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                measure.label,
                style: ansiSans(size: 14, weight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatQuantityIn(measure.amount, measure.basis.baseUnit)} '
              '${measure.basis.baseUnit.label}',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
            const Spacer(),
            Text(
              measureSourceWord(measure.sourceKind),
              style: ansiMono(size: 9, color: AnsiColors.muted),
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
      ),
    );
  }
}

/// The add form's shape, seeded from an existing row: a label, an amount in
/// the basis unit, Save — and a way back out that changes nothing.
///
/// It holds its own draft rather than borrowing the add form's, so opening a
/// row for editing never eats a half-typed new measure.
class _EditMeasureForm extends HookWidget {
  const _EditMeasureForm({
    required this.ingredient,
    required this.measure,
    required this.onEdit,
    required this.onDone,
    required this.onVolumeLabel,
  });

  final Ingredient ingredient;
  final Measure measure;
  final Future<AddMeasureOutcome> Function(String label, double amount) onEdit;
  final VoidCallback onDone;
  final ValueChanged<Unit> onVolumeLabel;

  @override
  Widget build(BuildContext context) {
    // A stored measure is denominated in the basis, so that is what it opens
    // in; re-weighing it in ounces is a pick away.
    final amountUnit = useState<Unit>(ingredient.macrosBasis.baseUnit);
    final label = useTextEditingController(text: measure.label);
    final amount = useTextEditingController(
      text: formatQuantityIn(measure.amount, amountUnit.value),
    );
    final error = useState<String?>(null);
    final baseLabel = ingredient.macrosBasis.baseUnit.label;

    Future<void> save() async {
      final name = label.text.trim();
      final weight = parseAmount(amount.text);
      if (name.isEmpty) {
        error.value = 'give the measure a name';
        return;
      }
      final volumeUnit = volumeUnitFromLabel(name);
      if (volumeUnit != null) {
        // The same door the add form offers (ADR-0008 §2): a volume-named
        // mapping IS the density, whichever form typed it.
        onVolumeLabel(volumeUnit);
        error.value =
            '“$name” is a unit — that mapping is the density; '
            'enter it in the density section and the ${volumeUnit.label} '
            'chip unlocks';
        return;
      }
      if (weight == null || !(weight > 0)) {
        error.value =
            'measure it: ${amountUnit.value.label} must be a positive number';
        return;
      }
      final inBasis = _inBasis(ingredient, weight, amountUnit.value);
      if (inBasis == null) {
        error.value = _noBridge(amountUnit.value, baseLabel);
        return;
      }
      error.value = null;
      final outcome = await onEdit(name, inBasis);
      // The host can be dismissed while the write is in flight.
      if (!context.mounted) return;
      switch (outcome) {
        case MeasureRefused(:final reason):
          error.value = reason;
        case MeasureNotAdded():
          return;
        case MeasureAdded():
          onDone();
      }
    }

    return MeasureForm(
      icon: FLucideIcons.pencil,
      headline: 'EDIT MEASURE',
      saveLabel: 'Save',
      slot: 'edit',
      units: basisConvertibleUnits(ingredient),
      unit: amountUnit.value,
      label: label,
      amount: amount,
      error: error.value,
      autofocus: false,
      onUnit: (u) => amountUnit.value = u,
      onSave: save,
      footer: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDone,
        child: Text(
          'leave it as it was',
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ),
    );
  }
}

/// [amount] of [unit] as the row's basis amount, or null when this row cannot
/// bridge the two — a volume weighed on a per-g row with no density.
double? _inBasis(Ingredient ingredient, double amount, Unit unit) =>
    switch (convert(
      Quantity(amount, unit),
      to: ingredient.macrosBasis.baseUnit,
      densityGPerMl: ingredient.densityGPerMl,
    )) {
      Ok(:final value) => value.amount,
      Err() => null,
    };

/// Why a pick could not be stored, in the words the density entry uses: the
/// missing number is named, and so is the way out.
String _noBridge(Unit unit, String baseLabel) =>
    'this row has no density, so ${unit.label} cannot become $baseLabel — '
    'say it in $baseLabel, or state a density first';

// --- Provenance display ------------------------------------------------------

/// The humanized provenance word (frame-b review: words carry the meaning,
/// never raw machine strings).
///
/// A curated seed number reads **estimate**, not "typical": the stored string
/// is a provenance, and "typical" beside a list whose order is what says which
/// measure is the usual one was read as a flag on the row rather than as where
/// the number came from.
String measureSourceWord(MeasureSourceKind kind) => switch (kind) {
  MeasureSourceKind.usdaPortion => 'USDA portion',
  MeasureSourceKind.borrowed => 'borrowed',
  MeasureSourceKind.typical => 'estimate',
  MeasureSourceKind.manual => 'yours',
  MeasureSourceKind.unknown => '—',
};

/// The subtle four-dot colour vocabulary (solid = USDA, ring = borrowed,
/// amber = estimate, ink = yours). Decorative beside the words — never
/// load-bearing on its own.
class SourceDot extends StatelessWidget {
  const SourceDot({required this.kind, super.key});

  final MeasureSourceKind kind;

  @override
  Widget build(BuildContext context) {
    final (fill, ring) = switch (kind) {
      MeasureSourceKind.usdaPortion => (AnsiColors.herb, AnsiColors.herb),
      MeasureSourceKind.borrowed => (null, AnsiColors.herb),
      MeasureSourceKind.typical => (AnsiColors.aging, AnsiColors.aging),
      MeasureSourceKind.manual => (AnsiColors.ink, AnsiColors.ink),
      MeasureSourceKind.unknown => (null, AnsiColors.line),
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
      ),
    );
  }
}
