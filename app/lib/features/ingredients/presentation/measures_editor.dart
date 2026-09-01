/// The manage-measures editor (design board `pv2-b2`, step 7.7/7.8) —
/// extracted from the quantity sheet's second state so the step-8.5 flesh-out
/// form shares it rather than growing a second one, exactly as `DensityEntry`
/// was extracted before it.
///
/// What it owns: the ingredient's live measure rows with their provenance
/// read in words, deletion, and the add form (label + an amount in the
/// ingredient's **basis** unit — g for a per-100 g row, ml for per-100 ml,
/// ADR-0008). What it deliberately does **not** own is the density: a
/// volume-named label ("cup") is not a measure at all — that mapping *is* a
/// density (ADR-0008 §2) — so the form refuses it and hands the resolved
/// spoon back through [MeasuresEditor.onVolumeLabel], leaving the host to
/// point its own density entry at it. Two hosts, one door, and no second
/// density widget.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';

class MeasuresEditor extends HookConsumerWidget {
  const MeasuresEditor({
    required this.ingredient,
    required this.measures,
    required this.onDelete,
    required this.onAdded,
    required this.onVolumeLabel,
    this.autofocus = false,
    super.key,
  });

  final Ingredient ingredient;

  /// The ingredient's live measures, as the host already watches them (the
  /// quantity sheet needs the same list for its chip row).
  final List<Measure> measures;

  /// Deletion runs through the host: the quantity sheet has to reconcile a
  /// selection pointing at the row being tombstoned.
  final Future<void> Function(Measure) onDelete;

  /// A measure was authored. The quantity sheet selects it; the flesh-out
  /// form has nothing to select and ignores it.
  final ValueChanged<Measure> onAdded;

  /// A volume-named label was refused and resolved to that catalog unit —
  /// the host points its density entry at it (the "volume-label redirect").
  final ValueChanged<Unit> onVolumeLabel;

  /// The quantity sheet opens straight into this state with the keyboard up;
  /// the flesh-out form must not steal focus from a screen the user is
  /// scrolling.
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = useState('');
    final amount = useState<double?>(null);
    final error = useState<String?>(null);

    final baseLabel = ingredient.macrosBasis.baseUnit.label;
    final listed = measures.where((m) => !isVolumeUnitLabel(m.label)).toList();

    Future<void> save() async {
      final name = label.value.trim();
      final weight = amount.value;
      if (name.isEmpty) {
        error.value = 'give the measure a name';
        return;
      }
      final volumeUnit = volumeUnitFromLabel(name);
      if (volumeUnit != null) {
        // Density owns volume conversion (ADR-0008 §2: a volume-named
        // weight mapping IS a density) — offer the right door instead of
        // just refusing.
        onVolumeLabel(volumeUnit);
        error.value =
            '“$name” is a unit — that mapping is the density; '
            'enter it in the density section and the ${volumeUnit.label} '
            'chip unlocks';
        return;
      }
      if (weight == null || !(weight > 0)) {
        error.value = 'measure it: $baseLabel must be a positive number';
        return;
      }
      error.value = null;
      final Measure added;
      try {
        added = await ref
            .read(measureRepositoryProvider)
            .addMeasure(
              ingredientId: ingredient.id,
              label: name,
              amount: weight,
            );
        // The repo's validation contract IS ArgumentError (documented on
        // addMeasure) — catching it here is the point: surface the refusal
        // inline instead of crashing the host.
        // ignore: avoid_catching_errors
      } on ArgumentError catch (e) {
        // The repository validates every write path (post-7.7 review); when
        // its rules and the form's ever diverge, the refusal surfaces inline
        // instead of silently diverging (or crashing).
        if (!context.mounted) return;
        error.value = '${e.message}';
        return;
      }
      // The host can be dismissed while the write is in flight — touching
      // its state after that throws (every sibling path guards).
      if (!context.mounted) return;
      onAdded(added);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (listed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'No measures yet — name one below.',
              style: miseMono(size: 12, color: MiseColors.muted),
            ),
          )
        else
          for (final m in listed) MeasureRow(measure: m, onDelete: onDelete),
        const SizedBox(height: 12),
        _AddMeasureForm(
          label: label,
          amount: amount,
          amountHint: baseLabel,
          error: error.value,
          autofocus: autofocus,
          onSave: save,
        ),
      ],
    );
  }
}

class MeasureRow extends StatelessWidget {
  const MeasureRow({required this.measure, required this.onDelete, super.key});

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
            '${formatQuantity(measure.amount)} '
            '${measure.basis.baseUnit.label}',
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
    required this.amount,
    required this.amountHint,
    required this.error,
    required this.autofocus,
    required this.onSave,
  });

  final ValueNotifier<String> label;
  final ValueNotifier<double?> amount;

  /// The basis unit the amount is entered in ('g' — or 'ml' for a per-ml
  /// ingredient, ADR-0008 basis-aware measures).
  final String amountHint;
  final String? error;
  final bool autofocus;
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
                autofocus: autofocus,
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
                hint: amountHint,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  onChange: (v) =>
                      amount.value = double.tryParse(v.text.trim()),
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
