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
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/picker_shell.dart';
import '../data/ingredient_providers.dart';
import '../data/usda_enrichment.dart';
import '../domain/ingredient.dart';
import 'ingredient_detail_view.dart' show ingredientDetailRoute;
import 'macros_format.dart';

/// Opens the picker as a bottom sheet; resolves to the chosen ingredient
/// (possibly a just-created stub), or null if dismissed. [title] carries the
/// destination context ('Add to "for the curry"').
Future<Ingredient?> showIngredientPicker(
  BuildContext context, {
  String title = 'Add an ingredient',
}) {
  return showAnsiSheet<Ingredient>(
    context: context,
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
        // The deep-link seam (D8): the line still gets its ingredient, and
        // the flesh-out form opens on top of wherever the picker was hosted.
        // Only offered where a router is actually in scope — the shopping
        // top-up embeds this row without one.
        onFleshOut: GoRouter.maybeOf(context) == null
            ? null
            : (ing) {
                Navigator.of(context).pop(ing);
                context.pushOnce(ingredientDetailRoute(ing.id));
              },
      ),
    );
  }
}

/// The scrolling results — frame-a rows, with the Recent header before any
/// query.
///
/// [trailing] is the one extension point (step 8.6 / D7, board frame c): a
/// section rendered UNDER the ingredient rows in the same scroll view — the
/// "Your recipes" section the line picker adds. Nothing else about the list
/// moves; when it is empty this is the shipped 7.7 list exactly.
class IngredientResultList extends StatelessWidget {
  const IngredientResultList({
    required this.results,
    required this.query,
    required this.showingRecents,
    required this.onPick,
    this.trailing = const [],
    super.key,
  });

  final List<Ingredient> results;
  final String query;
  final bool showingRecents;
  final ValueChanged<Ingredient> onPick;

  /// Extra sections below the ingredient rows.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty && trailing.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'No ingredients yet.'
              : 'No match for "$query" — add it below.',
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
      );
    }
    return ListView(
      children: [
        if (showingRecents)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('RECENT', style: ansiLabel()),
          )
        // With a second section below, the ingredient rows need a name of
        // their own — the board's frame-c header. Without one they are the
        // whole list and labelling them would be noise.
        else if (trailing.isNotEmpty && results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('INGREDIENTS', style: ansiLabel()),
          ),
        for (final (i, ing) in results.indexed) ...[
          if (i > 0) Container(height: 1, color: AnsiColors.line),
          IngredientRow(ingredient: ing, onPick: onPick),
        ],
        ...trailing,
      ],
    );
  }
}

/// One dense, information-honest result row: name (+`stub` badge), category
/// and capability hints, and a per-100 macro line for complete rows.
///
/// Shared by the picker (7.7) and the ingredients manager list (8.5) — the
/// two must read alike or the same ingredient tells two stories. Only the
/// trailing affordance differs: the picker adds, the manager navigates.
class IngredientRow extends StatelessWidget {
  const IngredientRow({
    required this.ingredient,
    required this.onPick,
    this.trailing,
    this.advisoryDensityGap = false,
    super.key,
  });

  final Ingredient ingredient;
  final ValueChanged<Ingredient> onPick;

  /// Defaults to the picker's `+`. The manager passes a chevron.
  final Widget? trailing;

  /// Whether a missing density is worth saying out loud. The manager list
  /// says it ("no density — volume units locked") because it is the screen
  /// that can fix it; the picker stays quiet because it can't (plan 0020 D5:
  /// this is an advisory, never a completion blocker).
  final bool advisoryDensityGap;

