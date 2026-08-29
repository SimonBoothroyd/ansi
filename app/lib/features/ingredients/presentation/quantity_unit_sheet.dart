/// The quantity + unit-chip entry surface (step 7.7, design board frame b —
/// built to Simon's simplified review reading): the everyday surface shows
/// ONLY the ingredient card (name + macro line), the quantity input, the
/// chip row (precise units · measure chips · imprecise after a divider · a
/// `+` chip), the live honest conversion line, and Done. Tapping `+` opens
/// the second state — **manage measures** — with the measure list (label ·
/// grams · humanized source) and the add-measure form (label + grams →
/// saved as `manual`). Chips ride the keyboard at the sheet's bottom: a true
/// iOS keyboard-accessory view fights Flutter's insets model, so the sheet
/// bottom-pads itself by the viewInsets instead — the stack above the
/// keyboard reads chips → Done → keyboard (Done sits between the chips and
/// the keyboard, not the frame's literal chips-touch-keypad adjacency; the
/// call the plan asked to document, wording trued up post-review).
///
/// Replaces the unit dropdown wherever a quantity + unit is edited: recipe
/// editor line items, the shopping add sheet, and the edit-top-up sheet.
///
/// **Deleting the selected measure** (manage state) reconciles the choice to
/// the ingredient's default unit with a visible note — Done must never write
/// a tombstoned `measure_id` (post-7.7 review call; the alternative,
/// keep-with-flag, is reserved for measures merely hidden by merge-on-read,
/// which stay reachable via the chip row's off-filter admission).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import 'ingredient_picker.dart' show StubBadge;
import 'macros_format.dart';

/// What the sheet resolved to.
sealed class QuantitySheetResult {
  const QuantitySheetResult();
}

/// The user confirmed a quantity + unit choice. [unitPicked] is true only
/// when a chip was explicitly tapped — callers preserving an unresolved
/// `measure_id` (the degrade-don't-destroy rule) clear it only then.
final class QuantitySaved extends QuantitySheetResult {
  const QuantitySaved({
    required this.choice,
    required this.unitPicked,
    this.quantity,
  });

  final double? quantity;
  final UnitChoice choice;
  final bool unitPicked;
}

/// The user hit the remove affordance (edit-top-up only).
final class QuantityRemoved extends QuantitySheetResult {
  const QuantityRemoved();
}

/// Opens the quantity surface for [ingredient]; resolves to a
/// [QuantitySheetResult], or null if dismissed.
Future<QuantitySheetResult?> showQuantityUnitSheet(
  BuildContext context, {
  required Ingredient ingredient,
  double? initialQuantity,
  UnitChoice? initialChoice,
  bool requireQuantity = false,
  bool pendingMeasure = false,
  String confirmLabel = 'Done',
  bool showRemove = false,
}) {
  return showFSheet<QuantitySheetResult>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (sheetContext) => QuantityUnitEditor(
      ingredient: ingredient,
      initialQuantity: initialQuantity,
      initialChoice: initialChoice,
      requireQuantity: requireQuantity,
      pendingMeasure: pendingMeasure,
      confirmLabel: confirmLabel,
      onDone: (saved) => Navigator.of(sheetContext).pop(saved),
      onRemove: showRemove
          ? () => Navigator.of(sheetContext).pop(const QuantityRemoved())
          : null,
    ),
  );
}

class QuantityUnitEditor extends HookConsumerWidget {
  const QuantityUnitEditor({
    required this.ingredient,
    required this.onDone,
    this.initialQuantity,
    this.initialChoice,
    this.requireQuantity = false,
    this.pendingMeasure = false,
    this.confirmLabel = 'Done',
    this.onRemove,
    super.key,
  });

  final Ingredient ingredient;
  final double? initialQuantity;
  final UnitChoice? initialChoice;

  /// When set, Done needs a positive quantity (shopping top-ups). The
  /// editor keeps quantities optional ("to taste").
  final bool requireQuantity;

  /// The stored selection is an unresolved measure's honest count fallback —
  /// shown with a pending note until a chip is explicitly picked.
  final bool pendingMeasure;

