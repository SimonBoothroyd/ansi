/// The macros section's **per-serving** mode (plan 0027 M-D1) — the pieces
/// both hosts draw: the serving row ("One serving is 14 g · 1 Tbsp on the
/// pack") and the stored-line preview under the four fields.
///
/// The flesh-out form owns the mode; the New-ingredient sheet draws the row
/// under a barcode draft whose panel came per serving (M-D5). The arithmetic
/// is [Macros.per100From] and the row stores per 100 like every row — this
/// file is only how the person sees the derivation before Save (M-D3).
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../recipes/presentation/format.dart';
import '../barcode/barcode_add.dart' show DraftServingPanel;
import 'density_entry.dart' show AnsiModeChip;
import 'macros_format.dart';

/// The serving a per-serving panel describes, as typed: an amount in the
/// basis unit, and — on the form only — what the pack calls it.
@immutable
class ServingDraft {
  const ServingDraft({this.amountText = '', this.name = '', this.packSays});

  /// The row a scanned per-serving panel seeds (M-D5): the amount when OFF
  /// had a number, and the pack's own words with any trailing parenthetical
  /// weight dropped ("2 Tbsp (32 g)" → "2 Tbsp"). A serving size that is
  /// only a weight ("32.0g") names nothing and seeds no name; one OFF gave
  /// no number for is kept whole as [packSays], beside the empty amount.
  factory ServingDraft.fromPanel(DraftServingPanel panel) {
    final amount = panel.servingAmount;
    var name = (panel.servingSize ?? '')
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .trim();
    if (RegExp(r'^\d[\d.,]*\s*[a-zA-Z]{0,2}$').hasMatch(name)) name = '';
    return ServingDraft(
      amountText: amount == null ? '' : formatQuantity(amount),
      name: name,
      packSays: amount == null ? panel.servingSize : null,
    );
  }

  /// The amount field's text. [amount] is its positive parse, or null.
  final String amountText;

  /// What the pack calls one serving ("1 tbsp", "1 slice") — the M-D2 offer
  /// reads this. Empty when nothing was typed or seeded.
  final String name;

  /// OFF's free-text `serving_size` when it carried no number, kept to show
  /// beside the empty amount ("the pack says “1 Tbsp (14 g)” — type the
  /// weight"). Never parsed into the amount.
  final String? packSays;

  /// The serving amount, or null unless it is a positive finite number.
  double? get amount {
    final v = double.tryParse(amountText.trim());
    return v != null && v.isFinite && v > 0 ? v : null;
  }

  ServingDraft copyWith({String? amountText, String? name}) => ServingDraft(
    amountText: amountText ?? this.amountText,
    name: name ?? this.name,
    packSays: packSays,
  );

  @override
  bool operator ==(Object other) =>
      other is ServingDraft &&
      other.amountText == amountText &&
      other.name == name &&
      other.packSays == packSays;

  @override
  int get hashCode => Object.hash(amountText, name, packSays);
}

/// "One serving is [14] g · ml [as the pack calls it]" (board frame a).
///
/// The unit chips set the row's **basis** — a 14 g serving reads per 100 g,
/// a 240 ml one per 100 ml — so there is one stored fact and the serving
/// names it. The name field is the form's (M-D2) and is hidden when
/// [withName] is false. Each field reports its own text rather than a whole
/// draft, so the host folds it into whatever it holds *now* — two fields
/// typed between rebuilds cannot lose each other.
class ServingRow extends StatelessWidget {
  const ServingRow({
    required this.draft,
    required this.basis,
    required this.onAmount,
    required this.onBasis,
    this.onName,
    super.key,
  });

  final ServingDraft draft;
  final MacrosBasis basis;
  final ValueChanged<String> onAmount;
  final ValueChanged<MacrosBasis> onBasis;

  /// Null hides the name field (the add sheet makes no M-D2 offer).
  final ValueChanged<String>? onName;

  bool get withName => onName != null;

  @override
  Widget build(BuildContext context) {
    final packSays = draft.packSays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('One serving is', style: ansiMono(size: 11)),
        const SizedBox(height: 6),
        // A Wrap (plan 0020 G2): amount · g · ml · the name field is wider
        // than a phone with the keyboard up, and a Row cannot give room it
        // has not got.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            SizedBox(
              width: 72,
              child: FTextField(
                key: const ValueKey('serving-amount'),
                hint: basis.baseUnit.label,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(text: draft.amountText),
                  onChange: (v) => onAmount(v.text),
                ),
              ),
            ),
            AnsiModeChip(
              label: 'g',
              selected: basis == MacrosBasis.perG,
              onTap: () => onBasis(MacrosBasis.perG),
            ),
            AnsiModeChip(
              label: 'ml',
              selected: basis == MacrosBasis.perMl,
              onTap: () => onBasis(MacrosBasis.perMl),
            ),
            if (withName)
              SizedBox(
                width: 170,
                child: FTextField(
                  key: const ValueKey('serving-name'),
                  hint: 'as the pack calls it — “1 tbsp”',
                  control: FTextFieldControl.managed(
                    initial: TextEditingValue(text: draft.name),
                    onChange: (v) => onName!(v.text),
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            draft.amount != null
                ? 'the four fields take the label’s figures as printed, per '
                      'this serving'
                : packSays != null
                ? 'the pack says “$packSays” — type the serving weight'
                : 'type the serving weight from the pack',
            style: ansiMono(
              size: 10,
              color: draft.amount != null ? AnsiColors.muted : AnsiColors.aging,
            ),
          ),
        ),
      ],
    );
  }
}

/// The muted line under the four fields (M-D1's preview, M-D3's note): what
/// the row will store, derived live from the serving and the printed four.
class StoredPer100Line extends StatelessWidget {
  const StoredPer100Line({
    required this.basis,
    required this.serving,
    required this.printed,
    super.key,
  });

  final MacrosBasis basis;
  final ServingDraft serving;

  /// The four fields as parsed, or null while blank or incoherent.
  final Macros? printed;

  @override
  Widget build(BuildContext context) {
    final amount = serving.amount;
    final printed = this.printed;
    final stored = printed == null || amount == null
        ? null
        : Macros.per100From(serving: amount, basis: basis, printed: printed);
    final String text;
    if (printed == null) {
      text = 'stored per 100 ${basis.dbValue} — once the four are in';
    } else if (stored == null) {
      text = 'stored per 100 ${basis.dbValue}: needs the serving weight';
    } else {
      // M-D3, said once, at entry: the label rounded to whole grams and the
      // scale factor carries that rounding with it.
      text =
          'stored per 100 ${basis.dbValue}: ${formatMacroLine(stored)}\n'
          'from a ${formatQuantity(amount)} ${basis.baseUnit.label} serving — '
          'the label’s rounding scales with it';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: ansiMono(size: 10, color: AnsiColors.muted)),
    );
  }
}
