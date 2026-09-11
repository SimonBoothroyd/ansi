/// The editor's ONE door for adding a line (step 8.6 / D7, design board frame
/// c): the shipped ingredient picker v2 with a **"Your recipes"** section
/// below the ingredient results.
///
/// The picker is not redrawn. Same top-anchored search, same honest ingredient
/// rows, same add-new footer; one more section appears when the query hits a
/// household recipe title, and picking from it makes the line a component
/// instead of an ingredient. Adding a line is one act, so it gets one door —
/// a separate "＋ sub-recipe" row would force the user to know, before
/// searching, whether the thing they want is a recipe.
///
/// The "Your recipes" search is the shared [searchRank] rule over titles — the
/// same call the planning picker makes, pinned by a cross-picker test. When
/// nothing was spelled right the section arrives under a `DID YOU MEAN`
/// header; a link is still one human tap away, never a resolution.
///
/// **A cycle is never offered** (D5). The recipe being edited is excluded
/// (a recipe cannot be its own component) and so is any recipe that already
/// reaches it over live component links; the check runs again at pick time,
/// because a link the other device wrote can land between the two moments.
///
/// The footer carries **two** add-new doors, because the thing a line wants
/// may be a recipe nobody has written yet: the ingredient form, and the
/// recipe editor seeded with the typed words. Both push over this sheet,
/// which stays open underneath, and resolve it with what they popped —
/// nothing is written by backing out of either. The new editor's own picker
/// offers the same two doors, so a sauce can be written from inside the
/// recipe that needs it, as deep as the cook goes.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/search/search_rank.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/picker_shell.dart';
import '../../../shared/write.dart';
import '../../books/domain/book.dart';
import '../../books/presentation/book_view_models.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../data/recipe_providers.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'recipe_chip.dart';
import 'recipe_editor_view.dart' show newSubRecipeRoute;

/// What the picker resolved to — an ingredient line, or a component line.
sealed class PickedLineTarget {
  const PickedLineTarget();
}

final class PickedIngredient extends PickedLineTarget {
  const PickedIngredient(this.ingredient);

  final Ingredient ingredient;
}

final class PickedSubRecipe extends PickedLineTarget {
  const PickedSubRecipe(this.target);

  /// Carries the title AND the yields, so the quantity sheet that opens next
  /// can offer the right chips without another read.
  final SubRecipeTarget target;
}

/// One "Your recipes" row's data: the recipe, and where it is filed.
typedef RecipeCandidate = ({RecipeSummary recipe, String filing});

/// Opens the picker; resolves to the chosen line target, or null if dismissed.
///
/// [editingRecipeId] is the recipe the line is being added to — excluded from
/// the recipes section along with anything that would close a cycle.
/// [subtitle] is the one line a caller may add under the title to say which
/// posture the pick is being made in — week mode's "for this week only".
///
/// [suppressRecipes] hides the "Your recipes" section entirely. Week mode
/// passes it: a sub-recipe swapped for one week would make the component graph
/// week-dependent, and that graph is read household-wide with no week at all.
Future<PickedLineTarget?> showLineTargetPicker(
  BuildContext context, {
  required String editingRecipeId,
  String title = 'Add an ingredient',
  String? subtitle,
  bool suppressRecipes = false,
}) {
  return showAnsiSheet<PickedLineTarget>(
    context: context,
    builder: (_) => _LineTargetPickerSheet(
      title: title,
      subtitle: subtitle,
      editingRecipeId: editingRecipeId,
      suppressRecipes: suppressRecipes,
    ),
  );
}

/// Every recipe in the library, with its "Book · Section" filing, flattened
/// out of the library tree in book order — the board's row subtitle.
List<RecipeCandidate> recipeCandidates(List<Book> books) => [
  for (final book in books) ...[
    for (final section in book.sections)
      for (final r in section.recipes)
        (recipe: r, filing: '${book.name} · ${section.name}'),
    for (final r in book.unsectioned) (recipe: r, filing: book.name),
  ],
];

