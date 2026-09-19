/// Editing one review line's amount: what the card prints in its amount slot,
/// and the two doors that change it.
///
/// An ingredient line opens the shared quantity + unit-chip sheet on the
/// matched ingredient's allowed set; a component line opens the component
/// sheet's batch math instead. Both write the picked quantity + unit back onto
/// the line's resolution and nothing else.
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

/// The amount label. With a picked number: the quantity + unit (count shows
/// just its number). With NO picked number: the original printed amount is
/// preferred while it still reads as an amount (so a range reads "2–3 cloves",
/// never a bare "clove" — round-2 #3), else the imprecise/measure unit word
/// ("to taste"), else empty (the caller renders "—" or a "set amount" prompt —
/// never an invented unit).
///
/// The AMOUNT slot never carries prose. A raw amount with no number in it is
/// not an amount — "(to serve (optional))" — so it shows the qualifier the
/// source named ("to serve") and nothing else; the prose itself rides the NOTES
/// slot instead (see [noteFromRawAmount]).
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
  // No number. A CLEAN catalog unit names itself — an imprecise amount reads
  // "pinch" / "to taste" / "handful", NEVER the raw phrase "A good pinch"
  // (round-3 #1a: an imprecise amount is a clean unit, not raw text).
  if (mapped != null) return mapped.label;
  // Unmapped/absent unit: the printed original still wins WHILE IT IS ONE — an
  // unpicked range ("2–3 cloves"), a "2 sprigs" the vocab couldn't map.
  final printed = raw.rawAmount.trim();
  if (printed.isNotEmpty && !isProseAmount(printed)) return printed;
  return amountQualifier(printed) ??
      (r.unit?.isNotEmpty ?? false ? r.unit! : '');
}

/// What the card actually prints in its AMOUNT slot: [amountLabel], except on
/// a line whose unit the matched ingredient cannot carry
/// ([LineIssue.unitNotAllowed]), where the slot prints NOTHING and the caller
/// renders its empty state (`—` / "set amount").
///
/// A slot reading "1 whole" or "1 can" looks *filled* — so the flag under it
/// ("Pick a supported unit") reads as pedantry rather than as the one thing
/// left to do. The word is the source's, not the kitchen's: "whole" is no unit
/// at all, and a "can" that the row measures as a `400 g can` is a word the
/// picker would never hand back. Blanking the slot says the amount is still
/// owed, which is the truth. The page's own words are not lost — a flagged
/// line keeps its `from source:` line in both states — and neither is the
/// parsed number: it stays on the resolution, so the amount sheet opens on
/// "1" and one chip tap resolves the line.
String amountSlotLabel(
  LineResolution r,
  RawLineItem raw,
  List<LineIssue> issues,
) => issues.contains(LineIssue.unitNotAllowed) ? '' : amountLabel(r, raw);

/// Whether the line's unit is one of the imprecise words — the card italicises
/// what [amountLabel] prints for one, so the reader can see it is a hand
/// gesture rather than a measurement.
bool isImpreciseAmount(LineResolution r) {
  if (r.unit == null) return false;
  return unitById(r.unit!)?.family == UnitFamily.imprecise;
}

/// Opens the step-7.7 quantity + unit-chip sheet for the flattened line at
/// [lineIndex] and writes the picked quantity + unit back onto its resolution
/// (decision 6). Only ever called on a MATCHED line (round-2 #7); the chips are
/// the matched ingredient's allowed set + measures + the always-admitted
/// imprecise units ([amountSheetIngredient], ADR-0008).
///
/// Round-2 #1 fix: the matched ingredient is loaded DIRECTLY by id (not via a
/// name search that could fail to return it and silently leave the tap inert);
/// a load failure degrades to a stub stand-in, and the sheet ALWAYS opens.
///
/// Round-1 fixes still hold: a picked MEASURE chip ("clove") rides its LABEL
/// through [sheetChoiceUnit] not a degraded "piece", and a RANGE opens on its
/// printed low endpoint so confirming resolves it.
///
/// Owner call (count-measure pre-selection): when the line's parsed unit is one
/// this ingredient cannot carry — the "pick a supported unit" flag — and the
/// ingredient names a measure, the sheet opens with that measure already
/// selected ([preselectedMeasure]), and Done adopts it even if no chip was
/// tapped. Resolving becomes one confirm tap; the flag stands until that tap.
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
  // A LINKED line is quantified against a RECIPE, not an ingredient: lane U's
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
      // Straight off the repository, NOT through the measures stream provider.
      // That read only ever worked because `importValidation` happened to be
      // holding the same watch open: on its own it mints an autoDispose element
      // with nothing listening, and a PowerSync watch does not emit before the
      // element is collected — so the future completed with a `StateError`, the
      // catch below turned it into "no measures", and the one-tap measure
      // repair silently did nothing.
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
  // A line already on one of the row's measures — the review landed a counted
  // lime on `lime, whole`, or a chip put it on `clove` — is a line being
  // edited, and opens on that measure rather than on the row's own seed.
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
  // The notifier is read HERE, after the awaited sheet, through the container
  // captured before it — never through `ref` (the chip's element can be
  // unmounted by now, and Riverpod 3 throws on that) and never as an instance
  // captured before the await (which can be a disposed one).
  container.read(importControllerProvider.notifier).updateResolution(
    lineIndex,
    (r) {
      // A pre-selected measure counts as picked on confirm: the sheet opened ON
      // it, so Done means "yes, that one" — otherwise the one-tap resolve would
      // silently keep the unit the line was flagged for.
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

/// Opens lane U's COMPONENT quantity sheet for a linked line (8.6 / D2 · D6)
/// and writes the picked amount back onto its resolution.
///
/// The target's yields come off the local repository — the link points at a
/// household recipe, which is a row this device already has — read STRAIGHT
/// from the keepAlive repository provider rather than through a stream provider
/// (an autoDispose element with nothing listening completes into an empty
/// default, and "no yields" would silently become "no yield set" on the sheet).
/// A read that cannot answer degrades the same honest way the sheet's own
/// no-yield state does: `batch` only, said out loud, never a guessed
/// conversion.
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
      // The summary's own conversion, so the dock opens on the target's yields
      // AND its own words in one step.
      target = r.asSubRecipeTarget;
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
    // The 7.7 stored-selection rule: the line's printed unit is admissible on
    // this line whatever the sheet would otherwise offer.
    initialUnit: stored,
    initialOptional: resolution.optional,
  );
  if (result == null) return;
  // Read AFTER the awaited sheet through the container, never captured before
  // it and never through a possibly-unmounted `ref` (see `editLineAmount`).
  container
      .read(importControllerProvider.notifier)
      .updateResolution(
        lineIndex,
        (r) => r
            .setAmount(quantity: result.quantity, unit: result.unit.id)
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
