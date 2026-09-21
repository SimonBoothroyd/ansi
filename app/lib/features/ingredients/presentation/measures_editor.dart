/// The manage-measures editor, shared by the quantity sheet and the ingredient
/// form.
///
/// It owns the ingredient's live measure rows (provenance, order, deletion) and
/// the add/edit form: a label and an amount in a chosen unit, converted into
/// the row's basis on save (ADR-0008). A volume-named label ("cup") is a
/// density, not a measure, so the form refuses it and hands the unit to
/// [MeasuresEditor.onVolumeLabel]. Whether a row may say `piece` is not decided
/// here (ADR-0015).
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

/// What the host did when the editor asked it to add a measure. A value rather
/// than an exception: a refusal is shown inline under the field, while a failed
/// write has already been reported by the host.
sealed class AddMeasureOutcome {
  const AddMeasureOutcome();
}

/// It landed, or is in the host's draft and will. [measure] has an id and can
/// be handed to `onAdded`.
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

  /// A measure was authored. The host decides when it lands (ADR-0011): the
  /// quantity sheet writes at once, the form holds it in its draft. This widget
  /// only validates the label and the amount, including the volume-label
  /// redirect.
  final Future<AddMeasureOutcome> Function(String label, double amount) onAdd;

  /// An existing measure was re-stated. The row keeps its id, so lines pointing
  /// at it follow the correction. Same outcomes as [onAdd].
  final Future<AddMeasureOutcome> Function(Measure, String label, double amount)
  onEdit;

  /// The list, in the order the drag left it. The first measure is the
  /// ingredient's typical one: it fronts the picker's chips and the shop's
  /// whole-unit hint rounds to it.
  final Future<void> Function(List<String> ids) onReorder;

  final ValueChanged<Measure> onAdded;

  /// A volume-named label was refused and resolved to that catalog unit —
  /// the host points its density entry at it (the "volume-label redirect").
  final ValueChanged<Unit> onVolumeLabel;

  /// What the add form's button says: `Save` where the host commits on tap,
  /// `Add` where the tap only fills a draft.
  final String addLabel;

  /// True on the quantity sheet, which opens here with the keyboard up. The
  /// form must not steal focus from a scrolling screen.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    // The add form's draft is held as controllers: a Forui managed control
    // seeds itself once, and this form must clear its slots after each add.
    final label = useTextEditingController();
    final amount = useTextEditingController();
    final labelFocus = useFocusNode();
    // A fresh form opens on the row's basis unit. A landed measure does not
    // reset the unit; see `save`.
    final openingUnit = ingredient.macrosBasis.baseUnit;
    final amountUnit = useState<Unit>(openingUnit);
    final error = useState<String?>(null);
    // Which row is open for editing, by id; one at a time.
    final editing = useState<String?>(null);

    final baseLabel = ingredient.macrosBasis.baseUnit.label;
    // The row's serving is stated in the nutrition section, and a volume-named
    // label is a density. Neither is listed here.
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
        // Density owns volume conversion (ADR-0008 §2), so offer that door
        // instead of only refusing.
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
          // The label and the figure clear for the next measure. The unit
          // stays: several measures usually come off one scale.
          label.clear();
          amount.clear();
          // Focus returns to the first slot, but only while this form is still
          // on screen: the quantity sheet's host closes it on an add.
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
        // Drop focus first: a focused field leaving the tree keeps a frame
        // callback on a dead render object.
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
          // A row open for editing cannot be dragged. The plain column also
          // keeps the form out of a scrollable of its own, so a field never
          // scrolls itself into view in a subtree Save is about to remove.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, m) in listed.indexed)
                if (editing.value == m.id) editForm(m) else row(m, i),
            ],
          )
        else
          // Draggable because the first row is the typical measure. Only the
          // grip starts a move, so a long-press never turns a scroll into a
          // reorder. It shrink-wraps inside a page that already scrolls.
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

/// One measure as a line in the editor. Tapping it opens the edit form, which
/// keeps the row's id; delete-and-re-add would orphan lines pointing at it.
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

/// The add form's shape, seeded from an existing row. It holds its own draft,
/// so editing a row never eats a half-typed new measure.
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

/// The provenance word shown for a measure. A curated seed number reads
/// "estimate".
String measureSourceWord(MeasureSourceKind kind) => switch (kind) {
  MeasureSourceKind.usdaPortion => 'USDA portion',
  MeasureSourceKind.borrowed => 'borrowed',
  MeasureSourceKind.typical => 'estimate',
  MeasureSourceKind.manual => 'yours',
  MeasureSourceKind.unknown => '—',
};

/// The four-dot colour vocabulary (solid = USDA, ring = borrowed, amber =
/// estimate, ink = yours). Decorative beside the words.
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
