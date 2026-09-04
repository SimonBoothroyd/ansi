/// The recipe picker v2 (step 7.7, design board "Pickers v2" frame c): the
/// shared picker shell over the household's recipes, with three sources
/// (Recent · Books · Favorites), day-tagged "already this week" quick picks,
/// information-honest rows (filing · last-planned recency · shelf-life chips
/// · per-serving macros or an `incomplete` badge — never zeros), and the
/// "Eating" footer naming the household the meal is planned for.
///
/// Search is the shared `searchRank` rule over titles — the same call the
/// editor's "Your recipes" section makes. When nothing was spelled right the
/// typo tier answers and the list arrives under a `DID YOU MEAN` header.
///
/// Planning search stays recipes-only in v1 (decision); foods-as-ad-hoc-meals
/// is revisited with step 8. Resolves to the chosen recipe, or null if
/// dismissed; the caller then opens the confirm sheet.
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
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/incomplete_macros.dart';
import '../../../shared/picker_shell.dart';
import '../../books/domain/book.dart';
import '../../books/domain/library_search.dart';
import '../../books/presentation/book_view_models.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/planning.dart';
import 'week_format.dart';
import 'week_view_models.dart';
import 'week_widgets.dart';

/// Opens the recipe picker for a meal on [dayOfWeek] in [slot]. Resolves to the
/// chosen recipe, or null if dismissed.
Future<RecipeSummary?> showRecipePickerSheet(
  BuildContext context, {
  required int dayOfWeek,
  required String slot,
}) {
  return showAnsiSheet<RecipeSummary>(
    context: context,
    builder: (_) => _RecipePickerSheet(dayOfWeek: dayOfWeek, slot: slot),
  );
}

class _RecipePickerSheet extends HookConsumerWidget {
  const _RecipePickerSheet({required this.dayOfWeek, required this.slot});

  final int dayOfWeek;
  final String slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final tab = useState(0); // 0 = Recent, 1 = Books, 2 = Favorites

    // Decorative emptiness, weighed (D6): every one of these decorates the
    // picker's rows — the filing breadcrumb, the eater avatars, the "last
    // planned" chip. A missing decoration is a quieter row, not a wrong
    // answer, and the recipe list itself renders its own empty state.
    final recipes = ref.watch(recipeListProvider).asData?.value ?? const [];
    final library = ref.watch(libraryProvider).asData?.value ?? const [];
    final week = ref.watch(viewedWeekProvider).asData?.value;
    final members = ref.watch(membersProvider).asData?.value ?? const [];
    final lastPlanned =
        ref.watch(lastPlannedByRecipeProvider).asData?.value ??
        const <String, DateTime>{};
    final filing = filingByRecipe(library);

    // The shared rule, over titles — the same call the editor's "Your recipes"
    // section makes, so the two pickers cannot disagree about what hits. An
    // empty query still matches everything: this list is a browse surface as
    // well as a search.
    //
    // Only the BEST tier is shown. If any title was spelled right, no guess is
    // offered beside it; if none was, the whole list is a guess and says so.
    final tier = bestTier([
      for (final r in recipes) recipeTitleHit(r.title, query.value),
    ]);
    bool matches(String title) {
      if (query.value.isEmpty) return true;
      final hit = recipeTitleHit(title, query.value);
      return hit != null && hit.tier == tier;
    }

    final guessing = tier == SearchTier.typo;

    // Distinct recipes already planned this week, with the earliest day.
    final alreadyThisWeek = <String, ({String title, int day})>{};
    for (final e in week?.entries ?? const <PlanEntry>[]) {
      if (e.recipeTitle == null) continue;
      final existing = alreadyThisWeek[e.recipeId];
      if (existing == null || e.dayOfWeek < existing.day) {
        alreadyThisWeek[e.recipeId] = (title: e.recipeTitle!, day: e.dayOfWeek);
      }
    }

    void pick(RecipeSummary r) => Navigator.of(context).pop(r);

    Widget row(RecipeSummary r, {Filing? explicitFiling}) => _RecipeRow(
      recipe: r,
      filing: explicitFiling ?? filing[r.id],
      lastPlanned: lastPlanned[r.id],
      onPick: pick,
    );

    final body = switch (tab.value) {
      1 => _BooksList(
        library: library,
        recipes: recipes,
        matches: matches,
        row: row,
      ),
      2 => _FavoritesList(
        recipes: [
          for (final r in recipes)
            if (r.favorite && matches(r.title)) r,
        ],
        row: row,
      ),
      _ => _RecentList(
        recipes: _recentOrder(
          recipes.where((r) => matches(r.title)).toList(),
          lastPlanned,
        ),
        row: row,
      ),
    };