class _LineTargetPickerSheet extends HookConsumerWidget {
  const _LineTargetPickerSheet({
    required this.title,
    required this.editingRecipeId,
    this.subtitle,
    this.suppressRecipes = false,
  });

  final String title;
  final String? subtitle;
  final String editingRecipeId;
  final bool suppressRecipes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    // Decorative emptiness, weighed (D6): the books only group the picker's
    // rows. The recipes themselves come from their own provider and still list.
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    final refusal = useState<String?>(null);

    // The shared rule, over titles — the same call the planning picker makes,
    // so two pickers one screen apart cannot disagree about what hits.
    //
    // Only the best tier is offered: if any title was spelled right, no guess
    // is shown beside it.
    final candidates = [
      if (!suppressRecipes)
        for (final c in recipeCandidates(books))
          if (c.recipe.id != editingRecipeId) c,
    ];
    final tier = bestTier([
      for (final c in candidates) recipeTitleHit(c.recipe.title, search.query),
    ]);
    final matches = tier == null
        ? const <RecipeCandidate>[]
        : [
            for (final c in candidates)
              if (recipeTitleHit(c.recipe.title, search.query)?.tier == tier) c,
          ];
    final guessing = tier == SearchTier.typo;

    // The cycle guard, over exactly the rows about to be offered. Until it
    // answers, nothing from this section is shown — an offer that has to be
    // taken back is worse than one that arrives a frame late.
    final checked = useState<({String key, Set<String> blocked})?>(null);
    final key = '$editingRecipeId|${matches.map((c) => c.recipe.id).join(',')}';
    useEffect(() {
      if (matches.isEmpty) return null;
      var cancelled = false;
      final repository = ref.read(recipeRepositoryProvider);
      Future<void>(() async {
        final blocked = <String>{};
        for (final c in matches) {
          if (await repository.componentLinkWouldCycle(
            recipeId: editingRecipeId,
            subRecipeId: c.recipe.id,
          )) {
            blocked.add(c.recipe.id);
          }
        }
        if (!cancelled) checked.value = (key: key, blocked: blocked);
      });
      return () => cancelled = true;
    }, [key]);

    final answer = checked.value;
    final offered = answer == null || answer.key != key
        ? const <RecipeCandidate>[]
        : [
            for (final c in matches)
              if (!answer.blocked.contains(c.recipe.id)) c,
          ];

    Future<void> pick(SubRecipeTarget target) async {
      // Re-asked at the moment of the tap: the other device can have written
      // the closing link while this sheet was open (D5). A recipe written
      // from the footer goes through here too — its editor's own picker could
      // have linked it back at this one while it was open.
      final cycles = await ref
          .read(recipeRepositoryProvider)
          .componentLinkWouldCycle(
            recipeId: editingRecipeId,
            subRecipeId: target.id,
          );
      if (!context.mounted) return;
      if (cycles) {
        refusal.value =
            '“${target.title}” already uses this recipe — linking it '
            'would make a loop.';
        return;
      }
      Navigator.of(context).pop(PickedSubRecipe(target));
    }

