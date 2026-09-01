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

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/macros.dart';
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
    final canCreate =
        name.value.trim().isNotEmpty && !creating.value && !scanning.value;

    Future<void> create() async {
      creating.value = true;
      try {
        final prefill = draft.value;
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
              macrosBasis: prefill?.macrosBasis ?? MacrosBasis.perG,
            );
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