  final String confirmLabel;
  final ValueChanged<QuantitySaved> onDone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = useState<double?>(initialQuantity);
    final choice = useState<UnitChoice>(
      initialChoice ?? UnitOption(ingredient.defaultUnit),
    );
    final unitPicked = useState(false);
    final managing = useState(false);
    final deletedNote = useState<String?>(null);
    // The line's stored choice, admitted into the chip row even when the
    // filter wouldn't offer it (the retired dropdowns' rule) — so it stays
    // re-selectable after tapping another chip, for as long as it exists.
    final stored = useState<UnitChoice?>(initialChoice);

    final measures =
        ref.watch(ingredientMeasuresProvider(ingredient.id)).asData?.value ??
        const <Measure>[];

    // Deleting the SELECTED measure reconciles the choice (deliberate call,
    // post-7.7 review): keeping it would let Done write a tombstoned
    // measure_id, silently degrading "2 half cans" to "2 pieces" everywhere.
    // The selection resets to the ingredient's default unit with a visible
    // note (the pending-note pattern); a measure merely hidden by
    // merge-on-read is NOT deleted and stays admitted via the chip row's
    // off-filter rule instead.
    Future<void> deleteMeasure(Measure m) async {
      await ref.read(measureRepositoryProvider).softDeleteMeasure(m.id);
      // A deleted measure also stops being the admitted stored choice.
      if (stored.value == MeasureOption(m)) stored.value = null;
      if (choice.value == MeasureOption(m)) {
        choice.value = UnitOption(ingredient.defaultUnit);
        unitPicked.value = true;
        deletedNote.value =
            '“${m.label}” deleted — back to '
            '${ingredient.defaultUnit.label}';
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom:
              math.max(
                MediaQuery.viewInsetsOf(context).bottom,
                MediaQuery.paddingOf(context).bottom,
              ) +
              12,
        ),
        child: managing.value
            ? _MeasureManager(
                ingredient: ingredient,
                measures: measures,
                onBack: () => managing.value = false,
                onDelete: deleteMeasure,
                onAdded: (m) {
                  choice.value = MeasureOption(m);
                  unitPicked.value = true;
                  managing.value = false;
                },
              )
            : _QuantitySurface(
                ingredient: ingredient,
                measures: measures,
                quantity: quantity,
                choice: choice,
                unitPicked: unitPicked,
                stored: stored.value,
                deletedNote: deletedNote.value,
                pendingMeasure: pendingMeasure,
                requireQuantity: requireQuantity,
                confirmLabel: confirmLabel,
                onManage: () => managing.value = true,
                onDone: () => onDone(
                  QuantitySaved(
                    quantity: quantity.value,
                    choice: choice.value,
                    unitPicked: unitPicked.value,
                  ),
                ),
                onRemove: onRemove,
              ),
      ),
    );
  }
}

// --- State A: the everyday quantity surface ----------------------------------

class _QuantitySurface extends StatelessWidget {
  const _QuantitySurface({
    required this.ingredient,
    required this.measures,
    required this.quantity,
    required this.choice,
    required this.unitPicked,
    required this.stored,
    required this.deletedNote,
    required this.pendingMeasure,
    required this.requireQuantity,
    required this.confirmLabel,
    required this.onManage,
    required this.onDone,
    required this.onRemove,
  });

  final Ingredient ingredient;
  final List<Measure> measures;
  final ValueNotifier<double?> quantity;
  final ValueNotifier<UnitChoice> choice;
  final ValueNotifier<bool> unitPicked;

  /// The line's stored choice, admitted into the chip row even off-filter.
  final UnitChoice? stored;

