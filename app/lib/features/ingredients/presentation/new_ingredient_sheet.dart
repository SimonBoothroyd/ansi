/// "New ingredient" — the add flow's front door (design board "Ingredients
/// manager · v1" frame (d)'s **Source** segment, and frame (e)'s barcode
/// result), and since plan 0025 D3 the ONLY door: every add-new in the app —
/// the manager's ＋, the editor picker's footer, the shopping top-up, the
/// import review's create-new — opens this sheet, so there is one answer to
/// "what does creating an ingredient mean" (plan 0020 D7b).
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
///   draft **prefills and never completes** (D1): it lands through
///   [applyDraft] — the rule the flesh-out form's own scan shares — so a name
///   already typed here stays, the macros arrive in the basis the label read
///   them in, a product with no panel leaves them blank with the reason under
///   them, and the row still saves as a `stub` for a human to confirm (D5).
///   Its provenance (`off:<barcode>`) and the ODbL credit ride along.
///
/// **The sheet hands the row back; the host decides where to go.** It pops
/// with the created [Ingredient] and pushes nothing. The manager's list pushes
/// the flesh-out form and moves on; a picker pushes the same form, *awaits*
/// its pop, and only then resolves — so the quantity sheet that follows opens
/// on the units the form just set. What no host may do is skip the form: the
/// row is a stub until a human confirms it, and the form is on the way, not a
/// detour.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/write.dart';
import '../../recipes/presentation/format.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../data/usda_enrichment.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import 'density_entry.dart' show AnsiModeChip;
import 'draft_card.dart';

/// The add sources of frame (d).
enum NewIngredientSource { manual, usda, barcode }

/// Opens the add sheet. Resolves with the created row, or null when the sheet
/// was closed without one. It pushes nothing: the caller lands the row on the
/// flesh-out form (see the library doc).
///
/// [initialName] prefills the name field — a picker passes what was typed
/// into its search, so "curry leaves" becomes the row without retyping.
///
/// [lookup] and [cameraPane] are forwarded to the barcode surface and exist
/// for tests only — app callers pass neither.
Future<Ingredient?> showNewIngredientSheet(
  BuildContext context, {
  String initialName = '',
  OffLookup? lookup,
  BarcodeCameraPane? cameraPane,
}) => showAnsiSheet<Ingredient>(
  context: context,
  builder: (_) => NewIngredientSheet(
    initialName: initialName,
    lookup: lookup,
    cameraPane: cameraPane,
  ),
);

class NewIngredientSheet extends HookConsumerWidget {
  const NewIngredientSheet({
    this.initialName = '',
    this.lookup,
    this.cameraPane,
    super.key,
  });

  /// What the name field opens with. Yours to change before it becomes a row.
  final String initialName;