    return PickerShell(
      title: 'Add a meal',
      subtitle: 'to · ${kWeekdayFull[dayOfWeek]}, $slot',
      searchHint: 'Search recipes',
      onQueryChanged: (q) => query.value = q,
      aboveList: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PickerTabs(
            labels: const ['Recent', 'Books', 'Favorites'],
            index: tab.value,
            onChanged: (i) => tab.value = i,
          ),
          // Nothing was spelled right, so the rows below are guesses and the
          // list says so before the user reads one as a find.
          if (guessing) ...[
            const SizedBox(height: 12),
            const DidYouMeanHeader(),
          ],
          if (alreadyThisWeek.isNotEmpty && query.value.isEmpty) ...[
            const SizedBox(height: 12),
            _AlreadyThisWeek(
              items: alreadyThisWeek,
              onPick: (id, title) {
                // Hand the confirm sheet the real summary (shelf life drives
                // its "same batch" hint); a fabricated one only if the
                // recipe vanished from the list mid-build.
                final real = recipes.where((r) => r.id == id);
                pick(
                  real.isNotEmpty
                      ? real.first
                      : RecipeSummary(id: id, title: title, servingsBase: 1),
                );
              },
            ),
          ],
        ],
      ),
      body: body,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              Navigator.of(context).pop();
              context.pushOnce('/recipes/new');
            },
            child: DashedBorderBox(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    FLucideIcons.plus,
                    size: 12,
                    color: AnsiColors.herb,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'new recipe — build it from scratch',
                    textAlign: TextAlign.center,
                    style: ansiMono(
                      size: 11,
                      color: AnsiColors.herb,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (members.isNotEmpty) ...[
            const SizedBox(height: 10),
            _EatingFooter(members: members),
          ],
        ],
      ),
    );
  }
}

/// "Eating: Ada & Jun · shared" — who the plan feeds (frame c footer). The
/// actual eater selection happens on the confirm sheet.
class _EatingFooter extends StatelessWidget {
  const _EatingFooter({required this.members});

  final List<Member> members;

  @override
  Widget build(BuildContext context) {
    final names = members.map((m) => m.displayName).join(' & ');
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: 'Eating: ',
              style: ansiMono(size: 10, color: AnsiColors.muted),
              children: [
                TextSpan(
                  text: names,
                  style: ansiMono(size: 10, weight: FontWeight.w600),
                ),
                if (members.length > 1)
                  TextSpan(
                    text: ' · shared',
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                  ),
              ],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: EaterAvatar(member: m, color: memberColor(i)),
          ),
      ],
    );
  }
}

class _AlreadyThisWeek extends StatelessWidget {
  const _AlreadyThisWeek({required this.items, required this.onPick});

  final Map<String, ({String title, int day})> items;
  final void Function(String id, String title) onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Already this week — cook it in the same batch',
            style: ansiMono(
              size: 10,
              color: AnsiColors.herbDeep,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in items.entries)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(e.key, e.value.title),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AnsiColors.surface,
                      border: Border.all(color: AnsiColors.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.value.title,
                          style: ansiSans(
                            size: 13,
                            color: AnsiColors.herbDeep,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          kWeekdayShort[e.value.day],
                          style: ansiMono(size: 9, color: AnsiColors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Recent" means what the rows display (post-7.7 review): recently PLANNED
/// first (newest last-planned date leading), then never-planned recipes in
/// the list's own order (newest created first). The old created-at-only
/// order contradicted the recency label each row carries.
List<RecipeSummary> _recentOrder(
  List<RecipeSummary> recipes,
  Map<String, DateTime> lastPlanned,
) {
  final planned = [
    for (final r in recipes)
      if (lastPlanned.containsKey(r.id)) r,
  ]..sort((a, b) => lastPlanned[b.id]!.compareTo(lastPlanned[a.id]!));
  return [
    ...planned,
    for (final r in recipes)
      if (!lastPlanned.containsKey(r.id)) r,
  ];
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.recipes, required this.row});

  final List<RecipeSummary> recipes;
  final Widget Function(RecipeSummary r, {Filing? explicitFiling}) row;

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return Center(
        child: Text(
          'No recipes yet — add one below.',
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
      );
    }
    return ListView(children: [for (final r in recipes) row(r)]);
  }
}

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({required this.recipes, required this.row});

