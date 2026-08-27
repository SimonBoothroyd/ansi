/// Step 2 of the add-a-meal flow: choose a recipe from your own library.
///
/// A bottom sheet over the Week. Recipes come from the recipes + books features
/// (this screen composes them): a "Recent" list (newest-first) and a "Books"
/// list (grouped by book · section), each row carrying its filing as subtitle.
/// Dishes already on the week are surfaced at the top as quick picks (the
/// batch-aware framing — the shelf-life reasoning itself lands in step 5). It
/// resolves to the chosen recipe, or null if dismissed; the caller then opens
/// the confirm sheet.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/dashed_border_box.dart';
import '../../books/domain/book.dart';
import '../../books/presentation/book_view_models.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/recipe_view_models.dart';
import '../domain/planning.dart';
import 'week_format.dart';
import 'week_view_models.dart';

/// Opens the recipe picker for a meal on [dayOfWeek] in [slot]. Resolves to the
/// chosen recipe, or null if dismissed.
Future<RecipeSummary?> showRecipePickerSheet(
  BuildContext context, {
  required int dayOfWeek,
  required String slot,
}) {
  return showFSheet<RecipeSummary>(
    context: context,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => _RecipePickerSheet(dayOfWeek: dayOfWeek, slot: slot),
  );
}

/// Filing context (book · section) for a recipe, for the row subtitle.
typedef _Filing = ({String book, String? section});

Map<String, _Filing> _filingByRecipe(List<Book> library) {
  final map = <String, _Filing>{};
  for (final b in library) {
    for (final s in b.sections) {
      for (final r in s.recipes) {
        map[r.id] = (book: b.name, section: s.name);
      }
    }
    for (final r in b.unsectioned) {
      map[r.id] = (book: b.name, section: null);
    }
  }
  return map;
}

class _RecipePickerSheet extends HookConsumerWidget {
  const _RecipePickerSheet({required this.dayOfWeek, required this.slot});

  final int dayOfWeek;
  final String slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = useState('');
    final tab = useState(0); // 0 = Recent, 1 = Books

    final recipes = ref.watch(recipeListProvider).asData?.value ?? const [];
    final library = ref.watch(libraryProvider).asData?.value ?? const [];
    final week = ref.watch(currentWeekProvider).asData?.value;
    final filing = _filingByRecipe(library);

    bool matches(String title) =>
        query.value.isEmpty ||
        title.toLowerCase().contains(query.value.toLowerCase());

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

    return Container(
      height: MediaQuery.sizeOf(context).height * 0.86,
      decoration: const BoxDecoration(
        color: MiseColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: Column(
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
                    'Add a meal',
                    textAlign: TextAlign.center,
                    style: miseSerif(size: 20),
                  ),
                ),
                const SizedBox(width: 22),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'to · ${kWeekdayFull[dayOfWeek]}, $slot',
              textAlign: TextAlign.center,
              style: miseMono(size: 11, color: MiseColors.muted),
            ),
            const SizedBox(height: 12),
            FTextField(
              hint: 'Search recipes',
              control: FTextFieldControl.managed(
                onChange: (v) => query.value = v.text,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Tab(
                  label: 'Recent',
                  selected: tab.value == 0,
                  onTap: () => tab.value = 0,
                ),
                const SizedBox(width: 8),
                _Tab(
                  label: 'Books',
                  selected: tab.value == 1,
                  onTap: () => tab.value = 1,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (alreadyThisWeek.isNotEmpty && query.value.isEmpty)
              _AlreadyThisWeek(
                items: alreadyThisWeek,
                onPick: (id, title) =>
                    pick(RecipeSummary(id: id, title: title, servingsBase: 1)),
              ),
            Expanded(
              child: tab.value == 0
                  ? _RecentList(
                      recipes: recipes.where((r) => matches(r.title)).toList(),
                      filing: filing,
                      onPick: pick,
                    )
                  : _BooksList(
                      library: library,
                      matches: matches,
                      onPick: pick,
                    ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(context).pop();
                context.push('/recipes/new');
              },
              child: DashedBorderBox(
                child: Text(
                  '＋ new recipe — build it from scratch',
                  textAlign: TextAlign.center,
                  style: miseMono(
                    size: 11,
                    color: MiseColors.herb,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? MiseColors.ink : MiseColors.surface,
          border: Border.all(
            color: selected ? MiseColors.ink : MiseColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: miseMono(
            size: 12,
            color: selected ? MiseColors.surface : MiseColors.muted,
          ),
        ),
      ),
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
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MiseColors.herbSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Already this week',
            style: miseMono(
              size: 10,
              color: MiseColors.herbDeep,
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
                      color: MiseColors.surface,
                      border: Border.all(color: MiseColors.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.value.title,
                          style: miseSans(
                            size: 13,
                            color: MiseColors.herbDeep,
                            weight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          kWeekdayShort[e.value.day],
                          style: miseMono(size: 9, color: MiseColors.muted),
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

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.recipes,
    required this.filing,
    required this.onPick,
  });

  final List<RecipeSummary> recipes;
  final Map<String, _Filing> filing;
  final ValueChanged<RecipeSummary> onPick;

  @override
  Widget build(BuildContext context) {
    if (recipes.isEmpty) {
      return Center(
        child: Text(
          'No recipes yet — add one below.',
          style: miseMono(size: 12, color: MiseColors.muted),
        ),
      );
    }
    return ListView(
      children: [
        for (final r in recipes)
          _RecipeRow(recipe: r, filing: filing[r.id], onPick: onPick),
      ],
    );
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({
    required this.library,
    required this.matches,
    required this.onPick,
  });

  final List<Book> library;
  final bool Function(String title) matches;
  final ValueChanged<RecipeSummary> onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final b in library) ...[
          for (final s in b.sections)
            for (final r in s.recipes)
              if (matches(r.title))
                _RecipeRow(
                  recipe: r,
                  filing: (book: b.name, section: s.name),
                  onPick: onPick,
                ),
          for (final r in b.unsectioned)
            if (matches(r.title))
              _RecipeRow(
                recipe: r,
                filing: (book: b.name, section: null),
                onPick: onPick,
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
    required this.onPick,
  });

  final RecipeSummary recipe;
  final _Filing? filing;
  final ValueChanged<RecipeSummary> onPick;

  @override
  Widget build(BuildContext context) {
    final f = filing;
    final keeps = recipe.keepsForDays;
    final sub = [
      if (f != null) f.book,
      if (f?.section != null) f!.section!,
      if (keeps != null) 'keeps $keeps d',
      if (recipe.freezable) 'freezable',
    ].join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onPick(recipe),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: MiseColors.surface,
          border: Border.all(color: MiseColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const _RecipeThumb(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                    style: miseSerif(size: 16),
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: miseMono(size: 10, color: MiseColors.muted),
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

/// A placeholder recipe thumbnail (photos need Storage — deferred).
class _RecipeThumb extends StatelessWidget {
  const _RecipeThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: MiseColors.herbSoft,
        borderRadius: BorderRadius.circular(9),
      ),
      child: const Icon(
        FLucideIcons.cookingPot,
        size: 18,
        color: MiseColors.herb,
      ),
    );
  }
}
