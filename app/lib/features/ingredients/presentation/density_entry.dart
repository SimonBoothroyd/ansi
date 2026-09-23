/// The density entry, shared by the quantity sheet and the ingredient form.
///
/// Density is the single stored volume⇄mass fact (ADR-0008), entered as one
/// sentence: "`[1]` `[cup]` weighs `[30]` `[g]`". Both sides take an amount and
/// a unit, one a volume and one a weight, in either order. The block folds to
/// `0.13 g/ml · change` once a number is stated, and also owns removing it
/// (`clearDensity`).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../shared/amount_and_unit.dart';
import '../../../shared/format.dart';
import '../../../shared/inline_amount_field.dart';
import '../domain/allowed_units.dart';
import '../domain/density_said.dart';
import '../domain/ingredient.dart';
import 'ingredient_facts.dart';

class DensityEntry extends HookWidget {
  const DensityEntry({
    required this.ingredient,
    required this.redirectedSpoon,
    required this.onSave,
    required this.onRemove,
    this.serving,
    this.servingPrefill,
    this.saveLabel = 'Save',
    this.headline = 'DENSITY',
    super.key,
  });

  final Ingredient ingredient;

  /// The row's own `serving` measure, the first leg of [densityReading]. It
  /// arrives from a watched query, so it can be null on the first build.
  final Measure? serving;

  /// Set when the add-measure form redirected a volume-named label here —
  /// pre-picks that spoon and switches to the spoon phrasing.
  final Unit? redirectedSpoon;

  /// The form's own serving when it is a volume in this sentence's unit list,
  /// offered as the left-hand side, with the pack's printed weight beside it.
  /// An offer only: nothing is saved until the button is pressed.
  final ({double amount, Unit unit, double? grams})? servingPrefill;

  /// The host decides when a density lands (ADR-0011). This widget validates
  /// the sentence and hands it over as said; the number is derived from it
  /// when it is stored. The quantity sheet's host writes at once, the form's
  /// host holds it in its draft. Returns whether it landed.
  final Future<bool> Function(DensitySaid said) onSave;

  /// The mirror write: the number goes and the cross-family units it unlocked
  /// lock again. The host lands it.
  final Future<bool> Function() onRemove;

  /// What the inline button says; the host chooses it to match what the tap
  /// does.
  final String saveLabel;

  /// The section's micro-label. The flesh-out form says "DENSITY — OPTIONAL"
  /// (macros gate completion, density does not).
  final String headline;

  /// What either side offers: every mass and volume unit, in kitchen order.
  /// `ml` and `g` are included, so "1 ml weighs 0.66 g" states g/ml directly.
  /// Which side is the volume is read off the units picked.
  static const _units = [
    tsp, tbsp, flOz, cup, ml, l, pint, quart, //
    g, kg, oz, lb,
  ];

  /// The leading space above the headline, matching the form's other
  /// micro-labels. The entry draws it because it draws its own label.
  static const _leadingSpace = 20.0;

