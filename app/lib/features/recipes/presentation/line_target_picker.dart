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
/// The "Your recipes" search is the shared `searchRank` rule over titles — the
/// same call the planning picker makes, pinned by a cross-picker test. When
/// nothing was spelled right the section arrives under a `DID YOU MEAN`
/// header; a link is still one human tap away, never a resolution.
///
/// **A cycle is never offered** (D5). The recipe being edited is excluded
/// (a recipe cannot be its own component) and so is any recipe that already
/// reaches it over live component links; the check runs again at pick time,
/// because a link the other device wrote can land between the two moments.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/picker_shell.dart';
import '../../books/domain/book.dart';
import '../../books/presentation/book_view_models.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/search_rank.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../data/recipe_providers.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'recipe_chip.dart';

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
Future<PickedLineTarget?> showLineTargetPicker(
  BuildContext context, {
  required String editingRecipeId,
  String title = 'Add an ingredient',
}) {
  return showAnsiSheet<PickedLineTarget>(
    context: context,
    builder: (_) =>
        _LineTargetPickerSheet(title: title, editingRecipeId: editingRecipeId),
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
  });

  final String title;
  final String editingRecipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = useIngredientSearch(ref, context);
    // Decorative emptiness, weighed (D6): the books only group the picker's
    // rows. The recipes themselves come from their own provider and still list.
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    final refusal = useState<String?>(null);

    // The shared rule, over titles — the same call the planning picker makes.
    // This section used to carry a rule of its own (the WHOLE query had to
    // prefix the title, and `[^a-z0-9]+` split words, so an accented letter
    // was a word break); the two pickers disagreed one screen apart.
    //
    // Only the best tier is offered: if any title was spelled right, no guess
    // is shown beside it.
    final candidates = [
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

    Future<void> pick(RecipeSummary recipe) async {
      // Re-asked at the moment of the tap: the other device can have written
      // the closing link while this sheet was open (D5).
      final cycles = await ref
          .read(recipeRepositoryProvider)
          .componentLinkWouldCycle(
            recipeId: editingRecipeId,
            subRecipeId: recipe.id,
          );
      if (!context.mounted) return;
      if (cycles) {
        refusal.value =
            '“${recipe.title}” already uses this recipe — linking it '
            'would make a loop.';
        return;
      }
      Navigator.of(context).pop(
        PickedSubRecipe(
          SubRecipeTarget(
            id: recipe.id,
            title: recipe.title,
            yieldQty: recipe.yieldQty,
            yieldUnit: recipe.yieldUnit,
            yieldQty2: recipe.yieldQty2,
            yieldUnit2: recipe.yieldUnit2,
          ),
        ),
      );
    }

    return PickerShell(
      title: title,
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
              _RecipeRow(candidate: c, onPick: () => pick(c.recipe)),
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
      // The add-new chain (plan 0025 D3): sheet → flesh-out form → back, and
      // only then does this sheet resolve — so the editor's `_addLine`
      // continues into the quantity sheet AFTER the form, on the units the
      // form set. The row handed over is the re-read one.
      footer: AddNewIngredientRow(
        query: search.query,
        onCreated: (ing) => Navigator.of(context).pop(PickedIngredient(ing)),
      ),
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
