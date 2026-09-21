/// Editing one review line's amount: what the card prints in its amount slot,
/// and the two sheets that change it. An ingredient line opens the shared
/// quantity sheet; a component line opens the component sheet. Both write only
/// the picked quantity and unit back onto the line's resolution.
library;

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/component_quantity_sheet.dart';
import '../../recipes/presentation/line_card.dart';
import '../domain/amount_text.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/reconciliation_payload.dart';
import 'import_view_models.dart';

/// The amount label. With a picked number: the quantity and unit (a count shows
/// just the number). Without one: the printed amount while it still reads as an
/// amount ("2–3 cloves"), else the imprecise or measure unit word, else empty.
///
/// The slot never carries prose. A raw amount with no number shows only the
/// qualifier the source named ("to serve"); the prose goes to the notes slot
/// ([noteFromRawAmount]).
String amountLabel(LineResolution r, RawLineItem raw) {
  final mapped = r.unit == null ? null : unitById(r.unit!);
  if (r.quantity != null) {
    final unitLabel = mapped?.label ?? r.unit ?? '';
    // An unmapped unit is a raw source word, and a word the catalog does not
    // know cannot say how its number is read: it keeps the kitchen rule.
    final qty = mapped == null
        ? formatQuantity(r.quantity)
        : formatQuantityIn(r.quantity, mapped);
    if (mapped != null && mapped.family == UnitFamily.count) return qty;
    return '$qty $unitLabel'.trim();
  }
  // No number: a catalog unit names itself ("pinch", "to taste"), never the raw
  // phrase.
  if (mapped != null) return mapped.label;
  // Unmapped/absent unit: the printed original still wins WHILE IT IS ONE — an
  // unpicked range ("2–3 cloves"), a "2 sprigs" the vocab couldn't map.
  final printed = raw.rawAmount.trim();
  if (printed.isNotEmpty && !isProseAmount(printed)) return printed;
  return amountQualifier(printed) ??
      (r.unit?.isNotEmpty ?? false ? r.unit! : '');
}

/// What the card prints in its amount slot: [amountLabel], except on a
/// [LineIssue.unitNotAllowed] line, where it prints nothing and the caller
/// renders its empty state.
///
/// A slot reading "1 whole" looks filled, which hides that the amount is still
/// owed. The parsed number stays on the resolution, so the amount sheet opens
/// on "1".
String amountSlotLabel(
  LineResolution r,
  RawLineItem raw,
  List<LineIssue> issues,
) => issues.contains(LineIssue.unitNotAllowed) ? '' : amountLabel(r, raw);

/// Whether the line's unit is an imprecise word; the card italicises those.
bool isImpreciseAmount(LineResolution r) {
  if (r.unit == null) return false;
  return unitById(r.unit!)?.family == UnitFamily.imprecise;
}

/// Opens the quantity sheet for the flattened line at [lineIndex] and writes
/// the picked quantity and unit back onto its resolution. Only called on a
/// matched line; the chips come from [amountSheetIngredient] (ADR-0008).
///
/// The ingredient is loaded by id, and a load failure degrades to a stub
/// stand-in, so the sheet always opens. A picked measure rides its label
/// through [sheetChoiceUnit], and a range opens on its low endpoint. When the
/// line's unit is one the ingredient cannot carry and [preselectedMeasure]
/// names a measure, the sheet opens on it and Done adopts it even with no chip
/// tapped.
Future<void> editLineAmount(
  BuildContext context,
  WidgetRef ref,
  int lineIndex,
) async {
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return;
  // Captured BEFORE the sheet: the app-lifetime container is what the write
  // after the await goes through (the chip's own element may be gone by then).
  final container = ProviderScope.containerOf(context, listen: false);
  final raw = state.lineAt(lineIndex).raw;
  final resolution = state.resolutions.firstWhere(
    (r) => r.lineIndex == lineIndex,
  );
  // A linked line is quantified against a recipe, not an ingredient: the
  // component sheet, whose chips are `batch` ∪ the target's yield families.
  if (resolution.isComponent) {
    await editComponentAmount(context, ref, lineIndex);
    return;
  }
  if (resolution.chosenIngredientId == null) {
    return; // units need an ingredient to derive an allowed set
  }

  Ingredient? loaded;
  var measures = const <Measure>[];
  final chosenId = resolution.chosenIngredientId;
  if (chosenId != null) {
    try {
      loaded = await ref.read(ingredientRepositoryProvider).byId(chosenId);
    } on Object {
      loaded = null; // never leave the tap inert — fall back to a stand-in
    }
    try {
      // Straight off the repository, not the measures stream provider: read
      // alone, that mints an autoDispose element nothing listens to, and the
      // watch does not emit before it is collected.
      measures =
          (await ref.read(measureRepositoryProvider).measuresByIngredients({
            chosenId,
          }))[chosenId] ??
          const [];
    } on Object {
      measures = const []; // no measures reachable → simply no pre-selection
    }
  }
  if (!context.mounted) return;

  final unit = resolution.unit == null ? null : unitById(resolution.unit!);
  final base =
      loaded ??
      Ingredient(
        id: resolution.chosenIngredientId ?? 'import-$lineIndex',
        canonicalName: resolution.chosenName ?? resolution.ingredientText,
        defaultUnit: unit ?? (resolution.quantity == null ? toTaste : g),
        status: IngredientStatus.stub,
      );
  // A range with no picked number opens on its printed low endpoint (a real
  // printed value, not an invented one) so confirming the sheet resolves it.
  final initialQuantity =
      resolution.quantity ??
      (resolution.isRange ? (raw.qtyLow ?? raw.qtyHigh) : null);
  // An inadmissible unit on an ingredient that names exactly one measure opens
  // on it — "2 clove" for a garlic line that arrived as "2 ml".
  final preselect = loaded == null
      ? null
      : preselectedMeasure(loaded, measures, unit: resolution.unit);
  // A line already on one of the row's measures opens on that measure.
  final named = measureNamed(resolution.unit, measures);
  final result = await showQuantityUnitSheet(
    context,
    ingredient: amountSheetIngredient(base, parsedUnit: resolution.unit),
    initialQuantity: initialQuantity,
    initialChoice: preselect != null
        ? MeasureOption(preselect)
        : unit != null
        ? UnitOption(unit)
        : named != null
        ? MeasureOption(named)
        : null,
    initialOptional: resolution.optional,
  );
  if (result is! QuantitySaved) return;
  // The notifier is read after the awaited sheet, through the container
  // captured before it; never through `ref` (the element can be unmounted, and
  // Riverpod 3 throws) or a pre-captured instance (it can be disposed).
  container.read(importControllerProvider.notifier).updateResolution(
    lineIndex,
    (r) {
      // A pre-selected measure counts as picked on confirm, or Done would keep
      // the flagged unit.
      final picked = sheetChoiceUnit(
        choice: result.choice,
        unitPicked: result.unitPicked || preselect != null,
        currentUnit: r.unit,
      );
      return r
          .setAmount(quantity: result.quantity, unit: picked)
          .setOptional(optional: result.optional);
    },
  );
}

