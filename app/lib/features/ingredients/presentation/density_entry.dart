/// The density entry (design board `pv2-b2`, step 7.8) — extracted from the
/// manage-measures sheet so the step-8.5 flesh-out form shares it rather than
/// growing a second one.
///
/// ADR-0008: density is the SINGLE stored volume⇄mass fact, enterable two
/// equivalent ways — a direct g/ml field, or "1 tbsp of this weighs __ g"
/// (spoon selectable tsp/tbsp/cup; converts through ml-per-spoon and writes
/// the same `density_g_per_ml`). Both phrasings resolve to one number, and
/// the write extends the ingredient's explicit `allowed_units` with what the
/// density unlocks in the same transaction (`setDensity`).
///
/// It also owns the **deletion** of that number (plan 0020 D4b) — the mirror
/// write, which strips the cross-family units the density was the only reason
/// to admit (`clearDensity`). That is the single leg of the admission model
/// where the allowed list shrinks; everything else unions.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';

class DensityEntry extends HookWidget {
  const DensityEntry({
    required this.ingredient,
    required this.redirectedSpoon,
    required this.onSave,
    required this.onRemove,
    this.saveLabel = 'Save',
    this.headline = 'DENSITY',
    super.key,
  });

  final Ingredient ingredient;

  /// Set when the add-measure form redirected a volume-named label here —
  /// pre-picks that spoon and switches to the spoon phrasing.
  final Unit? redirectedSpoon;

  /// **The host decides when a density lands** (plan 0029 W1, ADR-0011). This
  /// widget validates the input and computes the one stored number; it does
  /// not know a repository. The quantity sheet's host writes immediately —
  /// it has no Save and that is correct there — and the flesh-out form's host
  /// holds it in a draft until the form's own Save.
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
  /// (plan 0020 D5: macros gate completion, density does not).
  final String headline;

  /// What "1 __ of this weighs" offers. `ml` is in the list on purpose: its
  /// ratio to base is 1, so "1 ml of this weighs 0.66 g" IS 0.66 g/ml,
  /// exactly. That is what let the old direct-g/ml field be deleted rather
  /// than merely hidden — the two phrasings ADR-0008 promises are now two
  /// picks in one sentence instead of two controls behind a segment.
  static const _measures = [tsp, tbsp, cup, ml];

  @override
  Widget build(BuildContext context) {
    final spoon = useState<Unit>(tbsp);
    final input = useState<double?>(null);
    final error = useState<String?>(null);
    // Deleting a density also strips what it unlocked (D4b), so the affordance
    // asks once rather than acting on a stray tap.
    final confirmingRemoval = useState(false);
    // A redirect ("cup" typed as a measure label) lands in spoon phrasing
    // with that spoon picked — cup is in the selectable set; any other
    // volume unit keeps the current spoon (the phrasing still applies).
    useEffect(() {
      final r = redirectedSpoon;
      // The redirect no longer has a mode to switch — there is only the one
      // sentence — so it just pre-picks the unit it resolved.
      if (r != null && _measures.contains(r)) spoon.value = r;
      return null;
    }, [redirectedSpoon]);

    final density = ingredient.densityGPerMl;

    Future<void> save() async {
      final v = input.value;
      final gPerMl = v == null ? null : densityFromVolumeWeight(spoon.value, v);
      if (gPerMl == null || !(gPerMl > 0)) {
        error.value =
            'weigh it: grams per ${spoon.value.label} must be positive';
        return;
      }
      error.value = null;
      final landed = await onSave(gPerMl);
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
    }

    // D4b's strip leg from the user's side: the number goes, and the units it
    // was the only reason to admit go with it, in one write.
    Future<void> remove() async {
      final landed = await onRemove();
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
      error.value = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The headline and the stored number. The two phrasing chips that
        // used to sit opposite them are GONE (plan 0028): the segment existed
        // to choose between a sentence a person would say and one they would
        // have to compute, and nobody divides grams by millilitres in their
        // head. With them go G2's width problem — that fix was about these
        // four things not fitting a 402pt phone — and the naming problem the
        // label had ("a spoon weighs…" was cute; "grams per spoon" hid cup).
        Row(
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
          ],
        ),
        const SizedBox(height: 8),
        // One self-describing sentence: "1 [tbsp] of this weighs [__] g".
        // Still a Wrap (G2's lesson stands — it is a row of controls, not a
        // row with slack), but a shorter one now that the mode is gone.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Text('1', style: ansiMono(size: 13)),
            for (final u in _measures)
              AnsiModeChip(
                label: u.label,
                selected: spoon.value == u,
                onTap: () => spoon.value = u,
              ),
            Text('of this weighs', style: ansiMono(size: 13)),
            SizedBox(
              width: 72,
              child: FTextField(
                hint: 'g',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  onChange: (v) => input.value = double.tryParse(v.text.trim()),
                ),
              ),
            ),
            FButton(
              size: FButtonSizeVariant.sm,
              onPress: save,
              child: Text(saveLabel),
            ),
          ],
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
              densityFromVolumeWeight(spoon.value, input.value!) == null
                  ? ''
                  : '= ${formatDensity(densityFromVolumeWeight(spoon.value, input.value!)!)} g/ml',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
      ],
    );
  }
}

/// Deleting the stored density — the one write in the whole admission model
/// that makes the allowed list *shrink* (plan 0020 D4b).
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
    super.key,
  });

  final String label;
  final bool selected;

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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
