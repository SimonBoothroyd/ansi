/// "New ingredient" — the add flow's front door (design board "Ingredients
/// manager · v1" frame (d)'s **Source** segment).
///
/// Three sources, drawn as one segment because that is where the board put
/// the barcode entry point:
/// - **Manual** — type the name, get a stub, land on the flesh-out form.
/// - **USDA FDC** — the same write. The lookup is not a client action:
///   `usda_food` never syncs to a device (ADR-0005), so the trigram match
///   runs server-side when the row uploads (plan 0020 D7 (a)) and the form's
///   "Look up in USDA" button is a re-read, not a query. The segment says so
///   rather than implying a catalogue we deliberately don't ship.
/// - **Barcode** — rendered, and deliberately inert here. The scanner sheet,
///   the on-device Open Food Facts client and the draft mapper are lane B's
///   (D2/D3); this option is the socket they plug into at merge. A segment
///   that hid its unavailable leg would tell the user nothing about why.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../data/ingredient_providers.dart';
import 'density_entry.dart' show MiseModeChip;
import 'ingredient_detail_view.dart';

/// The add sources of frame (d).
enum NewIngredientSource { manual, usda, barcode }

/// Opens the add sheet. Resolves when it closes; on a create it has already
/// pushed the flesh-out form.
Future<void> showNewIngredientSheet(BuildContext context) => showFSheet<void>(
  context: context,
  side: FLayout.btt,
  mainAxisMaxRatio: null,
  useSafeArea: true,
  builder: (_) => const NewIngredientSheet(),
);

class NewIngredientSheet extends HookConsumerWidget {
  const NewIngredientSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = useState(NewIngredientSource.manual);
    final name = useState('');
    final creating = useState(false);
    final canCreate = name.value.trim().isNotEmpty && !creating.value;

    Future<void> create() async {
      creating.value = true;
      try {
        final created = await ref
            .read(ingredientRepositoryProvider)
            .createStub(name.value.trim());
        if (!context.mounted) return;
        Navigator.of(context).pop();
        // The push outlives this sheet; nothing here waits on the form.
        unawaited(context.push(ingredientDetailRoute(created.id)));
      } finally {
        if (context.mounted) creating.value = false;
      }
    }

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
              const MiseModeChip(
                label: 'Barcode',
                selected: false,
                enabled: false,
                onTap: _inert,
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
            NewIngredientSource.barcode => '',
          }, style: miseMono(size: 10, color: MiseColors.muted)),
          const SizedBox(height: 8),
          Text(
            'Barcode — wired at merge. The scanner, the Open Food Facts '
            'lookup and its ODbL credit land with the barcode lane; this is '
            'where they attach.',
            style: miseMono(size: 10, color: MiseColors.muted),
          ),
          const SizedBox(height: 18),
          Text('NAME', style: miseLabel()),
          const SizedBox(height: 6),
          FTextField(
            autofocus: true,
            hint: 'e.g. Curry leaves, fresh',
            control: FTextFieldControl.managed(
              onChange: (v) => name.value = v.text,
            ),
          ),
          const SizedBox(height: 14),
          FButton(
            onPress: canCreate ? create : null,
            child: const Text('Create & flesh out'),
          ),
        ],
      ),
    );
  }
}

/// The disabled Barcode option's no-op — a named function so the chip's
/// inertness is deliberate rather than an empty closure someone "fixes".
void _inert() {}
