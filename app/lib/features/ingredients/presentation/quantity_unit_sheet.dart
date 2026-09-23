/// The one surface for editing a quantity and unit: recipe lines, the shopping
/// add sheet, the edit-top-up sheet.
///
/// It shows the ingredient card, the quantity input, the chip row, the live
/// conversion line and Done; the `+` chip opens the manage-measures state. A
/// caller that names no choice opens on the first chip offered
/// (`firstOfferedChoice`, ADR-0016). Deleting the selected measure resets the
/// choice to the default unit, so Done never writes a tombstoned `measure_id`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../../../shared/format.dart';
import '../../../shared/write.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import '../domain/serving_measure.dart';
import 'density_entry.dart';
import 'ingredient_picker.dart' show StubBadge;
import 'macros_format.dart';
import 'measure_delete.dart';
import 'measures_editor.dart';
import 'piece_weight_entry.dart';
import 'unit_chips.dart';

/// What the sheet resolved to.
sealed class QuantitySheetResult {
  const QuantitySheetResult();
}

/// The user confirmed a quantity and unit. [unitPicked] is true only when a
/// chip was tapped; callers preserving an unresolved `measure_id` clear it only
/// then. [optional] is the Optional switch's final state, false when the host
/// did not offer it.
final class QuantitySaved extends QuantitySheetResult {
  const QuantitySaved({
    required this.choice,
    required this.unitPicked,
    this.quantity,
    this.optional = false,
  });

