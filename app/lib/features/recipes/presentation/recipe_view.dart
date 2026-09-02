/// The recipe page: grouped ingredients that scale live with a servings
/// control, plus the method — laid out as Ingredients / Method tabs.
///
/// The Ingredients tab closes with the per-serving macro panel (step 9,
/// [RecipeMacroPanel]) — the only number on this page the servings scaler
/// does not move.
///
/// **As a sub-recipe** (step 8.6 / D9, design board frame b) the page gains
/// two facts: a *"makes 1 cup"* pill beside serves (a second pill when the
/// yield states two denominations), and a THIRD tab — "Used in · N" — holding
/// the recipes that list this one as a component. The tab is conditional: it
/// renders only while the count is non-zero, so a recipe used in nothing keeps
/// the two-tab page it has always had. That same count is what D5's delete
/// refusal speaks — one query, two uses.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/method_step_text.dart';
import '../data/recipe_providers.dart';
import '../domain/line_display.dart';
import '../domain/recipe.dart';
import '../domain/recipe_repository.dart';
import '../domain/scaling.dart';
import 'component_format.dart';
import 'format.dart';
import 'ingredient_line.dart';
import 'recipe_chip.dart';
import 'recipe_macro_panel.dart';
import 'recipe_view_models.dart';

class RecipeView extends ConsumerWidget {
  const RecipeView({required this.recipeId, super.key});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeByIdProvider(recipeId));

    return async.when(
      loading: () => const FScaffold(child: Center(child: FCircularProgress())),
      error: (e, _) {
        debugPrint('recipe load failed: $e');
        return FScaffold(
          child: Center(
            child: Text(
              'Could not load this recipe.',
              style: ansiMono(size: 13, color: AnsiColors.muted),
            ),
          ),
        );
      },
      data: (recipe) => recipe == null
          ? FScaffold(
              child: Center(
                child: Text('Recipe not found', style: ansiSerif(size: 20)),
              ),
            )
          : _RecipeBody(recipe: recipe),
    );
  }
}

