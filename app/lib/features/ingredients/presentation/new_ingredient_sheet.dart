/// "New ingredient" — the add flow's front door (design board "Ingredients
/// manager · v1" frame (d)'s **Source** segment, and frame (e)'s barcode
/// result).
///
/// Three sources, drawn as one segment because that is where the board put
/// the barcode entry point:
/// - **Manual** — type the name, get a stub, land on the flesh-out form.
/// - **USDA FDC** — the same write. The lookup is not a client action:
///   `usda_food` never syncs to a device (ADR-0005), so the trigram match
///   runs server-side when the row uploads (plan 0020 D7 (a)) and the form's
///   "Look up in USDA" button is a re-read, not a query. The segment says so
///   rather than implying a catalogue we deliberately don't ship.
/// - **Barcode** — opens the scan surface (`scanBarcodeForDraft`, the barcode
///   module's one public door) and comes back with an [IngredientDraft]. The
///   draft **prefills and never completes** (D1): the name is a starting
///   point, the macros arrive in the basis the label read them in, a product
///   with no panel leaves them blank with the reason under them, and the row
///   still saves as a `stub` for a human to confirm (D5). Its provenance
///   (`off:<barcode>`) and the ODbL credit ride along.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import '../../recipes/presentation/format.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import 'density_entry.dart' show MiseModeChip;
import 'ingredient_detail_view.dart';
import 'macros_format.dart';

/// The add sources of frame (d).
enum NewIngredientSource { manual, usda, barcode }

/// Opens the add sheet. Resolves when it closes; on a create it has already
/// pushed the flesh-out form.
///
/// [lookup] and [cameraPane] are forwarded to the barcode surface and exist
/// for tests only — app callers pass neither.
Future<void> showNewIngredientSheet(
  BuildContext context, {
  OffLookup? lookup,
  BarcodeCameraPane? cameraPane,
}) => showFSheet<void>(
  context: context,
  side: FLayout.btt,
  mainAxisMaxRatio: null,
  useSafeArea: true,
  builder: (_) => NewIngredientSheet(lookup: lookup, cameraPane: cameraPane),
);

class NewIngredientSheet extends HookConsumerWidget {
  const NewIngredientSheet({this.lookup, this.cameraPane, super.key});

  /// Forwarded to [scanBarcodeForDraft]. Both exist for tests and are null in
  /// app code, where the defaults are a real Open Food Facts client and the
  /// real camera preview — the same hooks the barcode module documents.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = useState(NewIngredientSource.manual);
    final name = useState('');
    final draft = useState<IngredientDraft?>(null);
    final creating = useState(false);
    final scanning = useState(false);
    // The pack-size measure the board's frame (e) draws as a tick. Pre-ticked
    // because the frame draws it ticked and the row is right there above the
    // CTA — but it is never *auto*-added: no tick, no measure row.
    final addPackMeasure = useState(true);
    final packLabel = useState('pack');
    final canCreate =
        name.value.trim().isNotEmpty && !creating.value && !scanning.value;

    Future<void> create() async {
      creating.value = true;
      try {
        final prefill = draft.value;
        final basis = prefill?.macrosBasis ?? MacrosBasis.perG;
        final created = await ref
            .read(ingredientRepositoryProvider)
            .createStub(
              name.value.trim(),
              // The draft's own provenance value — `off:<barcode>` for a
              // found product, `manual` for anything else, including the
              // not-found exit (which kept the code but learnt nothing).
              source: prefill?.sourceValue ?? 'manual',
              // Absent macros stay absent: a missing panel writes no numbers
              // (D1/invariant 3), and present ones keep the basis the label
              // read them in rather than being converted (7.7).
              macros: prefill?.macros,
              macrosBasis: basis,
            );
        // The opt-in half of frame (e): the pack size becomes a real measure
        // row only because the tick is on. It rides the shared editor's
        // repository, so it is an ordinary `manual` measure from here — the
        // flesh-out form can rename it by deleting and re-adding, or bin it.
        final packAmount = _packAmountInBasis(prefill, basis);
        if (addPackMeasure.value &&
            packAmount != null &&
            packLabel.value.trim().isNotEmpty) {
          await ref
              .read(measureRepositoryProvider)
              .addMeasure(
                ingredientId: created.id,
                label: packLabel.value.trim(),
                amount: packAmount,
              );
        }
        if (!context.mounted) return;
        Navigator.of(context).pop();
        // The push outlives this sheet; nothing here waits on the form.
        unawaited(context.push(ingredientDetailRoute(created.id)));
      } finally {
        if (context.mounted) creating.value = false;
      }
    }

