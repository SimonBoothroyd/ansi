/// The density entry (design board `pv2-b2`, step 7.8) — extracted from the
/// manage-measures sheet so the step-8.5 flesh-out form shares it rather than
/// growing a second one.
///
/// ADR-0008: density is the SINGLE stored volume⇄mass fact, and it is entered
/// as one sentence — "`[1]` `[cup]` weighs `[__]` `[g]`". Every phrasing
/// resolves to one number, and the write extends the ingredient's explicit
/// `allowed_units` with what the density unlocks in the same transaction
/// (`setDensity`).
///
/// **Both sides take an amount and a unit**, because a pack states both and
/// neither of them is grams per millilitre: a label says *1/4 cup = 30 g* or
/// *30 ml weighs 1 oz*, and a sentence that fixed either half made the person
/// do the conversion in their head before they could type. One side is a
/// volume and the other a weight — in either order — and the stored fact is
/// still the one number. This is also the ONLY place a density is stated —
/// the macros section's serving row does none, whatever unit it is in.
///
/// The sentence holds **one run at 402 pt**, and the block **folds** to
/// `0.13 g/ml · change` for a row that already states a number — a density is
/// entered once and read often.
///
/// It also owns the **deletion** of that number — the mirror write, which
/// strips the cross-family units the density was the only reason to admit
/// (`clearDensity`). That is the single leg of the admission model where the
/// allowed list shrinks; everything else unions.
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
import '../../../shared/amount_and_unit.dart';
import '../../../shared/format.dart';
import '../domain/allowed_units.dart';
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

  /// The row's own `serving` measure, when it states one — the first leg of
  /// [densityReading], which is what this sentence opens on.
  ///
  /// It arrives with a watched query, so it can be null on the first build of
  /// a row that has one; the seeding effect follows it in.
  final Measure? serving;

  /// Set when the add-measure form redirected a volume-named label here —
  /// pre-picks that spoon and switches to the spoon phrasing.
  final Unit? redirectedSpoon;

  /// The form's own serving, when it is a **volume** — "2 tbsp" — offered as
  /// this sentence's left-hand side, with the weight the pack printed beside
  /// it ("(32 g)") in the slot that takes one. Only a serving in this
  /// sentence's own unit list is offered: an amount kept beside a unit the row
  /// cannot show would describe a different serving from the one on screen.
  ///
  /// It is an offer and nothing more — the sentence is still what states the
  /// density, nothing is saved until the button is pressed, and typing over
  /// either half is the ordinary case.
  final ({double amount, Unit unit, double? grams})? servingPrefill;

  /// **The host decides when a density lands** (ADR-0011). This widget
  /// validates the input and computes the one stored number; it does not know a
  /// repository. The quantity sheet's host writes immediately — it has no Save
  /// and that is correct there — and the flesh-out form's host holds it in a
  /// draft until the form's own Save.
  ///
  /// Returns whether it landed, which is all this widget needs in order to
  /// clear its own error and confirmation state. Everything else — the write,
  /// the invalidation, retiring a redirect — belongs to the host.
  ///
  /// This is deliberately **not** a boolean mode on the widget: two behaviours
  /// behind a flag inside one shared widget is exactly how the form came to
  /// have two persistence models at once.
  final Future<bool> Function(double gPerMl) onSave;

  /// The mirror write (D4b): the number goes and the cross-family units it
  /// was the only reason to admit lock again. Same rule — the host lands it.
  final Future<bool> Function() onRemove;

  /// What the inline button says. It reads `Save` in a host that writes on
  /// tap and `Add`/`Save` as the host chooses — because a button that says
  /// Save while writing nothing is the confusion this plan is removing.
  final String saveLabel;

  /// The section's micro-label. The flesh-out form says "DENSITY — OPTIONAL"
  /// (macros gate completion, density does not).
  final String headline;

  /// What either side offers: every mass and volume unit the kitchen has, in
  /// kitchen order. `ml` and `g` are in the list on purpose — their ratio to
  /// base is 1, so "1 ml weighs 0.66 g" IS 0.66 g/ml, exactly, which is what
  /// let the old direct-g/ml field be deleted rather than merely hidden.
  ///
  /// The two sides are not typed differently. Which one is the volume and
  /// which the weight is read off the units the person picked, so "1/4 cup
  /// weighs 30 g" and "30 ml weighs 1 oz" are the same sentence said in the
  /// order the pack printed it.
  static const _units = [
    tsp, tbsp, flOz, cup, ml, l, pint, quart, //
    g, kg, oz, lb,
  ];

  /// The leading space above the headline — the same one every micro-label in
  /// the flesh-out form's groups carries, so `DENSITY` reads as a subject of
  /// its own rather than as a caption under the admission chips.
  /// The entry draws it itself because it draws its own label: a host that
  /// spaced it from outside would be spacing a label it cannot see.
  static const _leadingSpace = 20.0;

  @override
  Widget build(BuildContext context) {
    // **The sentence opens in the row's own words** — the unit the fact sheet
    // states this density in ([densityReading]), with the weight it comes to
    // in that unit. A row whose serving is `1 tsp` reopens as `1 tsp weighs
    // 5 g`; one with a volume default reopens in it; anything else reopens on
    // the cup a person can picture. One derivation, read by both, so a number
    // is reopened in the words it was entered in and the fact sheet says the
    // same sentence back.
    final read = densityReading(ingredient, serving: serving);
    final storedWeight = densityReadingWeight(ingredient, serving: serving);
    final spoon = useState<Unit>(read.unit);
    // How many of that spoon the sentence is about. One unless the row's own
    // serving says otherwise, because one is what a density means.
    final amount = useState<double>(read.amount);
    final amountSeed = useState(0);
    final input = useState<double?>(storedWeight);
    // Whether somebody has aimed this sentence at something — typed in it,
    // picked a unit, or been handed a redirect or a serving offer. Until then
    // the row's own reading may land in it as the watched queries behind it
    // arrive; after it, the sentence is theirs and nothing rewrites it.
    final aimed = useState(false);
    // What the weight is stated in. `g` is the common case and stays the
    // default; an American label prints ounces and now says so.
    final weightUnit = useState<Unit>(g);
    final error = useState<String?>(null);
    // Deleting a density also strips what it unlocked (D4b), so the affordance
    // asks once rather than acting on a stray tap.
    final confirmingRemoval = useState(false);
    // **A stated density folds** (owner-ruled). The number is entered
    // once and read often, so the sentence that enters it is not the everyday
    // height of this section — `0.13 g/ml · change` is. A row with no density
    // opens on the sentence, because there the entry IS the subject.
    //
    // It is seeded once, from the row as the section was first drawn: the fold
    // is a starting state, not a live mirror of whether a number exists (see
    // `save`).
    final open = useState(ingredient.densityGPerMl == null);
    // The row's own reading, following the watched queries in. A serving
    // arrives after the first build, so the sentence this section opens on is
    // not knowable when its state is created — and once somebody has aimed it
    // this stands down, so a density landing in the draft never rewrites the
    // sentence that was just typed.
    useEffect(() {
      if (aimed.value) return null;
      spoon.value = read.unit;
      amount.value = read.amount;
      input.value = storedWeight;
      amountSeed.value++;
      return null;
    }, [read.unit, read.amount, storedWeight]);
    // A redirect ("cup" typed as a measure label) lands in spoon phrasing
    // with that spoon picked — cup is in the selectable set; any other
    // volume unit keeps the current spoon (the phrasing still applies).
    useEffect(() {
      final r = redirectedSpoon;
      // The redirect no longer has a mode to switch — there is only the one
      // sentence — so it just pre-picks the unit it resolved. It also unfolds:
      // a redirect is a person mid-entry, and the fold would swallow it.
      if (r != null) {
        open.value = true;
        aimed.value = true;
      }
      if (r != null && _units.contains(r)) spoon.value = r;
      return null;
    }, [redirectedSpoon]);
    // The serving offered as the left-hand side. Both halves or neither: an
    // amount of 2 with the spoon left on tbsp when the serving said cup would
    // be a sentence about something nobody typed. It unfolds the sentence
    // only on a row that has no density yet — a stated density stays
    // folded, offer or no offer; the offer is waiting behind `change`.
    useEffect(() {
      final offered = servingPrefill;
      // Only a VOLUME serving is an offer here: what a mass serving weighs is
      // itself, and this sentence would then say nothing.
      if (offered == null || offered.unit.family != UnitFamily.volume) {
        return null;
      }
      spoon.value = offered.unit;
      amount.value = offered.amount;
      // The pack printed the weight too, so the whole sentence is offered
      // rather than half of it. Still an offer: it is typed into the field
      // the person is looking at, and the button is what lands it.
      if (offered.grams case final grams?) input.value = grams;
      amountSeed.value++;
      // An offer aims the sentence: the row's own reading stops landing in it.
      aimed.value = true;
      if (ingredient.densityGPerMl == null) open.value = true;
      return null;
    }, [servingPrefill]);

    final density = ingredient.densityGPerMl;
    // Folding is only ever a state of a row that HAS a number: with none
    // there is nothing to fold to, and a stale `false` (the number was
    // removed by a host that is not us) must never render an empty section.
    final expanded = open.value || density == null;

    Future<void> save() async {
      final v = input.value;
      final gPerMl = v == null
          ? null
          : densityForPair(amount.value, spoon.value, v, weightUnit.value);
      if (gPerMl == null || !(gPerMl > 0)) {
        error.value = spoon.value.family == weightUnit.value.family
            ? 'one side is a volume and the other a weight — '
                  '“1 cup weighs 240 g”, or “30 ml weighs 1 oz”'
            : 'weigh it: ${_phrase(amount.value, spoon.value)} and what it '
                  'weighs must both be positive';
        return;
      }
      error.value = null;
      final landed = await onSave(gPerMl);
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
      // **The fold is where this section OPENS, not something that happens
      // under your hands.** Collapsing the moment a number lands would pull
      // the field you are typing in out of the tree — keyboard, focus,
      // in-flight ensure-visible scroll and all — and it would hide the
      // equivalence line ("= 0.66 g/ml") at exactly the moment it is the
      // receipt for what you just did. So the sentence stays put for this
      // visit, the removal affordance joins it, and the next time the
      // section is drawn it is one line.
    }

    // D4b's strip leg from the user's side: the number goes, and the units it
    // was the only reason to admit go with it, in one write.
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
        // The headline and the stored number. The two phrasing chips that used
        // to sit opposite them are GONE: the segment existed to choose between
        // a sentence a person would say and one they would have to compute, and
        // nobody divides grams by millilitres in their head. With them go G2's
        // width problem — that fix was about these four things not fitting a
        // 402pt phone — and the naming problem the label had ("a spoon weighs…"
        // was cute; "grams per spoon" hid cup).
        //
        // Folded, this row is the whole section: `DENSITY 0.13 g/ml · change`.
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
                      : '${formatDensity(density)} g/ml',
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
          // One self-describing sentence, and it reads as a SENTENCE:
          // "1 [tbsp] weighs [__] g [Add]" on ONE run at 402 pt.
          // A Wrap — G2's lesson stands, this is a row of controls with no
          // slack to distribute — but every part of it is sized so the common
          // case does not break: dense chips, a compact field with no field
          // chrome, and a button that takes its own width rather than the
          // whole line. A full-height field or a full-width button is a ROW,
          // and three rows is not a sentence. `density_entry_test.dart`
          // measures the run at 402 pt with the real fonts loaded.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 6,
            children: [
              AmountAndUnitField(
                seed: amountSeed.value,
                amountKey: const ValueKey('density-amount'),
                unitKey: const ValueKey('density-amount-unit'),
                // Narrow slots: a serving is `2` or `0.25`, never `1000`, and
                // every point here is a point the sentence needs to stay one
                // run at 402 pt.
                amountWidth: 34,
                unitWidth: 68,
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
              // The connector is one word, and it is the one word here that
              // had to be paid for in pixels: "of this weighs" makes the run
              // far wider than the phone, and nothing short of unreadable
              // controls and 10 pt prose closes that gap. "1 tbsp weighs 15 g"
              // says the same thing — *this* is the section's own subject,
              // named by the headline above it and by the ingredient the
              // whole screen is about.
              Text('weighs', style: ansiMono(size: 12)),
              AmountAndUnitField(
                // Re-seeded with its left-hand side: a pack states the pair
                // in one line, so the two slots move together or the
                // sentence describes a spoonful nobody typed.
                seed: amountSeed.value,
                amountKey: const ValueKey('density-grams'),
                unitKey: const ValueKey('density-grams-unit'),
                amountWidth: 34,
                unitWidth: 62,
                // In the unit the slot beside it names: a weight seeded from
                // the stored density is a scale reading — `156.15 g`, never
                // `156 1/8` — and it has to read as the fact sheet says it.
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
              child: Text(
                servingPrefill!.grams == null
                    ? 'the serving you typed above · the pack’s “(32g)” goes '
                          'here'
                    : 'the pack’s own serving line, both halves — check it '
                          'and tap $saveLabel',
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
                // The live equivalence: what the sentence above will store.
                // The g/ml figure is the ASIDE, not the sentence — the
                // sentence is the one a kitchen says.
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

/// The density the sentence states: "[a] [ua] weighs [b] [ub]", where one
/// side is a volume and the other a weight, in either order.
///
/// A pack prints "1/4 cup (30 g)" or "30 ml (1 oz)"; the stored fact is still
/// one number, and it is the weight in grams over the volume in millilitres —
/// never a figure a person had to convert in their head first. Null on honest
/// terms: two units of the same family (there is nothing to bridge), a unit
/// that is neither mass nor volume, or an amount that is not positive
/// (invariant 3 — never a fabricated number).
double? densityForPair(double a, Unit ua, double b, Unit ub) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(a > 0) || !(b > 0)) return null;
  final ({double amount, Unit unit}) volume;
  final ({double amount, Unit unit}) mass;
  if (ua.family == UnitFamily.volume && ub.family == UnitFamily.mass) {
    volume = (amount: a, unit: ua);
    mass = (amount: b, unit: ub);
  } else if (ua.family == UnitFamily.mass && ub.family == UnitFamily.volume) {
    volume = (amount: b, unit: ub);
    mass = (amount: a, unit: ua);
  } else {
    return null;
  }
  final inMl = convert(Quantity(volume.amount, volume.unit), to: ml);
  final inGrams = convert(Quantity(mass.amount, mass.unit), to: g);
  if (inMl case Ok(value: final v) when v.amount > 0) {
    if (inGrams case Ok(value: final w)) return w.amount / v.amount;
  }
  return null;
}

/// `2 tbsp` — a side of the sentence as the refusal quotes it back, said the
/// way its own unit is said.
String _phrase(double amount, Unit unit) =>
    '${formatQuantityIn(amount, unit)} ${unit.label}';

/// Deleting the stored density — the one write in the whole admission model
/// that makes the allowed list *shrink*.
///
/// It asks first, and the question names the consequence rather than saying
/// "are you sure": the cross-family chips this density unlocked
/// ([densityStrippedUnits]) lock again in the same write, and a recipe line
/// already saying one of them is left exactly as the user wrote it — flagged
/// on the import review like any other unsupported unit, never rewritten.
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

  /// A chip that is a WORD IN A SENTENCE rather than an option in a row of its
  /// own — the density sentence's spoon. Same type, same colours, three
  /// points less padding each side, which is part of what lets the sentence
  /// hold one run at 402 pt.
  final bool dense;

  /// Selected, but no longer sayable — the D4c shape: a `cup` default on a
  /// per-100 g row with no density. Drawn in [AnsiColors.gone] rather than in
  /// the herb of a healthy selection, so the chip says which unit the line
  /// underneath is about.
  final bool stranded;

  final VoidCallback onTap;

  /// A disabled option still renders — a segment that hides its unavailable
  /// leg tells the user nothing about why (board frame d's Barcode option,
  /// which lands with lane B).
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