  /// Set when the manage state deleted the selected measure and the choice
  /// was reconciled to the default unit — shown like the pending note.
  final String? deletedNote;
  final bool pendingMeasure;
  final bool requireQuantity;
  final String confirmLabel;
  final VoidCallback onManage;
  final VoidCallback onDone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final macros = ingredient.macros;
    final stub = ingredient.status == IngredientStatus.stub;
    final canConfirm =
        !requireQuantity || (quantity.value != null && quantity.value! > 0);
    final note = _conversionNote(quantity.value, choice.value, ingredient);
    final pendingNote = pendingMeasure && !unitPicked.value;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(FLucideIcons.x, size: 22),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(
                ingredient.canonicalName,
                style: miseSerif(size: 22),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (stub) ...[const SizedBox(width: 8), const StubBadge()],
          ],
        ),
        // Name + macro line only (frame-b review): density surfaces in the
        // conversion line below, where it is doing work.
        if (!stub && macros != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(
              TextSpan(
                text: formatMacroLine(macros),
                style: miseMono(size: 11, color: MiseColors.herbDeep),
                children: [
                  TextSpan(
                    text: ' ${macroBasisSuffix(ingredient.macrosBasis)}',
                    style: miseMono(size: 11, color: MiseColors.muted),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('QUANTITY', style: miseLabel()),
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 132,
              child: FTextField(
                autofocus: true,
                hint: 'qty',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(
                    text: formatQuantity(quantity.value),
                  ),
                  onChange: (v) => quantity.value = v.text.trim().isEmpty
                      ? null
                      : double.tryParse(v.text.trim()),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                choice.value.label,
                style: miseMono(size: 15, color: MiseColors.herbDeep),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (pendingNote)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'measure pending sync — it stays unless you pick a unit',
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
          ),
        if (deletedNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              deletedNote!,
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
          ),
        const SizedBox(height: 18),
        SizedBox(
          height: 16,
          child: note == null
              ? null
              : Text(
                  note,
                  textAlign: TextAlign.center,
                  style: miseMono(size: 11, color: MiseColors.muted),
                ),
        ),
        const SizedBox(height: 8),
        UnitChipRow(
          ingredient: ingredient,
          measures: measures,
          selected: choice.value,
          stored: stored,
          onSelect: (c) {
            choice.value = c;
            unitPicked.value = true;
          },
          onManage: onManage,
        ),
        const SizedBox(height: 14),
        FButton(onPress: canConfirm ? onDone : null, child: Text(confirmLabel)),
        if (onRemove != null) ...[
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRemove,
            child: Text(
              'Remove top-up',
              style: miseSans(size: 15, color: MiseColors.gone),
            ),
          ),
        ],
      ],
    );
  }
}

/// The honest conversion line: shown only when the unit system can actually
/// bridge the current entry to grams — a volume entry names the density it
/// used; nothing is ever fabricated (invariant 3).
String? _conversionNote(double? qty, UnitChoice choice, Ingredient ing) {
  if (qty == null || !(qty > 0)) return null;
  switch (choice) {
    case MeasureOption(:final measure):
      final grams = convertMeasure(qty, measure, to: g);
      return switch (grams) {
        Ok(:final value) => '≈ ${formatQuantity(value.amount)} g',
        Err() => null,
      };
    case UnitOption(:final unit):
      if (unit == g) return null;
      final grams = convert(
        Quantity(qty, unit),
        to: g,
        densityGPerMl: ing.densityGPerMl,
      );
      return switch (grams) {
        Ok(:final value) when unit.family == UnitFamily.volume =>
          '≈ ${formatQuantity(value.amount)} g · via density '
              '${formatDensity(ing.densityGPerMl!)} g/ml',
        Ok(:final value) => '≈ ${formatQuantity(value.amount)} g',
        Err() => null,
      };
  }
}

/// The chip row: precise units · measure chips (source dot + label) ·
/// imprecise after a divider · the `+` manage chip. Horizontally scrollable;
/// docked directly above the keyboard by the host sheet.
class UnitChipRow extends StatelessWidget {
  const UnitChipRow({
    required this.ingredient,
    required this.measures,
    required this.selected,
    required this.onSelect,
    required this.onManage,
    this.stored,
    super.key,
  });

  final Ingredient ingredient;
  final List<Measure> measures;
  final UnitChoice selected;