    return PickerShell(
      title: title,
      subtitle: subtitle,
      searchHint: 'Search ingredients',
      searchAutofocus: true,
      onQueryChanged: search.run,
      body: IngredientResultList(
        results: search.results,
        query: search.query,
        showingRecents: search.showingRecents,
        guessed: search.guessed,
        onPick: (ing) => Navigator.of(context).pop(PickedIngredient(ing)),
        trailing: [
          if (offered.isNotEmpty) ...[
            // Each corpus carries its own band: the ingredient rows above may
            // be spellings while these titles are guesses, or the reverse.
            if (guessing)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: DidYouMeanHeader(),
              ),
            Padding(
              padding: EdgeInsets.only(top: guessing ? 0 : 14, bottom: 4),
              child: Text('YOUR RECIPES', style: ansiLabel()),
            ),
            for (final (i, c) in offered.indexed) ...[
              if (i > 0) Container(height: 1, color: AnsiColors.line),
              _RecipeRow(
                candidate: c,
                onPick: () => pick(
                  SubRecipeTarget(
                    id: c.recipe.id,
                    title: c.recipe.title,
                    yieldQty: c.recipe.yieldQty,
                    yieldUnit: c.recipe.yieldUnit,
                    yieldQty2: c.recipe.yieldQty2,
                    yieldUnit2: c.recipe.yieldUnit2,
                  ),
                ),
              ),
            ],
          ],
          if (refusal.value != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                refusal.value!,
                style: ansiMono(size: 11, color: AnsiColors.gone),
              ),
            ),
        ],
      ),
      // The add-new chain: the form (or the editor), then back, and only then
      // does this sheet resolve — so the caller continues into the quantity
      // sheet AFTER it, on the units or yields it just set. What is handed
      // over is the thing as that write left it.
      footer: Column(
        children: [
          AddNewIngredientRow(
            query: search.query,
            onCreated: (ing) =>
                Navigator.of(context).pop(PickedIngredient(ing)),
          ),
          // Week mode hides the recipe section, and a recipe written here
          // would be a pick the week cannot store: the door goes with it.
          if (!suppressRecipes) ...[
            const SizedBox(height: 8),
            _AddNewRecipeRow(query: search.query, onCreated: pick),
          ],
        ],
      ),
    );
  }
}

/// "＋ …or write "X" as a new recipe" — the footer's second door.
///
/// A line can want something nobody has written yet, and making it should not
/// mean leaving the line half-added: the editor lands ABOVE this sheet,
/// writes nothing until Save, and pops with the recipe it made (or nothing,
/// if the person backed out). The sheet is still open underneath to resolve.
///
/// There is no placeholder here and no status column. An empty recipe is a
/// real recipe that simply yields nothing yet: it contributes nothing to
/// macros or the shop list, and a component whose target states no yield
/// degrades to batches — all of which the app already says out loud.
class _AddNewRecipeRow extends HookWidget {
  const _AddNewRecipeRow({required this.query, required this.onCreated});

  final String query;

  /// Receives the saved recipe as the line's target. Not called when the
  /// editor was backed out of — nothing was written, so nothing resolves.
  final ValueChanged<SubRecipeTarget> onCreated;

  @override
  Widget build(BuildContext context) {
    final name = query.trim();
    // Two taps in one frame would push two editors. The row goes inert for
    // the duration instead.
    final busy = useState(false);
    final enabled = name.isNotEmpty && !busy.value;

    Future<void> writeOne() async {
      busy.value = true;
      // The chain crosses an await with a keyboard in it; the handle it
      // continues through outlives this row (`hostContextOf`).
      final host = hostContextOf(context);
      try {
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        final created = await host.context.pushOnceFor<SubRecipeTarget?>(
          newSubRecipeRoute(title: name),
        );
        if (created == null) return;
        onCreated(created);
      } finally {
        if (context.mounted) busy.value = false;
      }
    }

    return DashedAction(
      icon: FLucideIcons.plus,
      enabled: enabled,
      label: enabled
          ? '…or write "$name" as a new recipe'
          : '…or type a name to write a new recipe',
      onTap: writeOne,
    );
  }
}

/// One "Your recipes" row: the cross-reference glyph, the title, its
/// book · section filing, and what a batch makes — or the honest *"no yield
/// yet"*, because a yield-less recipe still links (its amounts simply read in
/// batches, D2).
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.candidate, required this.onPick});

  final RecipeCandidate candidate;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final recipe = candidate.recipe;
    final yields = recipe.yields;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPick,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            const Icon(kSubRecipeIcon, size: 16, color: AnsiColors.herb),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title,
                    style: ansiSans(size: 15, weight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    candidate.filing,
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    yields.isEmpty ? 'no yield yet' : yieldText(yields.first),
                    style: ansiMono(
                      size: 10,
                      color: yields.isEmpty
                          ? AnsiColors.muted
                          : AnsiColors.herbDeep,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(FLucideIcons.plus, size: 18, color: AnsiColors.herb),
          ],
        ),
      ),
    );
  }
}