    Future<void> scan() async {
      if (scanning.value) return;
      // Restored on a dismissal: closing the scanner with nothing must leave
      // the segment exactly as it was found.
      final previous = source.value;
      source.value = NewIngredientSource.barcode;
      scanning.value = true;
      try {
        final scanned = await scanBarcodeForDraft(
          context,
          lookup: lookup,
          cameraPane: cameraPane,
        );
        // The sheet can be popped while the scan surface is open; touching
        // hook state after that throws.
        if (!context.mounted) return;
        if (scanned == null) {
          source.value = previous;
          return;
        }
        draft.value = scanned;
        // A starting point, not a decision — the field below stays editable,
        // and the board is explicit that yours is the name your recipes read.
        name.value = scanned.suggestedName;
      } finally {
        if (context.mounted) scanning.value = false;
      }
    }

    final prefill = draft.value;

    return Container(
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      // Scrollable since F2: a found product with a panel AND a pack-size
      // tick is taller than the sheet on a phone with the keyboard up, and a
      // fixed Column silently clips the CTA rather than saying so.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(FLucideIcons.x, size: 22),
                ),
                Expanded(
                  child: Text(
                    'New ingredient',
                    textAlign: TextAlign.center,
                    style: miseSerif(size: 20),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 16),
            Text('SOURCE', style: miseLabel()),
            const SizedBox(height: 6),
            Row(
              children: [
                MiseModeChip(
                  label: 'Manual',
                  selected: source.value == NewIngredientSource.manual,
                  onTap: () => source.value = NewIngredientSource.manual,
                ),
                const SizedBox(width: 6),
                MiseModeChip(
                  label: 'USDA FDC',
                  selected: source.value == NewIngredientSource.usda,
                  onTap: () => source.value = NewIngredientSource.usda,
                ),
                const SizedBox(width: 6),
                MiseModeChip(
                  label: 'Barcode',
                  selected: source.value == NewIngredientSource.barcode,
                  onTap: scan,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(switch (source.value) {
              NewIngredientSource.manual =>
                'Type the name your recipes will read. It saves as a stub — '
                    'fill in the macros and confirm it to make it count.',
              NewIngredientSource.usda =>
                'Same write, plus a server-side lookup: USDA FoodData Central '
                    'is matched when the row syncs up (it never leaves the '
                    'server — ADR-0005), and the form opens pre-populated. '
                    'A prefill never confirms the row for you.',
              NewIngredientSource.barcode =>
                'Scan the pack or type the number: the lookup runs on this '
                    'phone and prefills a draft. Open Food Facts is '
                    'volunteer-entered, so whatever it has no answer for stays '
                    'blank — and nothing counts until you confirm it.',
            }, style: miseMono(size: 10, color: MiseColors.muted)),

            if (prefill != null) ...[
              const SizedBox(height: 14),
              _DraftCard(draft: prefill),
            ],

            const SizedBox(height: 18),
            Text('NAME', style: miseLabel()),
            const SizedBox(height: 6),
            FTextField(
              // Re-keyed per draft: `initial` seeds the field once, so a scan
              // landing a suggested name needs a new field to seed it into.
              key: ValueKey('new-ingredient-name-${prefill?.barcode ?? ''}'),
              autofocus: true,
              hint: 'e.g. Curry leaves, fresh',
              control: FTextFieldControl.managed(
                initial: TextEditingValue(text: name.value),
                onChange: (v) => name.value = v.text,
              ),
            ),
            if (prefill != null) ...[
              const SizedBox(height: 6),
              Text(
                'the product name is a starting point — yours is the name your '
                'recipes will read',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
              if (_packAmountInBasis(prefill, prefill.macrosBasis) != null) ...[
                const SizedBox(height: 14),
                Text('ALSO ADD A MEASURE', style: miseLabel()),
                const SizedBox(height: 6),
                _PackSizeTick(
                  draft: prefill,
                  amountInBasis: _packAmountInBasis(
                    prefill,
                    prefill.macrosBasis,
                  )!,
                  ticked: addPackMeasure.value,
                  label: packLabel.value,
                  onToggle: () => addPackMeasure.value = !addPackMeasure.value,
                  onLabel: (l) => packLabel.value = l,
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Saves as a stub — confirm it on the next screen to make it '
                'count.',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
            ],
            const SizedBox(height: 14),
            FButton(
              onPress: canCreate ? create : null,
              child: Text(
                prefill == null ? 'Create & flesh out' : 'Save & review',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pack size expressed in the row's own basis unit, or null when there
/// is no pack size or it cannot be bridged honestly.
///
/// Open Food Facts' free-text `quantity` ("400 ml", "1 kg") is a ready-made
/// measure — but a measure stores its amount in the ingredient's **basis**
/// unit (ADR-0008), and a barcode carries no density. So "400 ml" on a
/// per-100 ml row converts, "1 kg" on a per-100 g row converts, and "400 ml"
/// on a per-100 g row does **not** — the tick is simply not offered rather
/// than being offered and writing a guess.
double? _packAmountInBasis(IngredientDraft? draft, MacrosBasis basis) {
  final pack = draft?.packSize;
  if (pack == null) return null;
  final inBasis = convert(
    Quantity(pack.amount, pack.unit),
    to: basis.baseUnit,
    densityGPerMl: draft?.densityGPerMl,
  );
  return switch (inBasis) {
    Ok(:final value) when value.amount > 0 => value.amount,
    Ok() || Err() => null,
  };
}

/// Frame (e)'s "Also add a measure" row: `can = 400 ml`, with a tick.
///
/// The plan's own note asks for exactly this shape — "offering it as an
/// opt-in checkbox on the barcode result, not writing it silently". The
/// label is editable because Open Food Facts' `quantity` carries the amount
/// and no noun: the board draws "can", and only the person holding the tin
/// knows whether it is a can, a jar or a pouch. It defaults to the honest
/// "pack" rather than to a guess.
class _PackSizeTick extends StatelessWidget {
  const _PackSizeTick({
    required this.draft,
    required this.amountInBasis,
    required this.ticked,
    required this.label,
    required this.onToggle,
    required this.onLabel,
  });

  final IngredientDraft draft;
  final double amountInBasis;
  final bool ticked;
  final String label;
  final VoidCallback onToggle;
  final ValueChanged<String> onLabel;

  @override
  Widget build(BuildContext context) {
    final basisLabel = draft.macrosBasis.baseUnit.label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ticked ? MiseColors.herbSoft : MiseColors.surface,
                  border: Border.all(
                    color: ticked ? MiseColors.herb : MiseColors.line,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ticked
                    ? const Icon(
                        FLucideIcons.check,
                        size: 13,
                        color: MiseColors.herbDeep,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: FTextField(
                hint: 'can',
                control: FTextFieldControl.managed(
                  initial: TextEditingValue(text: label),
                  onChange: (v) => onLabel(v.text),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '= ${formatQuantity(amountInBasis)} $basisLabel',
              style: miseMono(size: 12),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          ticked
              ? 'from the pack size — Open Food Facts’ own quantity, read '
                    'into this row’s basis. Edit it on the next screen.'
              : 'not added — the pack size is only a suggestion, and it is '
                    'not part of what makes this row count.',
          style: miseMono(size: 10, color: MiseColors.muted),
        ),
      ],
    );
  }
}

/// Frame (e)'s result card: what Open Food Facts actually said, with its
/// credit, above the name field the user still owns.
///
/// A draft that came back from the not-found exit ([DraftSource.manual] with
/// a code) has nothing to show but the code — it renders as the honest empty
/// answer rather than an empty card.
class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft});

  final IngredientDraft draft;

  @override
  Widget build(BuildContext context) {
    final attribution = draft.attribution;
    if (attribution == null) {
      return Text(
        'Nothing came back for ${draft.barcode ?? 'that code'} — the name and '
        'the macros are all a barcode was going to fill in. Type them here.',
        style: miseMono(size: 10, color: MiseColors.muted),
      );
    }
    final macros = draft.macros;
    final provenance = [
      if (draft.brand != null) draft.brand!,
      if (draft.barcode != null) 'barcode ${draft.barcode}',
      attribution,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MiseColors.surface,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FOUND · OPEN FOOD FACTS', style: miseLabel()),
          const SizedBox(height: 6),
          Text(
            draft.productName ?? draft.suggestedName,
            style: miseSans(size: 14, weight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          // The ODbL credit sits on the provenance line the frame draws it
          // on — beside the brand and the code it came with.
          Text(provenance, style: miseMono(size: 10, color: MiseColors.muted)),
          const SizedBox(height: 8),
          if (macros != null) ...[
            Text(formatMacroLine(macros), style: miseMono(size: 12)),
            const SizedBox(height: 2),
            Text(
              'panel read per 100 ${draft.macrosBasis.dbValue} — stored as '
              'the basis, not converted',
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
          ] else
            // Blank, with the reason. Never zeros: an absent panel is a fact
            // about Open Food Facts, not a nutrition figure (D1).
            Text(
              draft.macrosGap.message ??
                  'No macros came with this product — fill them in on the '
                      'next screen.',
              style: miseMono(size: 10, color: MiseColors.muted),
            ),
        ],
      ),
    );
  }
}