  @override
  Widget build(BuildContext context) {
    final ing = ingredient;
    final stub = ing.status == IngredientStatus.stub;
    final macros = ing.macros;
    final hints = [
      if (ing.category != null) ing.category!,
      if (ing.densityGPerMl != null)
        'has density'
      else if (advisoryDensityGap)
        'no density — volume units locked',
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
                          style: ansiSans(size: 15, weight: FontWeight.w600),
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
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Honest numbers: only a complete row shows a macro line.
                  if (!stub && macros != null) ...[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: formatMacroLine(macros),
                        style: ansiMono(size: 10, color: AnsiColors.herbDeep),
                        children: [
                          TextSpan(
                            text: ' ${macroBasisSuffix(ing.macrosBasis)}',
                            style: ansiMono(size: 10, color: AnsiColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(FLucideIcons.plus, size: 18, color: AnsiColors.herb),
          ],
        ),
      ),
    );
  }
}

/// "＋ can't find it? add a new ingredient" — creates a manual stub named
/// after the query (or prompts nothing when the query is blank: the row is
/// disabled until something is typed).
///
/// When [onFleshOut] is supplied the row does not close over the creation:
/// the stub is authored, and a two-action strip offers "use it" (the old
/// behaviour) beside "flesh out now →", which deep-links into the step-8.5
/// detail form. One flesh-out surface, not a second inline one (D8).
class AddNewIngredientRow extends HookConsumerWidget {
  const AddNewIngredientRow({
    required this.query,
    required this.onCreated,
    this.onFleshOut,
    super.key,
  });

  final String query;
  final ValueChanged<Ingredient> onCreated;
  final ValueChanged<Ingredient>? onFleshOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = query.trim();
    // Creating a stub is a write with no idempotency key, so a double tap
    // during the round-trip would author two identical vocab rows. The row
    // goes inert for the duration instead.
    final creating = useState(false);
    final justCreated = useState<Ingredient?>(null);
    final enabled = name.isNotEmpty && !creating.value;

    final created = justCreated.value;
    if (created != null) {
      return _JustCreatedStrip(
        created: created,
        onUse: () => onCreated(created),
        onFleshOut: () => onFleshOut!(created),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !enabled
          ? null
          : () async {
              creating.value = true;
              try {
                final made = await ref
                    .read(ingredientRepositoryProvider)
                    .createStub(name);
                // D7b: born enriched. The same probe-and-apply the manager's
                // add sheet runs — one answer to "what does creating an
                // ingredient mean", not two. Offline it answers null within
                // its own short timeout and the server trigger catches the
                // row on upload, so this never blocks the picker for long
                // and never surfaces an error.
                final enriched = await enrichFromUsda(
                  made,
                  probe: ref.read(usdaProbeProvider),
                  repository: ref.read(ingredientRepositoryProvider),
                );
                if (!context.mounted) return;
                // The enriched row when the probe landed, the bare one
                // otherwise — either way a `stub`, because confirming stays a
                // human act (D5).
                final row = enriched.row ?? made;
                if (onFleshOut == null) {
                  onCreated(row);
                } else {
                  justCreated.value = row;
                }
              } finally {
                if (context.mounted) creating.value = false;
              }
            },
      child: DashedBorderBox(
        color: enabled ? AnsiColors.herb : AnsiColors.line,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FLucideIcons.plus,
              size: 12,
              color: enabled ? AnsiColors.herb : AnsiColors.muted,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                enabled
                    ? 'can’t find it? add "$name" as a new ingredient'
                    : 'can’t find it? type a name to add it',
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: ansiMono(
                  size: 11,
                  color: enabled ? AnsiColors.herb : AnsiColors.muted,
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

/// What the add-new row becomes once the stub exists: it is already saved
/// (and already usable), so the two actions are "take it back to the line I
/// was editing" and "go fill it in now".
class _JustCreatedStrip extends StatelessWidget {
  const _JustCreatedStrip({
    required this.created,
    required this.onUse,
    required this.onFleshOut,
  });

  final Ingredient created;
  final VoidCallback onUse;
  final VoidCallback onFleshOut;

  @override
  Widget build(BuildContext context) {
    return DashedBorderBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'added “${created.canonicalName}” as a stub',
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onUse,
                child: Text(
                  'use it',
                  style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onFleshOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'flesh out now',
                      style: ansiMono(size: 12, color: AnsiColors.herbDeep),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      FLucideIcons.arrowRight,
                      size: 12,
                      color: AnsiColors.herbDeep,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
      child: Text('stub', style: ansiMono(size: 10, color: AnsiColors.muted)),
    );
  }
}
