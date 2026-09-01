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
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../data/ingredient_providers.dart';
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
      onSaved(updated);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(headline, style: miseLabel()),
            const SizedBox(width: 8),
            Text(
              density == null
                  ? 'none yet — unlocks volume⇄weight'
                  : '${formatDensity(density)} g/ml',
              style: miseMono(
                size: 10,
                color: density == null ? MiseColors.muted : MiseColors.herbDeep,
              ),
            ),
            const Spacer(),
            MiseModeChip(
              label: 'g/ml',
              selected: !spoonMode.value,
              onTap: () => spoonMode.value = false,
            ),
            const SizedBox(width: 6),
            MiseModeChip(
              label: 'a spoon weighs…',
              selected: spoonMode.value,
              onTap: () => spoonMode.value = true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (spoonMode.value)
          Row(
            children: [
              Text('1', style: miseMono(size: 13)),
              const SizedBox(width: 6),
              for (final u in _spoons) ...[
                MiseModeChip(
                  label: u.label,
                  selected: spoon.value == u,
                  onTap: () => spoon.value = u,
                ),
                const SizedBox(width: 6),
              ],
              Text('weighs', style: miseMono(size: 13)),
              const SizedBox(width: 8),
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
              const SizedBox(width: 8),
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
        if (error.value != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error.value!,
              style: miseMono(size: 10, color: MiseColors.gone),
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
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
          ),
      ],
    );
  }
}

/// The small pill that toggles one of a mutually exclusive pair/row — the
/// density phrasings, the spoon choice, the form's basis and source segments.
class MiseModeChip extends StatelessWidget {
  const MiseModeChip({
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
        ? MiseColors.line
        : (selected ? MiseColors.herb : MiseColors.line);
    final text = !enabled
        ? MiseColors.muted
        : (selected ? MiseColors.herbDeep : MiseColors.muted);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected && enabled ? MiseColors.herbSoft : MiseColors.surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: miseMono(size: 10, color: text)),
      ),
    );
  }
}