  final double? quantity;
  final UnitChoice choice;
  final bool unitPicked;
  final bool optional;
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
  bool? initialOptional,
  String confirmLabel = 'Done',
  bool showRemove = false,
}) {
  return showAnsiSheet<QuantitySheetResult>(
    context: context,
    builder: (sheetContext) => QuantityUnitEditor(
      ingredient: ingredient,
      initialQuantity: initialQuantity,
      initialChoice: initialChoice,
      requireQuantity: requireQuantity,
      pendingMeasure: pendingMeasure,
      initialOptional: initialOptional,
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
    this.initialOptional,
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

  /// The line's stored `optional` flag, for hosts with nowhere else to set it
  /// (the import review's and the week's amount doors). Null hides the switch.
  final bool? initialOptional;

  final String confirmLabel;
  final ValueChanged<QuantitySaved> onDone;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = useState<double?>(initialQuantity);
    final choice = useState<UnitChoice>(
      initialChoice ?? firstOfferedChoice(ingredient, const []),
    );
    final unitPicked = useState(false);
    final optional = useState(initialOptional ?? false);
    final managing = useState(false);
    final deletedNote = useState<String?>(null);
    // The line's stored choice, admitted into the chip row even when the filter
    // would not offer it, so it stays re-selectable.
    final stored = useState<UnitChoice?>(initialChoice);
    // The vocab row can change while the sheet is open (a density entry unlocks
    // the other unit family), so the surfaces read this copy.
    final live = useState(ingredient);

    final measuresAsync = ref.watch(ingredientMeasuresProvider(ingredient.id));
    final measures = measuresAsync.asData?.value ?? const <Measure>[];

    // The seed moves once, when the measures land, and only while nothing has
    // been picked. An explicit [initialChoice] is never moved.
    useEffect(() {
      if (initialChoice != null ||
          unitPicked.value ||
          !measuresAsync.hasValue ||
          choice.value != firstOfferedChoice(live.value, const [])) {
        return null;
      }
      choice.value = firstOfferedChoice(live.value, measures);
      return null;
    }, [measuresAsync.hasValue]);

    // Deleting the selected measure resets the choice to the default unit with
    // a visible note; keeping it would let Done write a tombstoned measure_id.
    // A measure merely hidden by merge-on-read is not deleted and stays
    // admitted.
    Future<void> deleteMeasure(Measure m) async {
      // A measure a recipe still uses cannot go: the lines that name it would
      // quietly drop out of every total.
      if (!await mayDeleteMeasure(context, ref, m)) return;
      if (!context.mounted) return;
      final deleted = await ref.writeOk(
        context,
        'delete “${m.label}”',
        () => ref.read(measureRepositoryProvider).softDeleteMeasure(m.id),
      );
      // The sheet can be dismissed while the write is in flight — touching
      // hook state then would throw (same guard as _MeasureManager.save).
      if (!deleted || !context.mounted) return;
      // A deleted measure also stops being the admitted stored choice.
      if (stored.value == MeasureOption(m)) stored.value = null;
      if (choice.value == MeasureOption(m)) {
        choice.value = UnitOption(live.value.defaultUnit);
        unitPicked.value = true;
        deletedNote.value =
            '“${m.label}” deleted — back to '
            '${live.value.defaultUnit.label}';
      }
    }

    // An errored measures stream read as "no measures" would silently narrow
    // the units on offer (ADR-0008), so the error is shown instead.
    if (measuresAsync.hasError) {
      return AnsiSheetShell(
        dismiss: AnsiSheetDismiss.none,
        children: [
          AnsiErrorState(
            what: 'this ingredient’s measures',
            error: measuresAsync.error!,
            stackTrace: measuresAsync.stackTrace,
            onRetry: () =>
                ref.invalidate(ingredientMeasuresProvider(ingredient.id)),
          ),
        ],
      );
    }

    return AnsiSheetShell(
      title: managing.value ? 'Measures' : null,
      subtitle: managing.value ? live.value.canonicalName : null,
      dismiss: managing.value ? AnsiSheetDismiss.back : AnsiSheetDismiss.x,
      onDismiss: managing.value ? () => managing.value = false : null,
      children: [
        if (managing.value)
          _MeasureManager(
            ingredient: live.value,
            measures: measures,
            onDelete: deleteMeasure,
            onAdded: (m) {
              choice.value = MeasureOption(m);
              unitPicked.value = true;
              managing.value = false;
            },
            onIngredientChanged: (i) => live.value = i,
          )
        else
          _QuantitySurface(
            ingredient: live.value,
            measures: measures,
            quantity: quantity,
            choice: choice,
            unitPicked: unitPicked,
            stored: stored.value,
            deletedNote: deletedNote.value,
            pendingMeasure: pendingMeasure,
            requireQuantity: requireQuantity,
            optional: initialOptional == null ? null : optional,
            confirmLabel: confirmLabel,
            onManage: () => managing.value = true,
            onDone: () => onDone(
              QuantitySaved(
                quantity: quantity.value,
                choice: choice.value,
                unitPicked: unitPicked.value,
                optional: optional.value,
              ),
            ),
            onRemove: onRemove,
          ),
      ],
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
    required this.optional,
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

  /// The Optional switch's state, or null when this host has no such row
  /// (see [QuantityUnitEditor.initialOptional]).
  final ValueNotifier<bool>? optional;
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
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(
                ingredient.canonicalName,
                style: ansiSerif(size: AnsiType.heading),
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
                style: ansiMono(size: 11, color: AnsiColors.herbDeep),
                children: [
                  TextSpan(
                    text: ' ${macroBasisSuffix(ingredient.macrosBasis)}',
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
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
                    text: _amountIn(quantity.value, choice.value),
                  ),
                  onChange: (v) => quantity.value = parseAmount(v.text),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                choice.value.label,
                style: ansiMono(size: 15, color: AnsiColors.herbDeep),
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
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        if (deletedNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              deletedNote!,
              style: ansiMono(size: 10, color: AnsiColors.muted),
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
                  style: ansiMono(size: 11, color: AnsiColors.muted),
                ),
        ),
        const SizedBox(height: 8),
        UnitChipRow(
          // The offer comes from the domain filter, already in ADR-0008 chip
          // order. It excludes volume-named measures and always admits the
          // stored selection.
          offer: allowedUnitChoicesFor(
            ingredient,
            measures,
            current: stored ?? choice.value,
          ),
          selected: choice.value,
          pieceLabel: pieceChipLabel(ingredient),
          onSelect: (c) {
            choice.value = c;
            unitPicked.value = true;
          },
          onManage: onManage,
        ),
        // The Optional row sits between the chips and Done. Its caption names
        // both consequences, since the effect is on two other screens.
        if (optional != null) ...[
          const SizedBox(height: 14),
          FSwitch(
            label: Text('Optional', style: ansiSans(size: 15)),
            value: optional!.value,
            onChange: (on) => optional!.value = on,
          ),
          const SizedBox(height: 4),
          Text(
            'left out of macros and the shop list, and named where it left',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
        const SizedBox(height: 14),
        FButton(onPress: canConfirm ? onDone : null, child: Text(confirmLabel)),
        if (onRemove != null) ...[
          const SizedBox(height: 8),
          FButton(
            variant: FButtonVariant.ghost,
            onPress: onRemove,
            child: Text(
              'Remove top-up',
              style: ansiSans(size: 15, color: AnsiColors.gone),
            ),
          ),
        ],
      ],
    );
  }
}

/// [quantity] as the picked choice says it: under the unit's own rule where a
/// unit is picked, and as the kitchen count a measure is counted in otherwise.
String _amountIn(double? quantity, UnitChoice choice) => switch (choice) {
  UnitOption(:final unit) => formatQuantityIn(quantity, unit),
  MeasureOption() => formatQuantity(quantity),
  RecipeMeasureOption(:final measure) => notAWordForAnIngredient(measure),
};

/// The conversion line, shown only when the entry can be bridged to the
/// ingredient's basis unit (ADR-0008). A cross-family entry names the density
/// it used.
String? _conversionNote(double? qty, UnitChoice choice, Ingredient ing) {
  if (qty == null || !(qty > 0)) return null;
  final base = ing.macrosBasis.baseUnit;
  switch (choice) {
    case RecipeMeasureOption(:final measure):
      notAWordForAnIngredient(measure);
    case MeasureOption(:final measure):
      final inBase = convertMeasure(
        qty,
        measure,
        to: base,
        densityGPerMl: ing.densityGPerMl,
      );
      return switch (inBase) {
        Ok(:final value) =>
          '≈ ${formatQuantityIn(value.amount, base)} ${base.label}',
        Err() => null,
      };
    case UnitOption(:final unit):
      if (unit == base) return null;
      // A weighed `piece` converts like a measure (ADR-0015), and the line
      // shows the multiplication itself: "2 × 350 g = 700 g".
      if (unit.family == UnitFamily.count && pieceAsMeasure(ing) != null) {
        final piece = pieceAsMeasure(ing)!;
        final inBase = convertMeasure(
          qty,
          piece,
          to: base,
          densityGPerMl: ing.densityGPerMl,
        );
        return switch (inBase) {
          Ok(:final value) =>
            '${formatQuantity(qty)} × '
                '${formatQuantityIn(piece.amount, base)} ${base.label} = '
                '${formatQuantityIn(value.amount, base)} ${base.label}',
          Err() => null,
        };
      }
      final inBase = convert(
        Quantity(qty, unit),
        to: base,
        densityGPerMl: ing.densityGPerMl,
      );
      return switch (inBase) {
        Ok(:final value) when unit.family != base.family =>
          '≈ ${formatQuantityIn(value.amount, base)} ${base.label} · via '
              'density ${formatDensity(ing.densityGPerMl!)} g/ml',
        Ok(:final value) =>
          '≈ ${formatQuantityIn(value.amount, base)} ${base.label}',
        Err() => null,
      };
  }
}

// --- State B: manage measures ------------------------------------------------

class _MeasureManager extends HookConsumerWidget {
  const _MeasureManager({
    required this.ingredient,
    required this.measures,
    required this.onDelete,
    required this.onAdded,
    required this.onIngredientChanged,
  });

  final Ingredient ingredient;
  final List<Measure> measures;

  /// Deletion runs through the editor so it can reconcile the selection —
  /// see [QuantityUnitEditor].
  final Future<void> Function(Measure) onDelete;
  final ValueChanged<Measure> onAdded;

  /// A density write updates the vocab row — the editor swaps its live copy
  /// so the chip row unlocks the other family without reopening.
  final ValueChanged<Ingredient> onIngredientChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Set when the add form refused a volume-named label ("cup") and handed
    // back the resolved spoon — the density entry below pre-picks it.
    final redirected = useState<Unit?>(null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        MeasuresEditor(
          ingredient: ingredient,
          measures: measures,
          onDelete: onDelete,
          // This host has no Save: it commits on tap.
          onAdd: (label, amount) async {
            final outcome = await ref.write(
              context,
              'add that measure',
              () async {
                try {
                  return MeasureAdded(
                    await ref
                        .read(measureRepositoryProvider)
                        .addMeasure(
                          ingredientId: ingredient.id,
                          label: label,
                          amount: amount,
                        ),
                  );
                  // The repository's validation contract IS ArgumentError
                  // (documented on addMeasure), so catching it is the point.
                  // ignore: avoid_catching_errors
                } on ArgumentError catch (e) {
                  return MeasureRefused('${e.message}');
                }
              },
            );
            return outcome ?? const MeasureNotAdded();
          },
          // An edit keeps the measure's id, so lines pointing at it follow the
          // fix.
          onEdit: (m, label, amount) async {
            final outcome = await ref.write(
              context,
              'save that measure',
              () async {
                final repo = ref.read(measureRepositoryProvider);
                try {
                  if (label != m.label) await repo.renameMeasure(m.id, label);
                  if (amount != m.amount) {
                    await repo.setMeasureAmount(m.id, amount);
                  }
                  // The repository's validation contract is ArgumentError (see
                  // renameMeasure).
                  // ignore: avoid_catching_errors
                } on ArgumentError catch (e) {
                  return MeasureRefused('${e.message}');
                }
                return MeasureAdded(
                  Measure(
                    id: m.id,
                    label: label,
                    amount: amount,
                    basis: m.basis,
                    sortOrder: m.sortOrder,
                    source: m.source,
                  ),
                );
              },
            );
            return outcome ?? const MeasureNotAdded();
          },
          // The first measure is the ingredient's typical one. This host has no
          // Save, so the drag writes at once.
          onReorder: (ids) async {
            await ref.write(
              context,
              'reorder those measures',
              () => ref
                  .read(measureRepositoryProvider)
                  .reorderMeasures(ingredient.id, ids),
            );
          },
          onAdded: onAdded,
          onVolumeLabel: (u) => redirected.value = u,
          autofocus: true,
        ),
        // The piece weight (ADR-0015), on a count-default row only. This host
        // has no Save, so it writes on tap and swaps its live row.
        if (ingredient.defaultUnit.family == UnitFamily.count)
          PieceWeightEntry(
            ingredient: ingredient,
            onSave: (amount) async {
              final updated = await ref.write(
                context,
                'save that piece weight',
                () => ref
                    .read(ingredientRepositoryProvider)
                    .setPieceWeight(ingredient.id, amount),
              );
              if (updated == null) return false;
              onIngredientChanged(updated);
              return true;
            },
            onRemove: () async {
              final updated = await ref.write(
                context,
                'remove that piece weight',
                () => ref
                    .read(ingredientRepositoryProvider)
                    .clearPieceWeight(ingredient.id),
              );
              if (updated == null) return false;
              onIngredientChanged(updated);
              return true;
            },
          ),
        // No spacer: the density entry carries its own leading space, the same
        // one the flesh-out form's micro-labels use.
        DensityEntry(
          ingredient: ingredient,
          // The row's own serving, so the sentence reopens in the unit the
          // fact sheet states this density in.
          serving: servingMeasureOf(measures),
          redirectedSpoon: redirected.value,
          // This host has no Save of its own, so it commits on tap.
          onSave: (said) async {
            final gPerMl = said.gPerMl;
            if (gPerMl == null) return false;
            final updated = await ref.write(
              context,
              'save that density',
              () => ref
                  .read(ingredientRepositoryProvider)
                  .setDensity(ingredient.id, gPerMl, said: said),
            );
            if (updated == null) return false;
            redirected.value = null;
            onIngredientChanged(updated);
            return true;
          },
          onRemove: () async {
            final updated = await ref.write(
              context,
              'remove that density',
              () => ref
                  .read(ingredientRepositoryProvider)
                  .clearDensity(ingredient.id),
            );
            if (updated == null) return false;
            redirected.value = null;
            onIngredientChanged(updated);
            return true;
          },
        ),
      ],
    );
  }
}
