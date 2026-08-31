/// The ingredient picker v2 (step 7.7, design board "Pickers v2" frame a):
/// top-anchored search over the synced vocab, a Recent section before any
/// query, information-honest result rows (category · capability hints · a
/// per-100 macro line for complete rows, a `stub` badge — never zeros), and
/// the add-new affordance (creates a `manual` stub, invariant 3).
///
/// Deterministic search only (ADR-0004): the step-7.4 normalizer + word-
/// boundary matching, in the repository.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/picker_shell.dart';
import '../data/ingredient_providers.dart';
import '../domain/ingredient.dart';
import 'macros_format.dart';

/// Opens the picker as a bottom sheet; resolves to the chosen ingredient
/// (possibly a just-created stub), or null if dismissed. [title] carries the
/// destination context ('Add to "for the curry"').
Future<Ingredient?> showIngredientPicker(
  BuildContext context, {
  String title = 'Add an ingredient',
}) {
  return showFSheet<Ingredient>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => _IngredientPickerSheet(title: title),
  );
}

/// The search state both hosts share (the picker sheet and the shopping
/// top-up embed): query text, results, and whether the results are the
/// recents feed (empty query) or a search.
({
  String query,
  List<Ingredient> results,
  bool showingRecents,
  Future<void> Function(String) run,
})
useIngredientSearch(WidgetRef ref, BuildContext context) {
  final query = useState('');
  final results = useState<List<Ingredient>>(const []);
  final showingRecents = useState(false);
  // Monotonic ticket so a slow older search can never overwrite a newer
  // one's results (or touch state after the host is dismissed).
  final searchSeq = useRef(0);

  Future<void> run(String q) async {
    query.value = q;
    final ticket = ++searchSeq.value;
    final repo = ref.read(ingredientRepositoryProvider);
    // Empty query → the recents feed; an unused vocab falls back to the
    // plain alphabetical list so the picker is never blank.
    var recents = false;
    var found = <Ingredient>[];
    if (q.trim().isEmpty) {
      found = await repo.recentlyUsed();
      recents = found.isNotEmpty;
    }
    if (found.isEmpty) found = await repo.search(q);
    if (!context.mounted || ticket != searchSeq.value) return;
    showingRecents.value = recents;
    results.value = found;
  }

  useEffect(() {
    run('');
    return null;
  }, const []);

  return (
    query: query.value,
    results: results.value,
    showingRecents: showingRecents.value,
    run: run,
  );
}

class _IngredientPickerSheet extends HookConsumerWidget {
  const _IngredientPickerSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);

    return PickerShell(
      title: title,
      searchHint: 'Search ingredients',
      searchAutofocus: true,
      onQueryChanged: search.run,
      body: IngredientResultList(
        results: search.results,
        query: search.query,
        showingRecents: search.showingRecents,
        onPick: (ing) => Navigator.of(context).pop(ing),
      ),
      footer: AddNewIngredientRow(
        query: search.query,
        onCreated: (ing) => Navigator.of(context).pop(ing),
      ),
    );
  }
}

/// The scrolling results — frame-a rows, with the Recent header before any
/// query.
class IngredientResultList extends StatelessWidget {
  const IngredientResultList({
    required this.results,
    required this.query,
    required this.showingRecents,
    required this.onPick,
    super.key,
  });

  final List<Ingredient> results;
  final String query;
  final bool showingRecents;
  final ValueChanged<Ingredient> onPick;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'No ingredients yet.'
              : 'No match for "$query" — add it below.',
          style: miseMono(size: 12, color: MiseColors.muted),
        ),
      );
    }
    return ListView(
      children: [
        if (showingRecents)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('RECENT', style: miseLabel()),
          ),
        for (final (i, ing) in results.indexed) ...[
          if (i > 0) Container(height: 1, color: MiseColors.line),
          IngredientRow(ingredient: ing, onPick: onPick),
        ],
      ],
    );
  }
}

/// One dense, information-honest result row: name (+`stub` badge), category
/// and capability hints, and a per-100 macro line for complete rows.
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    required this.ingredient,
    required this.onPick,
    super.key,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onPick;

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    final macros = ing.macros;
    final hints = [
      if (ing.category != null) ing.category!,
      if (ing.densityGPerMl != null) 'has density',
      if (ing.measureCount > 0)
        '${ing.measureCount} ${ing.measureCount == 1 ? 'measure' : 'measures'}',
      if (stub) 'needs macros — no zeros shown',
    ].join(' · ');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(ing),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ing.canonicalName,
                          style: miseSans(size: 15, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (stub) ...[
                        const SizedBox(width: 6),
                        const StubBadge(),
                      ],
                    ],
                  ),
                  if (hints.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hints,
                      style: miseMono(size: 10, color: MiseColors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Honest numbers: only a complete row shows a macro line.
                  if (!stub && macros != null) ...[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: formatMacroLine(macros),
                        style: miseMono(size: 10, color: MiseColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' ${macroBasisSuffix(ing.macrosBasis)}',
                            style: miseMono(size: 10, color: MiseColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(FLucideIcons.plus, size: 18, color: MiseColors.herb),
          ],
        ),
      ),
    );
  }
}

/// "＋ can't find it? add a new ingredient" — creates a manual stub named
/// after the query (or prompts nothing when the query is blank: the row is
/// disabled until something is typed).
class AddNewIngredientRow extends HookConsumerWidget {
  const AddNewIngredientRow({
    required this.query,
    required this.onCreated,
    super.key,
  });

  final String query;
  final ValueChanged<Ingredient> onCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = query.trim();
    // Creating a stub is a write with no idempotency key, so a double tap
    // during the round-trip would author two identical vocab rows. The row
    // goes inert for the duration instead.
    final creating = useState(false);
    final enabled = name.isNotEmpty && !creating.value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled
          ? null
          : () async {
              creating.value = true;
              try {
                final created = await ref
                    .read(ingredientRepositoryProvider)
                    .createStub(name);
                if (context.mounted) onCreated(created);
              } finally {
                if (context.mounted) creating.value = false;
              }
            },
      child: DashedBorderBox(
        color: enabled ? MiseColors.herb : MiseColors.line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FLucideIcons.plus,
              size: 12,
              color: enabled ? MiseColors.herb : MiseColors.muted,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                enabled
                    ? 'can’t find it? add "$name" as a new ingredient'
                    : 'can’t find it? type a name to add it',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: miseMono(
                  size: 11,
                  color: enabled ? MiseColors.herb : MiseColors.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StubBadge extends StatelessWidget {
  const StubBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text('stub', style: miseMono(size: 10, color: MiseColors.muted)),
    );
  }
}