  /// The stored (initial) choice — always admitted into the row, so an
  /// off-filter value (a merge-hidden duplicate measure, a no-longer-allowed
  /// unit) stays re-selectable even after tapping another chip. A user can
  /// only ever select an offered chip, so the live [selected] is always
  /// either in the filter or equal to this.
  final UnitChoice? stored;
  final ValueChanged<UnitChoice> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    // The full offer comes from the domain filter, which excludes
    // volume-named measures (density owns volume conversion, frame-b review)
    // and ALWAYS admits the stored selection — a merge-hidden duplicate
    // measure or a no-longer-allowed unit stays reachable, flagged so it can
    // read as outside the honest filter (the retired dropdowns' rule).
    final offer = allowedUnitChoicesFor(
      ingredient,
      measures,
      current: stored ?? selected,
    );
    final offFilter = offer.offFilter;
    final inFilter = offFilter == null
        ? offer.choices
        : offer.choices.sublist(0, offer.choices.length - 1);
    final precise = inFilter.whereType<UnitOption>().where(
      (c) => c.unit.family != UnitFamily.imprecise,
    );
    final measureChips = inFilter.whereType<MeasureOption>();
    final imprecise = inFilter.whereType<UnitOption>().where(
      (c) => c.unit.family == UnitFamily.imprecise,
    );

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in precise)
            _Chip(
              label: c.unit.label,
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
          for (final c in measureChips)
            _Chip(
              label: c.measure.label,
              dot: SourceDot(kind: c.measure.sourceKind),
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
          if (imprecise.isNotEmpty)
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              color: MiseColors.line,
            ),
          for (final c in imprecise)
            _Chip(
              label: c.unit.label,
              imprecise: true,
              selected: selected == c,
              onTap: () => onSelect(c),
            ),
          if (offFilter != null)
            _Chip(
              label: switch (offFilter) {
                MeasureOption(:final measure) => measure.label,
                UnitOption(:final unit) => unit.label,
              },
              suffix: 'not in filter',
              dot: switch (offFilter) {
                MeasureOption(:final measure) => SourceDot(
                  kind: measure.sourceKind,
                ),
                UnitOption() => null,
              },
              selected: selected == offFilter,
              onTap: () => onSelect(offFilter),
            ),
          // A real icon, not a "＋" glyph — the bundled fonts lack U+FF0B,
          // so the string form renders as tofu (the library_view rule).
          _Chip(
            icon: const Icon(
              FLucideIcons.plus,
              size: 13,
              color: MiseColors.herb,
            ),
            accent: true,
            onTap: onManage,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.onTap,
    this.label,
    this.icon,
    this.selected = false,
    this.imprecise = false,
    this.accent = false,
    this.dot,
    this.suffix,
  }) : assert(label != null || icon != null, 'a chip needs a label or icon');

  final String? label;
  final Widget? icon;
  final bool selected;
  final bool imprecise;
  final bool accent;
  final Widget? dot;

  /// A subtle annotation after the label ("not in filter") — the admitted
  /// off-filter selection reads as such without being hidden.
  final String? suffix;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? MiseColors.surface
        : accent
        ? MiseColors.herb
        : imprecise
        ? MiseColors.muted
        : MiseColors.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? MiseColors.herb : MiseColors.surface,
          border: Border.all(
            color: selected || accent ? MiseColors.herb : MiseColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[dot!, const SizedBox(width: 5)],
            if (icon != null) icon!,
            if (label != null)
              Text(label!, style: miseMono(size: 11.5, color: fg)),
            if (suffix != null) ...[
              const SizedBox(width: 5),
              Text(
                suffix!,
                style: miseMono(
                  size: 9,
                  color: selected ? MiseColors.surface : MiseColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- State B: manage measures ------------------------------------------------

class _MeasureManager extends HookConsumerWidget {
  const _MeasureManager({
    required this.ingredient,
    required this.measures,
    required this.onBack,
    required this.onDelete,
    required this.onAdded,
  });

  final Ingredient ingredient;
  final List<Measure> measures;
  final VoidCallback onBack;

  /// Deletion runs through the editor so it can reconcile the selection —
  /// see [QuantityUnitEditor].
  final Future<void> Function(Measure) onDelete;
  final ValueChanged<Measure> onAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = useState('');
    final grams = useState<double?>(null);
    final error = useState<String?>(null);

    final listed = measures.where((m) => !isVolumeUnitLabel(m.label)).toList();

    Future<void> save() async {
      final name = label.value.trim();
      final weight = grams.value;
      if (name.isEmpty) {
        error.value = 'give the measure a name';
        return;
      }
      if (isVolumeUnitLabel(name)) {
        // Density owns volume conversion — a "cup" measure would shadow it.
        error.value = '“$name” is a unit — name the real-world thing instead';
        return;
      }
      if (weight == null || !(weight > 0)) {
        error.value = 'weigh it: grams must be a positive number';
        return;
      }
      error.value = null;
      final added = await ref
          .read(measureRepositoryProvider)
          .addMeasure(ingredientId: ingredient.id, label: name, grams: weight);
      // The sheet can be dismissed while the write is in flight — touching
      // the parent's state then would throw (every sibling path guards).
      if (!context.mounted) return;
      onAdded(added);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack,
              child: const Icon(FLucideIcons.chevronLeft, size: 22),
            ),
            Expanded(
              child: Text(
                'Measures',
                textAlign: TextAlign.center,
                style: miseSerif(size: 20),
              ),
            ),
            const SizedBox(width: 22),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          ingredient.canonicalName,
          textAlign: TextAlign.center,
          style: miseMono(size: 11, color: MiseColors.muted),
        ),
        const SizedBox(height: 14),
        if (listed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No measures yet — name one below.',
              style: miseMono(size: 12, color: MiseColors.muted),
            ),
          )
        else
          for (final m in listed) _MeasureRow(measure: m, onDelete: onDelete),
        const SizedBox(height: 12),
        _AddMeasureForm(
          label: label,
          grams: grams,
          error: error.value,
          onSave: save,
        ),
      ],
    );
  }
}