  /// Forwarded to [scanBarcodeForDraft]. Both exist for tests and are null in
  /// app code, where the defaults are a real Open Food Facts client and the
  /// real camera preview — the same hooks the barcode module documents.
  final OffLookup? lookup;
  final BarcodeCameraPane? cameraPane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = useState(NewIngredientSource.manual);
    final name = useState(initialName.trim());
    final draft = useState<IngredientDraft?>(null);
    // What the last scan decided — the values [create] writes, and the list
    // of fields it left alone that the card names.
    final applied = useState<DraftApplication?>(null);
    // The name the last scan put in the field. A field still reading exactly
    // that is the draft's, not the person's, so the next scan may replace it
    // — the same "untouched is measured against what was seeded" rule the
    // form's macro fields keep (G1).
    final seededName = useRef<String?>(null);
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
        final landing = applied.value;
        // One guard over the whole creation: the row, its opt-in pack measure
        // and the enrichment are one act to the person who tapped Create, so
        // they get one honest answer if any of it fails.
        final created = await ref.write(
          context,
          'add ${name.value.trim()}',
          () async {
            final row = await ref
                .read(ingredientRepositoryProvider)
                .createStub(
                  name.value.trim(),
                  // The draft's own provenance value — `off:<barcode>` for a
                  // found product, `manual` for anything else, including the
                  // not-found exit (which kept the code but learnt nothing).
                  source: landing?.source ?? 'manual',
                  // Absent macros stay absent: a missing panel writes no
                  // numbers (D1/invariant 3), and present ones keep the basis
                  // the label read them in rather than being converted (7.7).
                  macros: landing?.macros,
                  macrosBasis: landing?.macrosBasis ?? MacrosBasis.perG,
                );
            // The opt-in half of frame (e): the pack size becomes a real
            // measure row only because the tick is on. It rides the shared
            // editor's repository, so it is an ordinary `manual` measure from
            // here — the flesh-out form can rename it by deleting and
            // re-adding, or bin it.
            final pack = landing?.packMeasure;
            if (addPackMeasure.value &&
                pack != null &&
                packLabel.value.trim().isNotEmpty) {
              await ref
                  .read(measureRepositoryProvider)
                  .addMeasure(
                    ingredientId: row.id,
                    label: packLabel.value.trim(),
                    amount: pack.amountInBasis,
                  );
            }
            // D7b: born enriched. The probe runs BEFORE the form opens, so a
            // new ingredient arrives with whatever USDA had rather than
            // acquiring it a few seconds later if you are still looking.
            // Offline it answers null within its own short timeout and the
            // 0014/0015 trigger picks the row up on upload — so this is a
            // beat, never a stall, and never an error.
            //
            // Only a manual draft is probed. A barcode row carries Open Food
            // Facts provenance (`off:<barcode>`) and the probe's source stamp
            // would replace it with a USDA id — the same exclusion the server
            // trigger's WHEN clause makes.
            if (prefill?.source != DraftSource.barcode) {
              final enriched = await enrichFromUsda(
                row,
                probe: ref.read(usdaProbeProvider),
                repository: ref.read(ingredientRepositoryProvider),
              );
              return enriched.row ?? row;
            }
            return row;
          },
        );
        if (created == null || !context.mounted) return;
        // The host lands it on the form. Nothing here waits, and nothing
        // here navigates — a sheet that pushed would put the page under a
        // picker still open beneath it.
        Navigator.of(context).pop(created);
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
          // An explicit parameter still wins (the widget tests pass one).
          // Otherwise the app's own client arrives by provider, which is the
          // seam `make test-sim` overrides — the sheet is opened from inside a
          // navigation stack no caller can thread a parameter through.
          lookup: lookup ?? ref.read(offLookupProvider),
          cameraPane: cameraPane,
        );
        // The sheet can be popped while the scan surface is open; touching
        // hook state after that throws.
        if (!context.mounted) return;
        if (scanned == null) {
          source.value = previous;
          return;
        }
        final landing = applyDraft(
          scanned,
          // A field the last scan seeded is free again; a name the person
          // typed (or the picker carried in) is theirs.
          target: DraftTarget(
            name: name.value == seededName.value ? '' : name.value,
          ),
        );
        draft.value = scanned;
        applied.value = landing;
        // A starting point, not a decision — the field below stays editable,
        // and the board is explicit that yours is the name your recipes read.
        if (landing.name != null) {
          name.value = landing.name!;
          seededName.value = landing.name;
        }
      } finally {
        if (context.mounted) scanning.value = false;
      }
    }

    final prefill = draft.value;
    final pack = applied.value?.packMeasure;

    return Container(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
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
                    style: ansiSerif(size: 20),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 16),
            Text('SOURCE', style: ansiLabel()),
            const SizedBox(height: 6),
            Row(
              children: [
                AnsiModeChip(
                  label: 'Manual',
                  selected: source.value == NewIngredientSource.manual,
                  onTap: () => source.value = NewIngredientSource.manual,
                ),
                const SizedBox(width: 6),
                AnsiModeChip(
                  label: 'USDA FDC',
                  selected: source.value == NewIngredientSource.usda,
                  onTap: () => source.value = NewIngredientSource.usda,
                ),
                const SizedBox(width: 6),
                AnsiModeChip(
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
            }, style: ansiMono(size: 10, color: AnsiColors.muted)),

            // F1: the lookup is drawn on the USDA leg, and it is DISABLED —
            // there is no row yet to fill in. It was a silent no-op on an
            // unsaved draft, which taught the user nothing; a greyed button
            // with the reason under it says what to do instead. Creating runs
            // exactly this probe (D7b), so the affordance is honest about
            // being the same action a moment later.
            if (source.value == NewIngredientSource.usda) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AnsiColors.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Look up in USDA',
                  textAlign: TextAlign.center,
                  style: ansiMono(size: 12, color: AnsiColors.muted),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'save first — a lookup fills in a row, and there isn’t one '
                'yet. Creating it runs exactly this lookup.',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],

            if (prefill != null) ...[
              const SizedBox(height: 14),
              DraftCard(
                draft: prefill,
                skipped: applied.value?.skipped ?? const [],
              ),
            ],

            const SizedBox(height: 18),
            Text('NAME', style: ansiLabel()),
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
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
              if (pack != null) ...[
                const SizedBox(height: 14),
                Text('ALSO ADD A MEASURE', style: ansiLabel()),
                const SizedBox(height: 6),
                _PackSizeTick(
                  amountInBasis: pack.amountInBasis,
                  basisLabel: pack.basis.baseUnit.label,
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
                style: ansiMono(size: 10, color: AnsiColors.muted),
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
    required this.amountInBasis,
    required this.basisLabel,
    required this.ticked,
    required this.label,
    required this.onToggle,
    required this.onLabel,
  });

  final double amountInBasis;
  final String basisLabel;
  final bool ticked;
  final String label;
  final VoidCallback onToggle;
  final ValueChanged<String> onLabel;

  @override
  Widget build(BuildContext context) {
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
                  color: ticked ? AnsiColors.herbSoft : AnsiColors.surface,
                  border: Border.all(
                    color: ticked ? AnsiColors.herb : AnsiColors.line,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: ticked
                    ? const Icon(
                        FLucideIcons.check,
                        size: 13,
                        color: AnsiColors.herbDeep,
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
              style: ansiMono(size: 12),
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
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
      ],
    );
  }
}
