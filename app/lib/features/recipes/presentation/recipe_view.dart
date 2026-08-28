/// The recipe page: grouped ingredients that scale live with a servings
/// control, plus the method — laid out as Ingredients / Method tabs.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/units.dart';
import '../data/recipe_providers.dart';
import '../domain/recipe.dart';
import '../domain/scaling.dart';
import 'format.dart';
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
              style: miseMono(size: 13, color: MiseColors.muted),
            ),
          ),
        );
      },
      data: (recipe) => recipe == null
          ? FScaffold(
              child: Center(
                child: Text('Recipe not found', style: miseSerif(size: 20)),
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

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        prefixes: [
          FHeaderAction.back(
            // After Save's `context.go`, the stack is replaced and there is
            // nothing to pop, so fall back to the list.
            onPress: () => context.canPop() ? context.pop() : context.go('/'),
          ),
        ],
        suffixes: [
          FPopoverMenu(
            menu: [
              FItemGroup(
                children: [
                  FItem(
                    prefix: const Icon(FLucideIcons.pencil),
                    title: const Text('Edit'),
                    onPress: () => context.push('/recipes/${recipe.id}/edit'),
                  ),
                  FItem(
                    prefix: const Icon(FLucideIcons.trash2),
                    title: const Text('Delete'),
                    onPress: () => _confirmDelete(context, ref),
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
          Text(_breadcrumb(recipe), style: miseLabel(color: MiseColors.herb)),
          const SizedBox(height: 8),
          Text(title, style: miseSerif(size: 33, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          _Chips(recipe: recipe),
          const SizedBox(height: 20),
          _TabBar(index: tab.value, onChanged: (i) => tab.value = i),
          const SizedBox(height: 4),
          if (tab.value == 0)
            _IngredientsTab(
              recipe: recipe,
              servings: servings.value,
              onServings: (v) => servings.value = v,
            )
          else
            _MethodTab(steps: recipe.steps),
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
    final ok = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        title: Text('Delete recipe?', style: miseSerif(size: 20)),
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
      await ref.read(recipeRepositoryProvider).deleteRecipe(recipe.id);
      if (context.mounted) context.go('/');
    }
  }
}

/// A plain-text tab bar with an underline under the active tab (no filled
/// segmented pill), matching the design board.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _labels = ['Ingredients', 'Method'];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MiseColors.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++) ...[
            _TabButton(
              label: _labels[i],
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
              color: selected ? MiseColors.ink : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            label,
            style: miseSans(
              size: 16,
              color: selected ? MiseColors.ink : MiseColors.muted,
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
      Container(height: 1, color: MiseColors.line);
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
                  colors: [MiseColors.fresh, MiseColors.aging, MiseColors.gone],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(text, style: miseMono(size: 11, color: MiseColors.herbDeep)),
        ],
      ),
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
                style: miseSerif(
                  size: 18,
                  color: MiseColors.herbDeep,
                  weight: FontWeight.w400,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            const _Hairline(),
          ],
          for (final item in group.items) _LineRow(item: item),
        ],
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
        color: MiseColors.paper,
        border: Border.all(color: MiseColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(
              'Scale\nto',
              style: miseSans(size: 13, color: MiseColors.muted),
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
                    style: miseSans(size: 17, weight: FontWeight.w700),
                  ),
                  Text(
                    '·${formatQuantity(factor)}×',
                    style: miseMono(size: 13, color: MiseColors.muted),
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

class _LineRow extends StatelessWidget {
  const _LineRow({required this.item});

  final LineItem item;

  @override
  Widget build(BuildContext context) {
    final name = item.note == null
        ? item.ingredientName
        : '${item.ingredientName}, ${item.note}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(name, style: miseSans(size: 16))),
              const SizedBox(width: 12),
              Text(
                _measure(item),
                textAlign: TextAlign.right,
                style: miseMono(size: 16),
              ),
            ],
          ),
        ),
        const _Hairline(),
      ],
    );
  }

  String _measure(LineItem item) {
    final qty = formatQuantity(item.quantity);
    // A named measure reads as "2 potato, large" (falls back to the stored
    // count unit below while the measure row hasn't synced).
    final measure = item.measure;
    if (measure != null) {
      return qty.isEmpty ? measure.label : '$qty ${measure.label}';
    }
    if (item.unit.family == UnitFamily.count) {
      return qty.isEmpty ? item.unit.label : qty;
    }
    if (qty.isEmpty) return item.unit.label;
    return '$qty ${item.unit.label}';
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No method written yet.',
          style: miseMono(size: 12, color: MiseColors.muted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const FDivider(),
          _StepRow(number: i + 1, text: steps[i]),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});

  final int number;
  final String text;

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
              color: MiseColors.ink,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: miseMono(
                size: 12,
                color: MiseColors.paper,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(text, style: miseSans(size: 16, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}