class _MeasureRow extends StatelessWidget {
  const _MeasureRow({required this.measure, required this.onDelete});

  final Measure measure;
  final Future<void> Function(Measure) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MiseColors.line)),
      ),
      child: Row(
        children: [
          SourceDot(kind: measure.sourceKind),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              measure.label,
              style: miseSans(size: 14, weight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatQuantity(measure.grams)} g',
            style: miseMono(size: 11, color: MiseColors.muted),
          ),
          const Spacer(),
          Text(
            measureSourceWord(measure.sourceKind),
            style: miseMono(size: 9, color: MiseColors.muted),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDelete(measure),
            child: const Icon(
              FLucideIcons.trash2,
              size: 15,
              color: MiseColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMeasureForm extends StatelessWidget {
  const _AddMeasureForm({
    required this.label,
    required this.grams,
    required this.error,
    required this.onSave,
  });

  final ValueNotifier<String> label;
  final ValueNotifier<double?> grams;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon + text, never the raw "＋" glyph (missing from the bundled
        // fonts — renders as tofu).
        Row(
          children: [
            const Icon(FLucideIcons.plus, size: 12, color: MiseColors.herb),
            const SizedBox(width: 5),
            Text('ADD MEASURE', style: miseLabel(color: MiseColors.herb)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FTextField(
                autofocus: true,
                hint: 'label — “half can”',
                control: FTextFieldControl.managed(
                  onChange: (v) => label.value = v.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: FTextField(
                hint: 'grams',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  onChange: (v) => grams.value = double.tryParse(v.text.trim()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FButton(
              size: FButtonSizeVariant.sm,
              onPress: onSave,
              child: const Text('Save'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (error != null)
          Text(error!, style: miseMono(size: 10, color: MiseColors.gone))
        else
          Row(
            children: [
              const SourceDot(kind: MeasureSourceKind.manual),
              const SizedBox(width: 5),
              Text(
                'saved as yours — synced & editable',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
            ],
          ),
      ],
    );
  }
}

// --- Provenance display ------------------------------------------------------

/// The humanized provenance word (frame-b review: words carry the meaning,
/// never raw machine strings).
String measureSourceWord(MeasureSourceKind kind) => switch (kind) {
  MeasureSourceKind.usdaPortion => 'USDA portion',
  MeasureSourceKind.borrowed => 'borrowed',
  MeasureSourceKind.typical => 'typical',
  MeasureSourceKind.manual => 'yours',
  MeasureSourceKind.unknown => '—',
};

/// The subtle four-dot colour vocabulary (solid = USDA, ring = borrowed,
/// amber = typical, ink = yours). Decorative beside the words — never
/// load-bearing on its own.
class SourceDot extends StatelessWidget {
  const SourceDot({required this.kind, super.key});

  final MeasureSourceKind kind;

  @override
  Widget build(BuildContext context) {
    final (fill, ring) = switch (kind) {
      MeasureSourceKind.usdaPortion => (MiseColors.herb, MiseColors.herb),
      MeasureSourceKind.borrowed => (null, MiseColors.herb),
      MeasureSourceKind.typical => (MiseColors.aging, MiseColors.aging),
      MeasureSourceKind.manual => (MiseColors.ink, MiseColors.ink),
      MeasureSourceKind.unknown => (null, MiseColors.line),
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