  final List<RecipeSummary> recipes;
  final Widget Function(RecipeSummary r, {Filing? explicitFiling}) row;

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return Center(
        child: Text(
          'No favorites yet — star a recipe from its page.',
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
      );
    }
    return ListView(children: [for (final r in recipes) row(r)]);
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({
    required this.library,
    required this.recipes,
    required this.matches,
    required this.row,
  });

  final List<Book> library;
  final List<RecipeSummary> recipes;
  final bool Function(String title) matches;
  final Widget Function(RecipeSummary r, {Filing? explicitFiling}) row;

  @override
  Widget build(BuildContext context) {
    // The Library aggregate carries its own (macro-less) summaries; render
    // the richer list-row summary where one exists so books rows stay as
    // honest as Recent's.
    final byId = {for (final r in recipes) r.id: r};
    return ListView(
      children: [
        for (final b in library) ...[
          for (final s in b.sections)
            for (final r in s.recipes)
              if (matches(r.title))
                row(
                  byId[r.id] ?? r,
                  explicitFiling: (book: b.name, section: s.name),
                ),
          for (final r in b.unsectioned)
            if (matches(r.title))
              row(
                byId[r.id] ?? r,
                explicitFiling: (book: b.name, section: null),
              ),
        ],
      ],
    );
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    required this.filing,
    required this.lastPlanned,
    required this.onPick,
  });

  final RecipeSummary recipe;
  final Filing? filing;
  final DateTime? lastPlanned;
  final ValueChanged<RecipeSummary> onPick;

  @override
  Widget build(BuildContext context) {
    final f = filing;
    final fileUnder = [
      if (f != null) f.book,
      if (f?.section != null) f!.section!,
    ].join(' · ');
    final planned = lastPlanned;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(recipe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RecipeThumb(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                    style: ansiSerif(size: 16),
                  ),
                  if (fileUnder.isNotEmpty || planned != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            fileUnder,
                            style: ansiMono(size: 10, color: AnsiColors.muted),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (planned != null)
                          Text(
                            formatLastPlanned(planned, DateTime.now()),
                            style: ansiMono(size: 10, color: AnsiColors.muted),
                          ),
                      ],
                    ),
                  ],
                  _ShelfChips(recipe: recipe),
                  _MacroLine(recipe: recipe),
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

/// The shelf-life chips (keeps N d with the freshness bar · freezable ·
/// best fresh).
class _ShelfChips extends StatelessWidget {
  const _ShelfChips({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) {
    final keeps = recipe.keepsForDays;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          if (keeps != null)
            _Pill(text: 'keeps $keeps d', freshness: true)
          else if (!recipe.freezable)
            const _Pill(text: 'best fresh'),
          if (recipe.freezable) const _Pill(text: 'freezable'),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.freshness = false});

  final String text;
  final bool freshness;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (freshness) ...[
            Container(
              width: 16,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  colors: [AnsiColors.fresh, AnsiColors.aging, AnsiColors.gone],
                ),
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(text, style: ansiMono(size: 9.5, color: AnsiColors.herbDeep)),
        ],
      ),
    );
  }
}

/// The honest per-serving line: `serves 4 · ~520 kcal · 31P /serving`, or
/// `serves 2 · [incomplete] 1 stub line` — never zeros (invariant 3).
class _MacroLine extends StatelessWidget {
  const _MacroLine({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) {
    final serves = 'serves ${formatQuantity(recipe.servingsBase)}';
    final summary = recipe.macros;
    if (summary == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          serves,
          style: ansiMono(size: 10, color: AnsiColors.herbDeep),
        ),
      );
    }
    final perServing = summary.perServing;
    if (perServing != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(
            text:
                '$serves · ~${perServing.kcal.round()} kcal · '
                '${perServing.protein.round()}P',
            style: ansiMono(size: 10, color: AnsiColors.herbDeep),
            children: [
              TextSpan(
                text: ' /serving',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(
            '$serves · ',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
          const IncompleteBadge(),
          // The reason WRAPS rather than running off the row: 8.6's nested
          // reasons ("1 unconvertible · 1 sub-recipe incomplete") are longer
          // than any before them, and a clipped reason is worse than a tall
          // row — the note exists to be read.
          Expanded(
            child: Text(
              ' ${incompleteNote(summary)}',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// A placeholder recipe thumbnail (photos need Storage — deferred).
class _RecipeThumb extends StatelessWidget {
  const _RecipeThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        FLucideIcons.cookingPot,
        size: 18,
        color: AnsiColors.herb,
      ),
    );
  }
}
