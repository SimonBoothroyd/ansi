/// The piece-weight entry — the count-side twin of `DensityEntry` (ADR-0015).
///
/// A density says what a volume of this weighs and unlocks the volume units;
/// a **piece weight** says what ONE of this weighs and unlocks `piece`. Both
/// are one number on the row, both are entered as one sentence — "1 piece
/// weighs `[__]` g" — and both fold to a headline once stated, because each
/// is entered once and read often.
///
/// It is drawn only where it means something: a row whose default unit is a
/// count (owner's ruling — `piece` shows only where the default is `piece`).
/// A count default with no weight is a stranded default, named by the host's
/// own flag and refused at Save; this widget is where that flag is cleared.
///
/// Like `DensityEntry`, **the host decides when the number lands**: the
/// flesh-out form holds it in its draft until Save, the quantity sheet's
/// manage state writes it on tap. The widget validates and reports; it knows
/// no repository.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/number_format.dart';
import '../../../shared/inline_amount_field.dart';
import '../domain/allowed_units.dart';
import '../domain/ingredient.dart';
import 'ingredient_facts.dart' show pieceWeightSourceSuffix;

class PieceWeightEntry extends HookWidget {
  const PieceWeightEntry({
    required this.ingredient,
    required this.onSave,
    required this.onRemove,
    this.saveLabel = 'Save',
    this.headline = 'PIECE WEIGHT',
    super.key,
  });

  final Ingredient ingredient;

  /// The amount, in the row's basis unit, once the sentence is valid. Returns
  /// whether it landed — all this widget needs to clear its own error state.
  final Future<bool> Function(double amount) onSave;

  /// The mirror write: the number goes and `piece` locks again in the same
  /// write. The host lands it.
  final Future<bool> Function() onRemove;

  /// What the inline button says: `Add` on the form (the tap only drafts),
  /// `Save` on the sheet (the tap writes).
  final String saveLabel;

  final String headline;

  /// The same leading space every micro-label in the form's groups carries.
  static const _leadingSpace = 20.0;

  @override
  Widget build(BuildContext context) {
    final input = useState<double?>(null);
    final error = useState<String?>(null);
    final confirmingRemoval = useState(false);
    // A stated weight folds; a row with none opens on the sentence, because
    // there the entry IS the subject. Seeded once, as the density entry is.
    final open = useState(ingredient.pieceBasisAmount == null);

    final weight = ingredient.pieceBasisAmount;
    final source = ingredient.pieceSource;
    final baseLabel = ingredient.macrosBasis.baseUnit.label;
    final expanded = open.value || weight == null;

    Future<void> save() async {
      final v = input.value;
      if (v == null || !(v > 0) || !v.isFinite) {
        error.value = 'weigh one: $baseLabel per piece must be positive';
        return;
      }
      error.value = null;
      final landed = await onSave(v);
      if (!context.mounted || !landed) return;
      confirmingRemoval.value = false;
      // The fold is where the section OPENS next time, never something that
      // happens under your hands (the density entry's rule).
    }

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
        Padding(
          padding: const EdgeInsets.only(top: _leadingSpace),
          child: Row(
            children: [
              Text(headline, style: ansiLabel()),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  weight == null
                      ? 'none yet — what one of these weighs'
                      : '${formatAmount(weight)} $baseLabel'
                            '${pieceWeightSourceSuffix(source)}',
                  style: ansiMono(
                    size: 10,
                    color: weight == null
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
          // One sentence on one run: "1 piece weighs [__] g [Add]".
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            runSpacing: 6,
            children: [
              Text('1 piece weighs', style: ansiMono(size: 12)),
              InlineAmountField(
                key: const ValueKey('piece-weight-field'),
                fractions: true,
                onChange: (t) => input.value = parseAmount(t),
                onSubmit: save,
              ),
              Text(baseLabel, style: ansiMono(size: 12)),
              FButton(
                key: const ValueKey('piece-weight-save'),
                size: FButtonSizeVariant.xs,
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
          if (weight != null)
            _RemovePieceWeight(
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
            ),
        ],
      ],
    );
  }
}

/// Deleting the stored piece weight — `piece` locks again in the same write.
/// Asks first, naming the consequence rather than "are you sure".
class _RemovePieceWeight extends StatelessWidget {
  const _RemovePieceWeight({
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
              'remove the piece weight',
              style: ansiMono(size: 10, color: AnsiColors.gone),
            ),
          ),
        ),
      );
    }
    final stripped = pieceStrippedUnits(ingredient);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stripped.isEmpty
                ? 'Remove it? Nothing about what a line may say changes.'
                : 'Remove it? ${stripped.map((u) => u.label).join(' · ')} '
                      'locks again, and a count of this stops joining totals.',
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