  @override
  Widget build(BuildContext context) {
    // The sentence opens as it was said. A density stored with no sentence
    // opens in the unit [densityReading] states it in.
    final said = densitySaidOf(ingredient);
    final read = densityReading(ingredient, serving: serving);
    final openUnit = said?.unit ?? read.unit;
    final openAmount = said?.amount ?? read.amount;
    final openWeight =
        said?.weighs ?? densityReadingWeight(ingredient, serving: serving);
    final openWeightUnit = said?.weighsUnit ?? g;
    final spoon = useState<Unit>(openUnit);
    // How many of that spoon the sentence is about. One unless the row's own
    // serving says otherwise, because one is what a density means.
    final amount = useState<double>(openAmount);
    final amountSeed = useState(0);
    final input = useState<double?>(openWeight);
    // Whether somebody has typed, picked a unit, or been handed a redirect or
    // serving offer. Until then the row's own reading may land as its queries
    // arrive; afterwards nothing rewrites the sentence.
    final aimed = useState(false);
    // What the weight is stated in. `g` is the common case and stays the
    // default; an American label prints ounces and now says so.
    final weightUnit = useState<Unit>(openWeightUnit);
    final error = useState<String?>(null);
    // Deleting a density also strips what it unlocked, so the affordance asks
    // once rather than acting on a stray tap.
    final confirmingRemoval = useState(false);
    // A row with a density opens folded; one without opens on the sentence.
    // Seeded once: the fold is a starting state, not a mirror of whether a
    // number exists (see `save`).
    final open = useState(ingredient.densityGPerMl == null);
    // The row's own reading follows the watched queries in, and stands down
    // once the sentence has been aimed.
    useEffect(() {
      if (aimed.value) return null;
      spoon.value = openUnit;
      amount.value = openAmount;
      input.value = openWeight;
      weightUnit.value = openWeightUnit;
      amountSeed.value++;
      return null;
    }, [openUnit, openAmount, openWeight, openWeightUnit]);
    // A redirect (a volume unit typed as a measure label) pre-picks that unit.
    useEffect(() {
      final r = redirectedSpoon;
      // It also unfolds: a redirect is a person mid-entry.
      if (r != null) {
        open.value = true;
        aimed.value = true;
      }
      if (r != null && _units.contains(r)) spoon.value = r;
      return null;
    }, [redirectedSpoon]);
    // The serving offered as the left-hand side, amount and unit together. It
    // unfolds the sentence only on a row with no density yet.
    useEffect(() {
      final offered = servingPrefill;
      // Only a VOLUME serving is an offer here: what a mass serving weighs is
      // itself, and this sentence would then say nothing.
      if (offered == null || offered.unit.family != UnitFamily.volume) {
        return null;
      }
      spoon.value = offered.unit;
      amount.value = offered.amount;
      // The pack printed the weight too, so the whole sentence is offered. The
      // button still lands it.
      if (offered.grams case final grams?) input.value = grams;
      amountSeed.value++;
      // An offer aims the sentence: the row's own reading stops landing in it.
      aimed.value = true;
      if (ingredient.densityGPerMl == null) open.value = true;
      return null;
    }, [servingPrefill]);

    final density = ingredient.densityGPerMl;
    // Only a row with a number can fold; a stale `false` must never render an
    // empty section.
    final expanded = open.value || density == null;

    Future<void> save() async {
      final v = input.value;
      final said = v == null
          ? null
          : DensitySaid(
              amount: amount.value,
              unit: spoon.value,
              weighs: v,
              weighsUnit: weightUnit.value,
            );
      final gPerMl = said?.gPerMl;
      if (said == null || gPerMl == null || !(gPerMl > 0)) {
        error.value = spoon.value.family == weightUnit.value.family
            ? 'one side is a volume and the other a weight — '
                  '“1 cup weighs 240 g”, or “30 ml weighs 1 oz”'
            : 'weigh it: ${_phrase(amount.value, spoon.value)} and what it '
                  'weighs must both be positive';
        return;
      }
      error.value = null;
      final landed = await onSave(said);
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
      // The section does not fold when a number lands: collapsing would pull
      // the focused field out of the tree and hide the equivalence line. It
      // folds the next time it is drawn.
    }

    // The number goes, and the units it unlocked go with it, in one write.
    Future<void> remove() async {
      final landed = await onRemove();
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
      error.value = null;
      open.value = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The headline: the sentence as said and the number derived from it,
        // or the number alone where nothing was said. Folded, this row is the
        // whole section: `DENSITY ⅓ cup weighs 40 g · 0.507 g/ml · change`.
        Padding(
          padding: const EdgeInsets.only(top: _leadingSpace),
          child: Row(
            children: [
              Text(headline, style: ansiLabel()),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  density == null
                      ? 'none yet — unlocks volume⇄weight'
                      : densityFact(ingredient, serving: serving),
                  style: ansiMono(
                    size: 10,
                    color: density == null
                        ? AnsiColors.muted
                        : AnsiColors.herbDeep,
                  ),
                ),
              ),
              if (!expanded) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => open.value = true,
                  child: Text(
                    '· change',
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          // One sentence, "1 [tbsp] weighs [__] g [Add]", on one run at 402 pt.
          // A Wrap of dense chips, a compact field and a button at its own
          // width; `density_entry_test.dart` measures the run with the real
          // fonts.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 6,
            children: [
              AmountAndUnitField(
                seed: amountSeed.value,
                amountKey: const ValueKey('density-amount'),
                unitKey: const ValueKey('density-amount-unit'),
                amountWidth: kInlineAmountWidth,
                amount: formatQuantityIn(amount.value, spoon.value),
                unit: spoon.value,
                units: _units,
                onAmount: (t) {
                  aimed.value = true;
                  amount.value = parseAmount(t) ?? 0;
                },
                onUnit: (u) {
                  aimed.value = true;
                  spoon.value = u;
                },
                onSubmit: save,
              ),
              // One word: a longer connector pushes the run past 402 pt.
              Text('weighs', style: ansiMono(size: 12)),
              AmountAndUnitField(
                // Re-seeded with its left-hand side, so the two slots move
                // together.
                seed: amountSeed.value,
                amountKey: const ValueKey('density-grams'),
                unitKey: const ValueKey('density-grams-unit'),
                amountWidth: kInlineWeightWidth,
                // A weight seeded from the stored density prints as a scale
                // reading (`156.15 g`), not as a fraction.
                amount: input.value == null
                    ? ''
                    : formatAmountIn(input.value!, weightUnit.value),
                unit: weightUnit.value,
                units: _units,
                onAmount: (t) {
                  aimed.value = true;
                  input.value = parseAmount(t);
                },
                onUnit: (u) {
                  aimed.value = true;
                  weightUnit.value = u;
                },
                onSubmit: save,
              ),
              FButton(
                size: FButtonSizeVariant.xs,
                // Its own width, not the line's: a full-width button IS a row,
                // and this one has to end a sentence.
                mainAxisSize: MainAxisSize.min,
                style: const FButtonStyleDelta.delta(
                  contentStyle: FButtonContentStyleDelta.delta(
                    padding: EdgeInsetsGeometryDelta.value(
                      EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                    ),
                  ),
                ),
                onPress: save,
                child: Text(saveLabel),
              ),
            ],
          ),
          if (servingPrefill?.unit.family == UnitFamily.volume)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              // Says what to do with what is in the slots, not where they came
              // from.
              child: Text(
                servingPrefill!.grams == null
                    ? 'your serving, ready to use — type what that much '
                          'weighs (the pack’s “(32 g)”)'
                    : _prefillHeld(servingPrefill!, density)
                    ? 'both halves come from the pack’s serving line — '
                          'check them against it'
                    : 'both halves come from the pack’s serving line — check '
                          'them, then tap $saveLabel',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
          if (density != null)
            _RemoveDensity(
              ingredient: ingredient,
              confirming: confirmingRemoval,
              onRemove: remove,
            ),
          if (error.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error.value!,
                style: ansiMono(size: 10, color: AnsiColors.gone),
              ),
            )
          else if (input.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                // The live equivalence: the g/ml the sentence above will store.
                switch (densityForPair(
                  amount.value,
                  spoon.value,
                  input.value!,
                  weightUnit.value,
                )) {
                  final gPerMl? => '= ${formatDensity(gPerMl)} g/ml',
                  null => '',
                },
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ),
        ],
      ],
    );
  }
}

