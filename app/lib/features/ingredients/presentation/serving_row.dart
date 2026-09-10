/// The macros section's **per-serving** mode: the serving row ("One serving is
/// 1 cup"), the derivation line under the four fields, and — on a scanned
/// per-100 row — the line that checks the pack's two readings against each
/// other.
///
/// The row takes an amount and **any kitchen unit**, and the unit's family is
/// the row's basis: a mass serving stores per 100 g, a volume serving per
/// 100 ml. A volume serving therefore needs no density at all — `2 tbsp` is
/// 29.57 ml by the catalog, exactly. Density is the density section's subject
/// and is stated nowhere else.
///
/// The arithmetic is [Macros.per100From]'s and the row stores per 100 like
/// every row — this file is only how the person sees the derivation before
/// Save.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../../shared/format.dart';
import '../domain/serving_measure.dart';
import 'macros_format.dart';

/// The units a serving line may say — the mass and volume families of the
/// catalog, in the catalog's own order. Count and imprecise words are not
/// servings: a label prints a weight or a measure, and "1 pinch" is not a
/// panel.
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

  /// A scanned per-100 label's own per-serving figures, kept only to check
  /// the pack's two readings against each other. Never entered into a field
  /// and never stored.
  final Macros? packPrinted;

  /// The pack's `serving_size` verbatim ("1 Cup (237 mL)"), quoted in that
  /// same line.
  final String? packPrintedText;

  /// The serving amount, or null unless it is a positive finite number.
  double? get amount {
    final v = double.tryParse(amountText.trim());
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

  /// `1 cup = 236.59 ml` — the conversion the derivation line cites. Empty
  /// for a serving already in its own base unit, where there is nothing to
  /// convert and the line would only repeat itself.
  String get conversion {
    final inBasis = amountInBasis;
    if (inBasis == null || unit == basis.baseUnit) return '';
    return '$phrase = ${formatQuantity(inBasis)} ${basis.baseUnit.label}';
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

/// "One serving is `[1]` `[cup ▾]`" — the whole row.
///
/// **A picker, not chips.** Twelve kitchen units is three runs of chips at
/// 402 pt and one control as a select, and the sentence has to stay a
/// sentence. The form already uses this idiom for the category, so the row
/// borrows a shape the page has rather than inventing one.
///
/// The unit sets the row's **basis**, so the admission chips and the stored
/// dimension follow it live. Each field reports its own value rather than a
/// whole draft, so the host folds it into whatever it holds *now*.
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
      SizedBox(
        width: 64,
        child: FTextField(
          key: const ValueKey('serving-amount'),
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          control: FTextFieldControl.managed(
            initial: TextEditingValue(text: draft.amountText),
            onChange: (v) => onAmount(v.text),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FSelect<Unit>.rich(
          key: const ValueKey('serving-unit'),
          format: (u) => u.label,
          control: FSelectControl<Unit>.lifted(
            value: draft.unit,
            onChange: (u) => onUnit(u ?? draft.unit),
          ),
          children: [
            for (final u in kServingUnits)
              FSelectItem(title: Text(u.label), value: u),
          ],
        ),
      ),
    ],
  );
}

/// The one muted line under the four fields in per-serving mode: what the row
/// will store, derived live from the serving and the figures as printed.
///
/// `stored per 100 ml · 46 kcal · 0.4P 2.1F 7.2C · from 1 cup = 236.59 ml`.
/// It is a derivation and reads like one — the fields keep the label's own
/// numbers, and this says what the app made of them.
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
          'stored per 100 ${basis.dbValue} · ${formatMacroLineFine(stored)}'
          '${from.isEmpty ? '' : ' · from $from'}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: ansiMono(size: 10, color: AnsiColors.muted)),
    );
  }
}

/// The line under a **scanned per-100** row's figures: what the pack printed
/// per serving, what that is per 100, and whether the two agree.
///
/// Drawn only when both readings exist — the label's per-serving figures and
/// the panel in the fields. Nothing is invented and nothing is corrected: the
/// pack printed both columns and the app says whether they say the same thing.
class ScannedServingLine extends StatelessWidget {
  const ScannedServingLine({
    required this.serving,
    required this.per100,
    super.key,
  });

  final ServingDraft serving;

  /// The four fields as parsed — the per-100 panel the scan landed.
  final Macros? per100;

  /// The gap either reading is allowed before the line says they differ. A
  /// label rounds its per-serving column to whole kcal, so a percent of the
  /// per-100 figure is the rounding the pack itself carries, not a
  /// disagreement.
  static const _tolerance = 0.01;

  @override
  Widget build(BuildContext context) {
    final printed = serving.packPrinted;
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
    // All four are compared, not the calories alone: a contributor who
    // mistyped one gram figure leaves the kcal agreeing and the carb wrong,
    // and that is exactly the error a person holding the pack can catch.
    final differs = [
      for (final (label, a, b) in [
        ('kcal', implied.kcal, per100.kcal),
        ('protein', implied.protein, per100.protein),
        ('carb', implied.carb, per100.carb),
        ('fat', implied.fat, per100.fat),
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
        'the pack prints ${formatQuantity(printed.kcal)} kcal per $says · '
        'that is ${formatQuantity(_round1(implied.kcal))} per 100 '
        '${serving.basis.dbValue} — $verdict',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }

  /// A percent of the held figure, with a floor a label's own rounding can
  /// reach: whole kcal, and grams printed to the nearest 0.5 g on a 28 g
  /// serving are ~1.8 g per 100.
  static double _slack(String label, double held) =>
      (held * _tolerance).clamp(label == 'kcal' ? 2.0 : 0.3, double.infinity);

  static String _gap(String label, double printed, double held) =>
      '$label ${formatQuantity(_round1(printed))} printed, '
      '${formatQuantity(_round1(held))} held';

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}
