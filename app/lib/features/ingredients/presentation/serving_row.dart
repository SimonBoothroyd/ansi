/// The macros section's per-serving mode: the serving row ("One serving is 1
/// cup"), the derivation line under the four fields, and, on a scanned per-100
/// row, the line that checks the pack's two readings against each other.
///
/// The serving's unit family sets the row's basis: mass stores per 100 g,
/// volume per 100 ml, so a volume serving needs no density. The arithmetic is
/// [Macros.per100From]'s; this file only shows the derivation before Save.
library;

import 'package:flutter/widgets.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../../../shared/amount_and_unit.dart';
import '../../../shared/format.dart';
import '../domain/serving_measure.dart';
import 'macros_format.dart';

/// The units a serving may say: the catalog's mass and volume families, in
/// catalog order. Count and imprecise words are not servings.
const kServingUnits = <Unit>[
  g, kg, oz, lb, //
  ml, l, tsp, tbsp, flOz, cup, pint, quart,
];

/// The serving as typed: an amount, and the unit the pack says it in.
@immutable
class ServingDraft {
  const ServingDraft({
    this.amountText = '',
    this.unit = g,
    this.packPrinted,
    this.packPrintedText,
  });

  /// The amount field's text. [amount] is its positive parse, or null.
  final String amountText;

  /// The unit the picker holds. It decides the row's [basis], so moving it
  /// moves the stored fact's dimension with it.
  final Unit unit;

  /// A scanned per-100 label's own per-serving figures, kept only for the
  /// cross-check. Never entered or stored.
  final Macros? packPrinted;

  /// The pack's `serving_size` verbatim ("1 Cup (237 mL)"), quoted in that
  /// same line.
  final String? packPrintedText;

  /// The serving amount, or null unless it is a positive finite number.
  double? get amount {
    final v = parseAmount(amountText);
    return v != null && v.isFinite && v > 0 ? v : null;
  }

  /// The basis this serving names: a mass serving is per 100 g, a volume one
  /// per 100 ml. One fact, said by the unit the person picked.
  MacrosBasis get basis =>
      unit.family == UnitFamily.volume ? MacrosBasis.perMl : MacrosBasis.perG;

  /// The serving in [basis]'s base unit — `1 cup` → 236.59 ml — through the
  /// catalog alone. Null while the amount is blank or not positive.
  double? get amountInBasis {
    final a = amount;
    if (a == null) return null;
    return switch (convert(Quantity(a, unit), to: basis.baseUnit)) {
      Ok(:final value) when value.amount > 0 => value.amount,
      Ok() || Err() => null,
    };
  }

  /// `1 cup` — the serving as the pack says it.
  String get phrase => amount == null ? '' : formatServingPhrase(amount!, unit);

  /// `1 cup = 236.59 ml`: the conversion the derivation line cites. Empty for a
  /// serving already in its base unit.
  String get conversion {
    final inBasis = amountInBasis;
    if (inBasis == null || unit == basis.baseUnit) return '';
    return '$phrase = ${formatQuantityIn(inBasis, basis.baseUnit)} '
        '${basis.baseUnit.label}';
  }

  ServingDraft copyWith({String? amountText, Unit? unit}) => ServingDraft(
    amountText: amountText ?? this.amountText,
    unit: unit ?? this.unit,
    packPrinted: packPrinted,
    packPrintedText: packPrintedText,
  );

  @override
  bool operator ==(Object other) =>
      other is ServingDraft &&
      other.amountText == amountText &&
      other.unit == unit &&
      other.packPrinted == packPrinted &&
      other.packPrintedText == packPrintedText;

  @override
  int get hashCode =>
      Object.hash(amountText, unit, packPrinted, packPrintedText);
}

/// "One serving is `1` `cup`": the whole row. The unit is one chip
/// ([AmountAndUnitField]) with the full offer a tap away, since twelve chips
/// would not fit a phone row. The unit sets the row's basis. Each field reports
/// its own value, so the host folds it into whatever it holds now.
class ServingRow extends StatelessWidget {
  const ServingRow({
    required this.draft,
    required this.onAmount,
    required this.onUnit,
    super.key,
  });

  final ServingDraft draft;
  final ValueChanged<String> onAmount;
  final ValueChanged<Unit> onUnit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text('One serving is', style: ansiMono(size: 11)),
      const SizedBox(width: 8),
      // The shared amount-and-unit control (`shared/amount_and_unit.dart`).
      AmountAndUnitField(
        amountKey: const ValueKey('serving-amount'),
        unitKey: const ValueKey('serving-unit'),
        amountWidth: 52,
        amount: draft.amountText,
        unit: draft.unit,
        units: kServingUnits,
        onAmount: onAmount,
        onUnit: onUnit,
      ),
    ],
  );
}

