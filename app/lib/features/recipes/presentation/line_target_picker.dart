/// The editor's one door for adding a line: the ingredient picker with a "Your
/// recipes" section under the ingredient results. Picking a recipe makes the
/// line a component.
///
/// The recipes search is the shared [searchRank] rule over titles; guesses
/// arrive under a `DID YOU MEAN` header. A cycle is never offered: the recipe
/// being edited and anything that already reaches it are excluded, and the
/// check runs again at pick time. The footer has two add-new doors, the
/// ingredient form and the recipe editor seeded with the typed words; both push
/// over this sheet and resolve it with what they created.
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

  /// Carries the title and the yields, so the quantity sheet needs no second
  /// read.
  final SubRecipeTarget target;
}

/// One "Your recipes" row's data: the recipe, and where it is filed.
typedef RecipeCandidate = ({RecipeSummary recipe, String filing});

/// Opens the picker; resolves to the chosen line target, or null if dismissed.
///
/// [editingRecipeId] is the recipe the line is being added to. [subtitle] is an
/// optional line under the title (week mode's "for this week only").
/// [suppressRecipes] hides the recipes section; week mode passes it, because a
/// week cannot store a sub-recipe swap.
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

/// Every recipe in the library with its "Book · Section" filing, in book order.
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
    // The books only group the rows; the recipes come from their own provider.
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    final refusal = useState<String?>(null);

    // The shared title search, as in the planning picker. Only the best tier is
    // offered.
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

    // The cycle guard over the rows about to be offered. Nothing from this
    // section shows until it answers.
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
      // Re-checked at the tap: another device can have written the closing link
      // while this sheet was open. A recipe written from the footer goes
      // through here too.
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
            // Each section has its own tier: ingredient rows may be spellings
            // while these titles are guesses, or the reverse.
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
                // The target carries this recipe's measures as well as its
                // yields.
                onPick: () => pick(c.recipe.asSubRecipeTarget),
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
      // Add-new: the form (or editor) runs, and only then does this sheet
      // resolve, so the quantity sheet opens on the units or yields just set.
      footer: Column(
        children: [
          AddNewIngredientRow(
            query: search.query,
            onCreated: (ing) =>
                Navigator.of(context).pop(PickedIngredient(ing)),
          ),
          // Week mode hides the recipe section, so it hides this door too.
          if (!suppressRecipes) ...[
            const SizedBox(height: 8),
            _AddNewRecipeRow(query: search.query, onCreated: pick),
          ],
        ],
      ),
    );
  }
}

/// "＋ …or write "X" as a new recipe" — the footer's second door. The editor
/// opens above this sheet, writes nothing until Save, and pops with the recipe
/// it made, or nothing.
class _AddNewRecipeRow extends HookWidget {
  const _AddNewRecipeRow({required this.query, required this.onCreated});

  final String query;

  /// Receives the saved recipe as the line's target. Not called when the editor
  /// was backed out of.
  final ValueChanged<SubRecipeTarget> onCreated;

  @override
  Widget build(BuildContext context) {
    final name = query.trim();
    // Inert while busy, so two taps in one frame cannot push two editors.
    final busy = useState(false);
    final enabled = name.isNotEmpty && !busy.value;

    Future<void> writeOne() async {
      busy.value = true;
      // The chain crosses an await with a keyboard in it, so it continues from
      // a context that outlives this row (`hostContextOf`).
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

/// One "Your recipes" row: the glyph, the title, its book · section filing, and
/// what a batch makes, or "no yield yet".
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