/// Whether [density] is already the one [offer] states — the host landed the
/// pack's serving line itself, so there is nothing left to tap.
bool _prefillHeld(
  ({double amount, Unit unit, double? grams}) offer,
  double? density,
) {
  final grams = offer.grams;
  if (density == null || grams == null) return false;
  final offered = densityForPair(offer.amount, offer.unit, grams, g);
  return offered != null && (offered - density).abs() < 1e-9;
}

/// `2 tbsp` — a side of the sentence as the refusal quotes it back, said the
/// way its own unit is said.
String _phrase(double amount, Unit unit) =>
    '${formatQuantityIn(amount, unit)} ${unit.label}';

/// Removes the stored density, the one write that shrinks the allowed list. The
/// confirmation names the consequence: the cross-family chips the density
/// unlocked ([densityStrippedUnits]) lock again. Recipe lines already using one
/// are left as written.
class _RemoveDensity extends StatelessWidget {
  const _RemoveDensity({
    required this.ingredient,
    required this.confirming,
    required this.onRemove,
  });

  final Ingredient ingredient;
  final ValueNotifier<bool> confirming;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    if (!confirming.value) {
      return Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => confirming.value = true,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'remove the density',
              style: ansiMono(size: 10, color: AnsiColors.gone),
            ),
          ),
        ),
      );
    }
    final stripped = densityStrippedUnits(ingredient);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stripped.isEmpty
                ? 'Remove it? Nothing about what a line may say changes.'
                : 'Remove it? ${stripped.map((u) => u.label).join(' · ')} '
                      'lock again.',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: onRemove,
                child: const Text('Remove'),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => confirming.value = false,
                child: Text(
                  'keep it',
                  style: ansiMono(size: 10, color: AnsiColors.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The small pill that toggles one of a mutually exclusive pair/row — the
/// density phrasings, the spoon choice, the form's basis and source segments.
class AnsiModeChip extends StatelessWidget {
  const AnsiModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.stranded = false,
    this.dense = false,
    super.key,
  });

  final String label;
  final bool selected;

  /// A chip set inside a sentence: same type and colours, three points less
  /// padding each side.
  final bool dense;

  /// Selected but no longer sayable, e.g. a `cup` default on a per-100 g row
  /// with no density. Drawn in [AnsiColors.gone].
  final bool stranded;

  final VoidCallback onTap;

  /// A disabled option still renders, so the user can see it exists.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final border = stranded
        ? AnsiColors.gone
        : !enabled
        ? AnsiColors.line
        : (selected ? AnsiColors.herb : AnsiColors.line);
    final text = stranded
        ? AnsiColors.gone
        : !enabled
        ? AnsiColors.muted
        : (selected ? AnsiColors.herbDeep : AnsiColors.muted);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected && enabled && !stranded
              ? AnsiColors.herbSoft
              : AnsiColors.surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: ansiMono(size: 10, color: text)),
      ),
    );
  }
}