/// The muted line under the four fields in per-serving mode: what the row will
/// store, derived live. `stored per 100 ml · 46 kcal · 0.4P 2.1F 7.2C · from 1
/// cup = 236.59 ml`.
class StoredPer100Line extends StatelessWidget {
  const StoredPer100Line({
    required this.serving,
    required this.printed,
    super.key,
  });

  final ServingDraft serving;

  /// The four fields as parsed, or null while blank or incoherent.
  final Macros? printed;

  @override
  Widget build(BuildContext context) {
    final basis = serving.basis;
    final inBasis = serving.amountInBasis;
    final printed = this.printed;
    final stored = printed == null || inBasis == null
        ? null
        : Macros.per100From(serving: inBasis, basis: basis, printed: printed);
    final String text;
    if (printed == null) {
      text = 'stored per 100 ${basis.dbValue} — once the four are in';
    } else if (stored == null) {
      text = 'stored per 100 ${basis.dbValue}: needs the serving amount';
    } else {
      final from = serving.conversion;
      text =
          'stored per 100 ${basis.dbValue} · ${formatMacroLine(stored)}'
          '${from.isEmpty ? '' : ' · from $from'}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: ansiMono(size: 10, color: AnsiColors.muted)),
    );
  }
}

/// The line a scanned per-100 row shows in [ScannedServingLine]'s slot when the
/// payload named no serving: it says per-serving mode exists. It goes once the
/// mode moves or a figure is typed.
class ScannedPerServingNudge extends StatelessWidget {
  const ScannedPerServingNudge({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      'the pack printed it per serving? switch to per serving and type it '
      'as read',
      style: ansiMono(size: 10, color: AnsiColors.muted),
    ),
  );
}

/// The line under a scanned row's figures: what the pack printed per serving,
/// what that is per 100, and whether the two agree. Drawn only when both
/// readings exist; the host says which one is in the fields. Nothing is
/// corrected.
class ScannedServingLine extends StatelessWidget {
  const ScannedServingLine({
    required this.serving,
    required this.printed,
    required this.per100,
    super.key,
  });

  final ServingDraft serving;

  /// The label's figures for one serving.
  final Macros? printed;

  /// The label's own per-100 column, which [printed] is checked against.
  final Macros? per100;

  /// The gap allowed before the line says the readings differ. A label rounds
  /// its per-serving column, so a percent of the per-100 figure is the pack's
  /// own rounding.
  static const _tolerance = 0.01;

  @override
  Widget build(BuildContext context) {
    final printed = this.printed;
    final per100 = this.per100;
    final inBasis = serving.amountInBasis;
    if (printed == null || per100 == null || inBasis == null) {
      return const SizedBox.shrink();
    }
    final implied = Macros.per100From(
      serving: inBasis,
      basis: serving.basis,
      printed: printed,
    );
    if (implied == null) return const SizedBox.shrink();
    // Every figure is compared, not the calories alone: one mistyped gram
    // figure leaves the kcal agreeing. Fibre joins only when both columns state
    // it ([Macros.fiber]).
    final impliedFiber = implied.fiber;
    final heldFiber = per100.fiber;
    final differs = [
      for (final (label, a, b) in [
        ('kcal', implied.kcal, per100.kcal),
        ('protein', implied.protein, per100.protein),
        ('carb', implied.carb, per100.carb),
        ('fat', implied.fat, per100.fat),
        if (impliedFiber != null && heldFiber != null)
          ('fibre', impliedFiber, heldFiber),
      ])
        if ((a - b).abs() > _slack(label, b)) _gap(label, a, b),
    ];
    final says = serving.packPrintedText ?? serving.phrase;
    final verdict = differs.isEmpty
        ? 'these agree'
        : 'these differ: ${differs.join(' · ')}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'the pack prints ${formatKcal(printed.kcal)} kcal per $says · '
        'that is ${formatKcal(implied.kcal)} per 100 '
        '${serving.basis.dbValue} — $verdict',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }

  /// A percent of the held figure, with a floor a label's rounding can reach:
  /// whole kcal, and 0.5 g on a 28 g serving is ~1.8 g per 100.
  static double _slack(String label, double held) =>
      (held * _tolerance).clamp(label == 'kcal' ? 2.0 : 0.3, double.infinity);

  static String _gap(String label, double printed, double held) {
    final show = label == 'kcal' ? formatKcal : formatGrams;
    return '$label ${show(printed)} printed, ${show(held)} held';
  }
}
