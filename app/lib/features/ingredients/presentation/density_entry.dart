/// The density entry (design board `pv2-b2`, step 7.8) — extracted from the
/// manage-measures sheet so the step-8.5 flesh-out form shares it rather than
/// growing a second one.
///
/// ADR-0008: density is the SINGLE stored volume⇄mass fact, and it is entered
/// as one sentence — "`[2]` `[tbsp]` weighs `[__]` g" (spoon selectable
/// tsp/tbsp/cup/ml; converts through ml-per-spoon and writes the same
/// `density_g_per_ml`). Every phrasing resolves to one number, and the write
/// extends the ingredient's explicit `allowed_units` with what the density
/// unlocks in the same transaction (`setDensity`).
///
/// **The sentence takes an amount**, because a pack states one: "2 tbsp
/// (32 g)" is typed as it reads rather than halved in the head, and it reads
/// back the same way. This is also the ONLY place a density is stated — the
/// macros section's serving row does none, whatever unit it is in.
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

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../../../shared/inline_amount_field.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';

class DensityEntry extends HookWidget {
  const DensityEntry({
    required this.ingredient,
    required this.redirectedSpoon,
    required this.onSave,
    required this.onRemove,
    this.servingPrefill,
    this.saveLabel = 'Save',
    this.headline = 'DENSITY',
    super.key,
  });

  final Ingredient ingredient;

  /// Set when the add-measure form redirected a volume-named label here —
  /// pre-picks that spoon and switches to the spoon phrasing.
  final Unit? redirectedSpoon;

  /// The form's own serving, when it is a **volume** — "2 tbsp" — offered as
  /// this sentence's left-hand side so the pack's "(32 g)" is typed where it
  /// belongs. Only a serving in this sentence's own unit list is offered: an
  /// amount kept beside a unit the row cannot show would describe a different
  /// serving from the one on screen.
  ///
  /// It is an offer and nothing more — the sentence is still what states the
  /// density, and typing over either half is the ordinary case.
  final ({double amount, Unit unit})? servingPrefill;

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

  /// What "1 __ weighs" offers. `ml` is in the list on purpose: its
  /// ratio to base is 1, so "1 ml weighs 0.66 g" IS 0.66 g/ml,
  /// exactly. That is what let the old direct-g/ml field be deleted rather
  /// than merely hidden — the two phrasings ADR-0008 promises are now two
  /// picks in one sentence instead of two controls behind a segment.
  static const _measures = [tsp, tbsp, cup, ml];

  /// The leading space above the headline — the same one every micro-label in
  /// the flesh-out form's groups carries, so `DENSITY` reads as a subject of
  /// its own rather than as a caption under the admission chips.
  /// The entry draws it itself because it draws its own label: a host that
  /// spaced it from outside would be spacing a label it cannot see.
  static const _leadingSpace = 20.0;

  @override
  Widget build(BuildContext context) {
    final spoon = useState<Unit>(tbsp);
    // How many of that spoon the sentence is about. One by default, because
    // one is what a density means; a pack that prints two says so.
    final amount = useState<double>(1);
    final amountSeed = useState(0);
    final input = useState<double?>(null);
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
    // A redirect ("cup" typed as a measure label) lands in spoon phrasing
    // with that spoon picked — cup is in the selectable set; any other
    // volume unit keeps the current spoon (the phrasing still applies).
    useEffect(() {
      final r = redirectedSpoon;
      // The redirect no longer has a mode to switch — there is only the one
      // sentence — so it just pre-picks the unit it resolved. It also unfolds:
      // a redirect is a person mid-entry, and the fold would swallow it.
      if (r != null) open.value = true;
      if (r != null && _measures.contains(r)) spoon.value = r;
      return null;
    }, [redirectedSpoon]);
    // The serving offered as the left-hand side. Both halves or neither: an
    // amount of 2 with the spoon left on tbsp when the serving said cup would
    // be a sentence about something nobody typed. It unfolds the sentence
    // only on a row that has no density yet — a stated density stays
    // folded, offer or no offer; the offer is waiting behind `change`.
    useEffect(() {
      final offered = servingPrefill;
      if (offered == null || !_measures.contains(offered.unit)) return null;
      spoon.value = offered.unit;
      amount.value = offered.amount;
      amountSeed.value++;
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
          : densityForAmount(amount.value, spoon.value, v);
      if (gPerMl == null || !(gPerMl > 0)) {
        error.value =
            'weigh it: grams per '
            '${_phrase(amount.value, spoon.value)} must be positive';
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
              InlineAmountField(
                key: ValueKey('density-amount-${amountSeed.value}'),
                fieldKey: const ValueKey('density-amount'),
                // Narrower than the grams slot: a serving is `2` or `0.25`,
                // never `1000`, and every point here is a point the sentence
                // needs to stay one run at 402 pt.
                width: 40,
                initial: _phrase(amount.value, null),
                onChange: (t) => amount.value = double.tryParse(t.trim()) ?? 0,
                onSubmit: save,
              ),
              for (final u in _measures)
                AnsiModeChip(
                  label: u.label,
                  selected: spoon.value == u,
                  dense: true,
                  onTap: () => spoon.value = u,
                ),
              // The connector is one word, and it is the one word here that
              // had to be paid for in pixels: "of this weighs" makes the run
              // 421 pt against 338 available, and nothing short of unreadable
              // chips and 10 pt prose closes that gap. "1 tbsp weighs 15 g"
              // says the same thing — *this* is the section's own subject,
              // named by the headline above it and by the ingredient the
              // whole screen is about.
              Text('weighs', style: ansiMono(size: 12)),
              InlineAmountField(
                fieldKey: const ValueKey('density-grams'),
                onChange: (t) => input.value = double.tryParse(t.trim()),
                onSubmit: save,
              ),
              Text('g', style: ansiMono(size: 12)),
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
          if (servingPrefill != null &&
              _measures.contains(servingPrefill!.unit))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'the serving you typed above · the pack’s “(32g)” goes here',
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
                switch (densityForAmount(
                  amount.value,
                  spoon.value,
                  input.value!,
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

/// The density implied by "[amount] [volumeUnit] weighs [grams] g" — the
/// sentence's arithmetic, one step up from [densityFromVolumeWeight].
///
/// A pack prints "2 tbsp (32 g)"; the stored fact is still one number, and it
/// is that line divided by its own amount rather than by a figure a person had
/// to halve in their head. Null on the same honest terms its one-spoon form
/// uses: a non-volume unit, or an amount or weight that is not positive
/// (invariant 3 — never a fabricated number).
double? densityForAmount(double amount, Unit volumeUnit, double grams) {
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (!(amount > 0) || !(grams > 0)) return null;
  return densityFromVolumeWeight(volumeUnit, grams / amount);
}

/// `2 tbsp` / `2` — the sentence's left-hand side, under the app's one number
/// rule. A null [unit] gives the bare amount, which is what seeds the field.
String _phrase(double amount, Unit? unit) =>
    '${formatQuantity(amount)}${unit == null ? '' : ' ${unit.label}'}';

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