class _RecipeBody extends HookConsumerWidget {
  const _RecipeBody({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servings = useState(recipe.servingsBase);
    final tab = useState(0);
    final title = recipe.title.isEmpty ? 'Untitled recipe' : recipe.title;
    // The back-links: the tab exists only while something points here (D9),
    // and the same rows carry the count D5's delete refusal speaks. A
    // still-loading query reads as "nothing points here yet" — two tabs, the
    // page it has always had — never as a third empty pane.
    final uses =
        ref.watch(recipeUsedInProvider(recipe.id)).asData?.value ??
        const <RecipeUse>[];
    final tabs = [
      'Ingredients',
      'Method',
      if (uses.isNotEmpty) usedInTabLabel(uses.length),
    ];
    // The last back-link can go while the tab is open; fall back rather than
    // stare at a pane that no longer exists.
    final index = tab.value < tabs.length ? tab.value : 0;
    // The favorite flag lives on the list summary (the planner's Favorites
    // tab reads the same row), not the aggregate — resolve it from there.
    final favorite =
        ref
            .watch(recipeListProvider)
            .asData
            ?.value
            .where((r) => r.id == recipe.id)
            .firstOrNull
            ?.favorite ??
        false;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        prefixes: [
          FHeaderAction.back(
            // After Save's `context.go`, the stack is replaced and there is
            // nothing to pop, so fall back to the list.
            onPress: () =>
                context.canPop() ? context.pop() : context.goOnce('/'),
          ),
        ],
        suffixes: [
          FPopoverMenu(
            // `menuBuilder`, not `menu`: an item has to be able to dismiss the
            // menu it was picked from before it navigates or opens a dialog.
            menuBuilder: (_, controller, _) => [
              FItemGroup(
                children: [
                  // The Favorites-tab marking affordance (7.7): a star
                  // toggle, household-shared like the recipe itself.
                  FItem(
                    prefix: Icon(
                      favorite ? FLucideIcons.starOff : FLucideIcons.star,
                    ),
                    title: Text(favorite ? 'Unfavorite' : 'Favorite'),
                    onPress: () {
                      unawaited(controller.hide());
                      unawaited(
                        ref
                            .read(recipeRepositoryProvider)
                            .setFavorite(recipe.id, !favorite),
                      );
                    },
                  ),
                  FItem(
                    prefix: const Icon(FLucideIcons.pencil),
                    title: const Text('Edit'),
                    onPress: () {
                      unawaited(controller.hide());
                      context.pushOnce('/recipes/${recipe.id}/edit');
                    },
                  ),
                  FItem(
                    prefix: const Icon(FLucideIcons.trash2),
                    title: const Text('Delete'),
                    onPress: () {
                      unawaited(controller.hide());
                      unawaited(_confirmDelete(context, ref));
                    },
                  ),
                ],
              ),
            ],
            builder: (context, controller, _) => FHeaderAction(
              icon: const Icon(FLucideIcons.ellipsis),
              onPress: controller.toggle,
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(_breadcrumb(recipe), style: ansiLabel(color: AnsiColors.herb)),
          const SizedBox(height: 8),
          Text(title, style: ansiSerif(size: 33, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          _Chips(recipe: recipe),
          const SizedBox(height: 20),
          _TabBar(labels: tabs, index: index, onChanged: (i) => tab.value = i),
          const SizedBox(height: 4),
          if (index == 0)
            _IngredientsTab(
              recipe: recipe,
              servings: servings.value,
              onServings: (v) => servings.value = v,
            )
          else if (index == 1)
            _MethodTab(recipe: recipe, servings: servings.value)
          else
            _UsedInTab(uses: uses),
        ],
      ),
    );
  }

  /// The "BOOK · SECTION" eyebrow above the title (design board `.r-book`).
  /// Falls back to "RECIPE" when the recipe isn't filed yet.
  String _breadcrumb(Recipe recipe) {
    final crumbs = [recipe.bookName, recipe.sectionName]
        .where((s) => s != null && s.isNotEmpty)
        .map((s) => s!.toUpperCase())
        .join(' · ');
    return crumbs.isEmpty ? 'RECIPE' : crumbs;
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // D5, the 8.5 ingredient-delete ruling verbatim: a recipe something points
    // at is not deleted, and the refusal names the count — "used in 2 recipes"
    // is something a person can act on, "failed" is not. Read the repository
    // (keepAlive) rather than the tab's cached rows: the answer must be the
    // one that is true at the moment of the tap.
    final repository = ref.read(recipeRepositoryProvider);
    final uses = await repository.usedIn(recipe.id);
    if (!context.mounted) return;
    if (uses.isNotEmpty) {
      await showFDialog<void>(
        context: context,
        builder: (context, style, animation) => FDialog(
          animation: animation,
          title: Text('Can’t delete this recipe', style: ansiSerif(size: 20)),
          body: Text(
            deleteRefusalText(
              recipes: uses.map((u) => u.recipeId).toSet().length,
              lines: uses.length,
            ),
          ),
          actions: [
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final ok = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        title: Text('Delete recipe?', style: ansiSerif(size: 20)),
        body: const Text('This removes it from your recipes.'),
        actions: [
          FButton(
            variant: FButtonVariant.destructive,
            onPress: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
          FButton(
            variant: FButtonVariant.outline,
            onPress: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if ((ok ?? false) && context.mounted) {
      await repository.deleteRecipe(recipe.id);
      if (context.mounted) context.go('/');
    }
  }
}

/// A plain-text tab bar with an underline under the active tab (no filled
/// segmented pill), matching the design board.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  /// Two tabs, or three while something points at this recipe (D9).
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _TabButton(
              label: labels[i],
              selected: index == i,
              onTap: () => onChanged(i),
            ),
            const SizedBox(width: 28),
          ],
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AnsiColors.ink : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            label,
            style: ansiSans(
              size: 16,
              color: selected ? AnsiColors.ink : AnsiColors.muted,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// A tight 1px rule for the dense ingredient list (Forui's [FDivider] carries a
/// 16px vertical margin, too loose for the design board's ingredient rows).
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AnsiColors.line);
}

class _Chips extends StatelessWidget {
  const _Chips({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final keeps = recipe.keepsForDays;
    final freezer = recipe.freezerDays;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (keeps != null) _Chip('keeps $keeps d', freshness: true),
        if (recipe.freezable)
          _Chip(freezer == null ? 'freezable' : 'freezable · $freezer d'),
        _Chip('serves ${formatQuantity(recipe.servingsBase)}'),
        // What one batch MAKES (D2/D9) — a second pill continues the sentence
        // when the yield states two denominations ("makes 250 g" then
        // "· 16 tbsp").
        // Serves and makes are two independent facts; neither derives from
        // the other, so both sit here.
        for (final label in yieldPillLabels(recipe.yields)) _Chip(label),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.freshness = false});

  final String text;

  /// When set, prefixes the freshness-scale signature bar (fresh → gone).
  final bool freshness;

  @override
  Widget build(BuildContext context) {
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (freshness) ...[
            Container(
              width: 22,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  colors: [AnsiColors.fresh, AnsiColors.aging, AnsiColors.gone],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(text, style: ansiMono(size: 11, color: AnsiColors.herbDeep)),
        ],
      ),
    );
  }
}

/// The "Used in · N" tab (D9): one row per referencing LINE — the parent
/// recipe, what its line asks for, and that amount as a share of a batch —
/// each pushing the parent. An amount that does not resolve says why rather
/// than guessing a share (D2).
class _UsedInTab extends StatelessWidget {
  const _UsedInTab({required this.uses});

  final List<RecipeUse> uses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        for (final use in uses)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/recipes/${use.recipeId}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(kSubRecipeIcon, size: 15, color: AnsiColors.herb),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          use.title,
                          style: ansiSans(size: 15, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          usedInAmountLine(
                            quantity: use.quantity,
                            unit: use.unit,
                            amount: use.amount,
                          ),
                          style: ansiMono(size: 10.5, color: AnsiColors.muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    FLucideIcons.chevronRight,
                    size: 14,
                    color: AnsiColors.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _IngredientsTab extends StatelessWidget {
  const _IngredientsTab({
    required this.recipe,
    required this.servings,
    required this.onServings,
  });

  final Recipe recipe;
  final double servings;
  final ValueChanged<double> onServings;

  @override
  Widget build(BuildContext context) {
    final groups = scaleGroups(recipe, servings);
    final factor = scaleFactorFor(recipe, servings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        _ScaleControl(
          servings: servings,
          factor: factor,
          onChanged: onServings,
        ),
        const SizedBox(height: 20),
        for (final group in groups) ...[
          if (group.name != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                // The stored name verbatim — authors write the full heading
                // ("for the curry", design board), so no prefix is added here.
                group.name!,
                style: ansiSerif(
                  size: 18,
                  color: AnsiColors.herbDeep,
                  weight: FontWeight.w400,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            const _Hairline(),
          ],
          for (final uses in groupLineUses(group.items))
            RecipeIngredientLine(
              uses: uses,
              // A component's chip pushes its target's page (D7).
              onOpenSubRecipe: (id) => context.push('/recipes/$id'),
            ),
        ],
        // Below the list, as the design board's Recipe frame drew it: the
        // strip reads as the sum of the lines above it, and it stays clear of
        // the scaler — a static per-serving figure sitting under a stepper
        // would invite the reading that the stepper drives it (it does not).
        const SizedBox(height: 22),
        RecipeMacroPanel(summary: recipe.macros),
      ],
    );
  }
}

class _ScaleControl extends StatelessWidget {
  const _ScaleControl({
    required this.servings,
    required this.factor,
    required this.onChanged,
  });

  final double servings;
  final double factor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              'Scale\nto',
              style: ansiSans(size: 13, color: AnsiColors.muted),
            ),
            const Spacer(),
            FButton.icon(
              onPress: servings > 1 ? () => onChanged(servings - 1) : null,
              child: const Icon(FLucideIcons.minus),
            ),
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  Text(
                    '${formatQuantity(servings)} servings',
                    style: ansiSans(size: 17, weight: FontWeight.w700),
                  ),
                  Text(
                    '·${formatQuantity(factor)}×',
                    style: ansiMono(size: 13, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
            FButton.icon(
              onPress: () => onChanged(servings + 1),
              child: const Icon(FLucideIcons.plus),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({required this.recipe, required this.servings});

  final Recipe recipe;
  final double servings;

  @override
  Widget build(BuildContext context) {
    final tokenized = recipe.methodSteps;
    final plain = recipe.steps;
    if ((tokenized == null || tokenized.isEmpty) && plain.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No method written yet.',
          style: ansiMono(size: 12, color: AnsiColors.muted),
        ),
      );
    }

    // A tokenized (imported) method renders chips via the fold; the chips'
    // numbers come live off the line items, scaled with the servings control.
    if (tokenized != null && tokenized.isNotEmpty) {
      final lineById = {
        for (final g in recipe.groups)
          for (final i in g.items) i.id: i,
      };
      final factor = scaleFactorFor(recipe, servings);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          for (var i = 0; i < tokenized.length; i++) ...[
            if (i > 0) const FDivider(),
            _StepRow(
              number: i + 1,
              child: MethodStepText(
                step: tokenized[i],
                lineById: lineById,
                factor: factor,
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        for (var i = 0; i < plain.length; i++) ...[
          if (i > 0) const FDivider(),
          _StepRow(
            number: i + 1,
            child: Text(plain[i], style: ansiSans(size: 16, height: 1.4)),
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.child});

  final int number;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AnsiColors.ink,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: ansiMono(
                size: 12,
                color: AnsiColors.paper,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
