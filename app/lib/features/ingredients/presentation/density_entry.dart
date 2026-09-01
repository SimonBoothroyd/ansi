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
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';

class DensityEntry extends HookConsumerWidget {
  const DensityEntry({
    required this.ingredient,
    required this.redirectedSpoon,
    required this.onSaved,
    this.headline = 'DENSITY',
    super.key,
  });

  final Ingredient ingredient;

  /// Set when the add-measure form redirected a volume-named label here —
  /// pre-picks that spoon and switches to the spoon phrasing.
  final Unit? redirectedSpoon;
  final ValueChanged<Ingredient> onSaved;

  /// The section's micro-label. The flesh-out form says "DENSITY — OPTIONAL"
  /// (plan 0020 D5: macros gate completion, density does not).
  final String headline;

  static const _spoons = [tsp, tbsp, cup];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spoonMode = useState(false);
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
      if (r != null) {
        spoonMode.value = true;
        if (_spoons.contains(r)) spoon.value = r;
      }
      return null;
    }, [redirectedSpoon]);

    final density = ingredient.densityGPerMl;

    Future<void> save() async {
      final v = input.value;
      final gPerMl = spoonMode.value
          ? (v == null ? null : densityFromVolumeWeight(spoon.value, v))
          : v;
      if (gPerMl == null || !(gPerMl > 0)) {
        error.value = spoonMode.value
            ? 'weigh it: grams per ${spoon.value.label} must be positive'
            : 'g/ml must be a positive number';
        return;
      }
      error.value = null;
      final updated = await ref
          .read(ingredientRepositoryProvider)
          .setDensity(ingredient.id, gPerMl);
      if (!context.mounted || updated == null) return;
      confirmingRemoval.value = false;
      onSaved(updated);
    }

    // D4b's strip leg from the user's side: the number goes, and the units it
    // was the only reason to admit go with it, in one write.
    Future<void> remove() async {
      final updated = await ref
          .read(ingredientRepositoryProvider)
          .clearDensity(ingredient.id);
      if (!context.mounted || updated == null) return;
      confirmingRemoval.value = false;
      error.value = null;
      onSaved(updated);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A `Wrap`, not a `Row` with a `Spacer` (plan 0020 **G2**). In the
        // "none yet" state the caption is at its longest and the two phrasing
        // chips are at their widest, and the four together are wider than a
        // phone — 55px of debug stripe on the owner's 402pt device. A `Spacer`
        // cannot give room it has not got; a `Wrap` drops the chips onto a
        // second line and keeps the spaced-apart look on any width where they
        // still fit. Each side is one indivisible group, so the caption never
        // splits from its headline.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnsiModeChip(
                  label: 'g/ml',
                  selected: !spoonMode.value,
                  onTap: () => spoonMode.value = false,
                ),
                const SizedBox(width: 6),
                AnsiModeChip(
                  label: 'a spoon weighs…',
                  selected: spoonMode.value,
                  onTap: () => spoonMode.value = true,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (spoonMode.value)
          // Also a Wrap (G2): "1 · tsp tbsp cup · weighs · [g] · Save" is a
          // whole sentence of controls, and it had three points of slack at
          // 402pt — none at all on a 390pt phone.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              Text('1', style: ansiMono(size: 13)),
              for (final u in _spoons)
                AnsiModeChip(
                  label: u.label,
                  selected: spoon.value == u,
                  onTap: () => spoon.value = u,
                ),
              Text('weighs', style: ansiMono(size: 13)),
              SizedBox(
                width: 72,
                child: FTextField(
                  hint: 'g',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  control: FTextFieldControl.managed(
                    onChange: (v) =>
                        input.value = double.tryParse(v.text.trim()),
                  ),
                ),
              ),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: save,
                child: const Text('Save'),
              ),
            ],
          )
        else
          Row(
            children: [
              SizedBox(
                width: 110,
                child: FTextField(
                  hint: 'g/ml',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  control: FTextFieldControl.managed(
                    onChange: (v) =>
                        input.value = double.tryParse(v.text.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FButton(
                size: FButtonSizeVariant.sm,
                onPress: save,
                child: const Text('Save'),
              ),
              const Spacer(),
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
        else if (spoonMode.value && input.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              // The live equivalence: both phrasings are the same fact.
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
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// A disabled option still renders — a segment that hides its unavailable
  /// leg tells the user nothing about why (board frame d's Barcode option,
  /// which lands with lane B).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final border = !enabled
        ? AnsiColors.line
        : (selected ? AnsiColors.herb : AnsiColors.line);
    final text = !enabled
        ? AnsiColors.muted
        : (selected ? AnsiColors.herbDeep : AnsiColors.muted);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected && enabled ? AnsiColors.herbSoft : AnsiColors.surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: ansiMono(size: 10, color: text)),
      ),
    );
  }
}
