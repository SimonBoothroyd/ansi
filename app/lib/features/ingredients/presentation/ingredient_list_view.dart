/// The ingredients manager list (`/ingredients`) — design board "Ingredients
/// manager · v1" frame (a). A **pushed** route with a back chevron and no
/// bottom nav (plan 0020 D8: the four tabs are the loop; a vocabulary is
/// reference data), reached from Library ▸ ⋯ ▸ Ingredients.
///
/// The old "Fleshing-out queue" frame becomes a **band on top of the whole
/// vocabulary** rather than its own screen: a vocabulary you can only see
/// when it is broken is not a vocabulary you can edit.
///
/// Rows are the 7.7 picker rows ([IngredientRow]) — same hints, same honest
/// silence where a number is missing — with a chevron instead of a `+`.
/// Search is the same deterministic local search the picker uses
/// ([useIngredientSearch]); typing collapses the band into the results, which
/// is what a search is for.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import 'ingredient_detail_view.dart';
import 'ingredient_picker.dart';
import 'new_ingredient_sheet.dart';

/// The manager's route.
const kIngredientsRoute = '/ingredients';

class IngredientListView extends HookConsumerWidget {
  const IngredientListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    final vocabulary = ref.watch(vocabularyProvider);
    // The search field owns its controller (a hook, so it survives every
    // rebuild) and the list branches on WHAT THE FIELD SAYS — never on a
    // query that has outlived the text that produced it. An empty field is
    // therefore the whole vocabulary, by construction: no round-trip, stale
    // `onChange` or re-seeded control can leave the list showing search
    // results under a field displaying its hint (plan 0020 **J4**).
    final field = useTextEditingController();
    final typed = useValueListenable(field).text;
    final searching = typed.trim().isNotEmpty;
    // Fetching is a side effect of the text changing; a selection-only change
    // must not re-run the query.
    final lastRun = useRef<String?>(null);
    useEffect(() {
      void onEdit() {
        if (lastRun.value == field.text) return;
        lastRun.value = field.text;
        search.run(field.text);
      }

      field.addListener(onEdit);
      return () => field.removeListener(onEdit);
    }, [field]);

    final all = vocabulary.asData?.value ?? const <Ingredient>[];
    final stubs = [
      for (final i in all)
        if (i.status == IngredientStatus.stub) i,
    ];

    void open(Ingredient i) => context.push(ingredientDetailRoute(i.id));

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('Ingredients', style: miseHeaderTitle()),
        prefixes: [
          FHeaderAction.back(
            onPress: () => context.canPop() ? context.pop() : context.go('/'),
          ),
        ],
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.plus),
            onPress: () => showNewIngredientSheet(context),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FTextField(
              hint: 'Search your vocabulary',
              control: FTextFieldControl.managed(controller: field),
              prefixBuilder: (context, style, _) =>
                  const Icon(FLucideIcons.search),
            ),
          ),
          Expanded(
            child: switch (vocabulary) {
              AsyncError(:final error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not read the vocabulary — $error',
                    textAlign: TextAlign.center,
                    style: miseMono(size: 12, color: MiseColors.muted),
                  ),
                ),
              ),
              AsyncLoading() when all.isEmpty => const SizedBox.shrink(),
              _ when all.isEmpty => Center(
                child: Text(
                  'No ingredients yet — the vocabulary arrives with your '
                  'household’s first sync.',
                  textAlign: TextAlign.center,
                  style: miseMono(size: 12, color: MiseColors.muted),
                ),
              ),
              _ => ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                children: [
                  if (searching)
                    // The typed text, not the hook's query: the "no match"
                    // line must name what the field shows.
                    ..._searchResults(search.results, typed, open)
                  else ...[
                    if (stubs.isNotEmpty) _StubBand(stubs: stubs, onOpen: open),
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 4),
                      child: Text(
                        'All ingredients · ${all.length}',
                        style: miseLabel(),
                      ),
                    ),
                    for (final (i, ing) in all.indexed) ...[
                      if (i > 0) Container(height: 1, color: MiseColors.line),
                      _ManagerRow(ingredient: ing, onOpen: open),
                    ],
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showNewIngredientSheet(context),
                    child: FCard(
                      child: Text(
                        'add an ingredient — by hand, or scan a barcode',
                        textAlign: TextAlign.center,
                        style: miseMono(size: 11, color: MiseColors.herb),
                      ),
                    ),
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _searchResults(
    List<Ingredient> results,
    String query,
    ValueChanged<Ingredient> onOpen,
  ) {
    if (results.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No match for "$query".',
            textAlign: TextAlign.center,
            style: miseMono(size: 12, color: MiseColors.muted),
          ),
        ),
      ];
    }
    return [
      for (final (i, ing) in results.indexed) ...[
        if (i > 0) Container(height: 1, color: MiseColors.line),
        _ManagerRow(ingredient: ing, onOpen: onOpen),
      ],
    ];
  }
}

/// The picker row, wearing the manager's chevron. Rendering it twice in two
/// places is how the same ingredient starts telling two stories.
class _ManagerRow extends StatelessWidget {
  const _ManagerRow({required this.ingredient, required this.onOpen});

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onOpen;

  @override
  Widget build(BuildContext context) => IngredientRow(
    ingredient: ingredient,
    onPick: onOpen,
    advisoryDensityGap: true,
    trailing: const Icon(
      FLucideIcons.chevronRight,
      size: 16,
      color: MiseColors.muted,
    ),
  );
}

/// "Needs fleshing out" — the stub band pinned above the vocabulary.
///
/// The per-row hint says **needs macros**, not "needs density · macros": the
/// D5 gate is macros alone, and a missing density is an advisory the full row
/// below already carries.
///
/// **G4** — and once a prefill has put macros there, the hint stops asking
/// for what the row already has. It reads **needs confirm**, which is D5's
/// own language for the one thing still missing: a human standing behind the
/// numbers. "needs macros" stays for the truly bare stubs, where it is the
/// literal truth.
class _StubBand extends StatelessWidget {
  const _StubBand({required this.stubs, required this.onOpen});

  final List<Ingredient> stubs;
  final ValueChanged<Ingredient> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: MiseColors.paper,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Needs fleshing out', style: miseSans(size: 13)),
              Text(
                '${stubs.length} ${stubs.length == 1 ? 'stub' : 'stubs'}',
                style: miseMono(size: 10, color: MiseColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final s in stubs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onOpen(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.canonicalName,
                        style: miseSans(size: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      [
                        if (s.macros == null)
                          'needs macros'
                        else
                          'needs confirm',
                        if (isUsdaPrefilled(s.source)) 'usda prefilled',
                      ].join(' · '),
                      style: miseMono(size: 10, color: MiseColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'A stub stays out of macro totals until you confirm it.',
            style: miseMono(size: 10, color: MiseColors.muted),
          ),
        ],
      ),
    );
  }
}