/// Opens the component quantity sheet for a linked line and writes the picked
/// amount back onto its resolution.
///
/// The target's yields are read straight from the keepAlive repository, not a
/// stream provider (an autoDispose element with nothing listening completes
/// empty). A read that cannot answer degrades to `batch` only, as the sheet's
/// no-yield state does.
Future<void> editComponentAmount(
  BuildContext context,
  WidgetRef ref,
  int lineIndex,
) async {
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final resolution = state.resolutions.firstWhere(
    (r) => r.lineIndex == lineIndex,
  );
  final recipeId = resolution.linkedRecipeId;
  if (recipeId == null) return;
  final title = resolution.linkedRecipeTitle ?? resolution.ingredientText;

  var target = SubRecipeTarget(id: recipeId, title: title);
  try {
    final recipes = await ref
        .read(recipeRepositoryProvider)
        .watchRecipes()
        .first
        .timeout(const Duration(seconds: 5));
    for (final r in recipes) {
      if (r.id != recipeId) continue;
      // The summary's conversion, so the dock opens on the target's stated
      // yields. Its measures are dropped: a review line stores a unit id and
      // has no column for a recipe's own word (ADR-0018).
      target = r.asSubRecipeTarget.copyWith(measures: const []);
      break;
    }
  } on Object {
    // Never leave the tap inert — the sheet opens on the batch denomination,
    // which needs no yield at all.
  }
  if (!context.mounted) return;

  final stored = resolution.unit == null ? null : unitById(resolution.unit!);
  final result = await showComponentQuantitySheet(
    context,
    target: target,
    initialQuantity: resolution.quantity,
    // The line's printed unit is admissible whatever the sheet would otherwise
    // offer. No ＋: a word coined here could not be stored on a review line.
    initialUnit: stored,
    initialOptional: resolution.optional,
  );
  if (result == null) return;
  // Read after the awaited sheet through the container (see `editLineAmount`).
  // The target carries no measures, so the sheet always hands back a unit;
  // `batches` only keeps the expression total.
  final picked = result.unit ?? batches;
  container
      .read(importControllerProvider.notifier)
      .updateResolution(
        lineIndex,
        (r) => r
            .setAmount(quantity: result.quantity, unit: picked.id)
            .setOptional(optional: result.optional),
      );
}

/// The tap-to-edit amount chip (decision 6). Shows the resolved amount, else
/// the printed raw amount, else a prompt; tapping opens the amount sheet.
class AmountEditor extends ConsumerWidget {
  const AmountEditor({
    required this.lineIndex,
    this.issues = const [],
    super.key,
  });

  final int lineIndex;

  /// The line's outstanding issues, so the chip prints what
  /// [amountSlotLabel] says and not a unit the ingredient refuses.
  final List<LineIssue> issues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider);
    if (state is! ImportReconciling) return const SizedBox.shrink();
    final raw = state.lineAt(lineIndex).raw;
    final resolution = state.resolutions.firstWhere(
      (r) => r.lineIndex == lineIndex,
    );

    return LineCardAmountChip(
      label: amountSlotLabel(resolution, raw, issues),
      onTap: () => editLineAmount(context, ref, lineIndex),
    );
  }
}
