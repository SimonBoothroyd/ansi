/// The barcode result card: what Open Food Facts actually said, with its
/// credit, and what of it was left alone because a human had already filled
/// that field in.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/format.dart';
import '../barcode/barcode_add.dart';
import '../domain/apply_draft.dart';
import 'macros_format.dart';

class DraftCard extends StatelessWidget {
  const DraftCard({required this.draft, this.skipped = const [], super.key});

  final IngredientDraft draft;

  /// What [applyDraft] left alone. Named on the card so the numbers it shows
  /// and the fields below it cannot silently disagree.
  final List<DraftSkip> skipped;

  @override
  Widget build(BuildContext context) {
    final attribution = draft.attribution;
    // A draft that came back from the not-found exit has nothing to show, so
    // it says so rather than drawing an empty card.
    if (attribution == null) {
      return Text(
        'Not found. Enter the name and macros.',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      );
    }
    final macros = draft.macros;
    final serving = draft.servingPanel;
    final provenance = [
      if (draft.brand != null) draft.brand!,
      if (draft.barcode != null) 'barcode ${draft.barcode}',
      attribution,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AnsiColors.surface,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FOUND · OPEN FOOD FACTS', style: ansiLabel()),
          const SizedBox(height: 6),
          Text(
            draft.productName ?? draft.suggestedName,
            style: ansiSans(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          // The ODbL credit sits on the provenance line the frame draws it
          // on — beside the brand and the code it came with.
          Text(provenance, style: ansiMono(size: 10, color: AnsiColors.muted)),
          const SizedBox(height: 8),
          if (macros != null) ...[
            Text(formatMacroLine(macros), style: ansiMono(size: 12)),
            const SizedBox(height: 2),
            Text(
              'per 100 ${draft.macrosBasis.dbValue}',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ] else if (serving != null) ...[
            // A per-serving panel: the four figures as printed, and what OFF
            // knows about the serving. The host derives the per-100 reading.
            Text(formatMacroLine(serving.printed), style: ansiMono(size: 12)),
            const SizedBox(height: 2),
            Text(
              _servingLine(serving),
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ] else
            // Blank, with the reason. Never zeros: an absent panel is a fact
            // about Open Food Facts, not a nutrition figure.
            Text(
              draft.macrosGap.message ?? 'No macros found',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'kept: ${skipped.map((s) => s.reason).join(' · ')}',
              style: ansiMono(size: 10, color: AnsiColors.aging),
            ),
          ],
        ],
      ),
    );
  }

  /// Under the printed four: what OFF knows about the serving, and whether
  /// the amount still has to be typed.
  static String _servingLine(DraftServingPanel serving) {
    final amount = serving.servingAmount;
    if (amount == null) return 'per serving. Enter the serving weight.';
    final unit = serving.servingBasis!.baseUnit;
    return 'per serving of ${formatQuantityIn(amount, unit)} ${unit.label}';
  }
}
