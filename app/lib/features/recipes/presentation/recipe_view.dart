/// The recipe page: grouped ingredients that scale live with a servings
/// control, the method, and the per-serving macro panel ([RecipeMacroPanel]).
///
/// Tabs on a phone (plus "Used in · N" while other recipes list this one as a
/// component); two columns with no tabs at [AnsiLayout.expanded], built from
/// the same widgets. Opened from a week that plans it (`?week=`), the
/// ingredients show that week's effective lines and the `optional` tag becomes
/// the switch that writes the week's include row.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/macros.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_stepper_row.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/cost_words.dart';
import '../../../shared/format.dart';
import '../../../shared/freshness_bar.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/incomplete_macros.dart';
import '../../../shared/method_step_text.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../ingredients/domain/price.dart';
import '../../ingredients/presentation/ingredient_detail_view.dart'
    show ingredientDetailRoute;
import '../../planning/data/planning_providers.dart';
import '../../planning/presentation/week_recipe_band.dart';
import '../../planning/presentation/week_variant_format.dart';
import '../../planning/presentation/week_view_models.dart';
import '../data/recipe_providers.dart';
import '../domain/effective_lines.dart';
import '../domain/line_display.dart';
import '../domain/line_override.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_cost.dart';
import '../domain/recipe_macros.dart';
import '../domain/recipe_repository.dart';
import '../domain/scaling.dart';
import 'component_format.dart';
import 'ingredient_line.dart';
import 'recipe_chip.dart';
import 'recipe_cost_panel.dart';
import 'recipe_macro_panel.dart';
import 'recipe_view_models.dart';

class RecipeView extends ConsumerWidget {
  const RecipeView({required this.recipeId, this.weekKey, super.key});

  final String recipeId;

  /// The week this page was opened from (`?week=YYYY-MM-DD`). Null from the
  /// Library, and treated as null when that week does not plan this recipe; see
  /// [_RecipeBody].
  final String? weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeByIdProvider(recipeId));

    return async.when(
      loading: () => const FScaffold(child: Center(child: FCircularProgress())),
      error: (e, st) => FScaffold(
        child: AnsiErrorState(
          what: 'this recipe',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(recipeByIdProvider(recipeId)),
        ),
      ),
      data: (recipe) => recipe == null
          ? FScaffold(
              child: Center(
                child: Text(
                  'Recipe not found',
                  style: ansiSerif(size: AnsiType.heading),
                ),
              ),
            )
          : _RecipeBody(recipe: recipe, weekKey: weekKey),
    );
  }
}

class _RecipeBody extends HookConsumerWidget {
  const _RecipeBody({required this.recipe, this.weekKey});

  final Recipe recipe;

  /// See [RecipeView.weekKey].
  final String? weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servings = useState(recipe.servingsBase);
    final tab = useState(0);
    // What the cook has ticked off in the method. Page-local and unsynced; the
    // keys are positional (`s2`, `s2:c0`, see [_MethodTab]).
    final struck = useState(const <String>{});
    void toggleStruck(String key) {
      final next = {...struck.value};
      if (!next.remove(key)) next.add(key);
      struck.value = next;
    }

    // Both columns are on screen at expanded: no tab bar, the scaler and `⋯` in
    // the hero, the back-links under the ingredients column.
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    // The back-links tab exists only while something points here. A
    // still-loading query reads as no back-links.
    final usesAsync = ref.watch(recipeUsedInProvider(recipe.id));
    final uses = usesAsync.asData?.value ?? const <RecipeUse>[];
    // An errored query keeps the tab and says so inside it: "nothing points
    // here" and "could not find out" are different answers.
    final usesFailed = usesAsync.hasError;
    final tabs = [
      'Ingredients',
      'Method',
      if (usesFailed)
        'Used in'
      else if (uses.isNotEmpty)
        usedInTabLabel(uses.length),
    ];
    // The last back-link can go while the tab is open; fall back rather than
    // stare at a pane that no longer exists.
    final index = tab.value < tabs.length ? tab.value : 0;
    // Two session-held reading postures; see [ShowLineFigures] and
    // [CostReading].
    final lineFigures = ref.watch(showLineFiguresProvider);
    final costReading = ref.watch(costReadingProvider);
    // A planned arrival: the link names a week and that week still plans this
    // recipe. The page asks the week rather than trusting the parameter, since
    // a stale link can outlive the meal.
    final key = weekKey;
    final placement = key == null
        ? const (days: <int>[], edited: false)
        : ref.watch(weekRecipePlacementProvider(recipe.id, key));
    final plannedWeek = placement.days.isEmpty ? null : key;
    // What that week says about this recipe: its overrides and its own
    // re-summation (absent while the week varies nothing).
    final overrides = plannedWeek == null
        ? const <LineOverride>[]
        : ref
                  .watch(weekOverridesForProvider(plannedWeek))
                  .asData
                  ?.value[recipe.id] ??
              const <LineOverride>[];
    final weekSummary = plannedWeek == null
        ? null
        : ref
              .watch(weekVariantMacrosForProvider(plannedWeek))
              .asData
              ?.value[recipe.id];
    // Cost figures layered the same way: the week's when it varies the recipe,
    // the Library's otherwise. Absent while the ledger loads.
    final weekCost = plannedWeek == null
        ? null
        : ref
              .watch(weekVariantCostsForProvider(plannedWeek))
              .asData
              ?.value[recipe.id];
    final cost =
        weekCost ?? ref.watch(recipeCostsProvider).asData?.value[recipe.id];

    // Hero, ingredients, method and back-links are built once here and placed
    // by the band.
    final hero = _Hero(
      recipe: recipe,
      // The band under the title: which days of the originating week cook this,
      // and whether the week varies it.
      band: plannedWeek == null
          ? null
          : PlannedThisWeekBand(days: placement.days, edited: placement.edited),
    );
    final menu = _RecipeMenu(
      recipe: recipe,
      showLineFigures: lineFigures,
      // At expanded the ingredients are always on screen, so the toggle is
      // always about something visible.
      offerLineFigures: wide || index == 0,
      plannedWeek: plannedWeek,
      days: placement.days,
      inHeader: !wide,
    );
    final factor = scaleFactorFor(recipe, servings.value);
    final scaler = _ScaleControl(
      servings: servings.value,
      factor: factor,
      onChanged: (v) => servings.value = v,
    );
    final ingredients = _IngredientsTab(
      recipe: recipe,
      servings: servings.value,
      onServings: (v) => servings.value = v,
      showLineFigures: lineFigures,
      costReading: costReading,
      cost: cost,
      onReading: (wantCost) =>
          ref.read(costReadingProvider.notifier).show(cost: wantCost),
      // The scaler is in the hero at expanded, where it reaches both columns.
      showScaler: !wide,
      weekStart: plannedWeek == null
          ? null
          : weekStartOfKey(plannedWeek, ref.watch(weekShapeProvider)),
      overrides: overrides,
      weekSummary: weekSummary,
    );
    final method = _MethodTab(
      recipe: recipe,
      servings: servings.value,
      struck: struck.value,
      onToggle: toggleStruck,
      // The lines this week leaves out, so the method's chips can say so too.
      weekExcluded: {
        for (final o in overrides)
          if (o.action == LineOverrideAction.exclude)
            if (o.recipeLineItemId != null) o.recipeLineItemId!,
      },
    );
    final backLinks = usesFailed
        ? AnsiErrorState(
            what: 'what this is used in',
            error: usesAsync.error!,
            stackTrace: usesAsync.stackTrace,
            onRetry: () => ref.invalidate(recipeUsedInProvider(recipe.id)),
          )
        : _UsedInList(uses: uses);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        prefixes: [
          FHeaderAction.back(
            // A cold deep link has no page beneath to pop. With `?week=` the
            // referring tab is the Week, read from the raw parameter whether or
            // not the meal is still planned.
            onPress: () =>
                ansiBack(context, home: weekKey == null ? '/' : '/week'),
          ),
        ],
        // At expanded the same menu hangs in the hero beside the scaler, which
        // is where the width gives it room. One door either way.
        suffixes: [if (!wide) menu],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ansiPageGutter,
          4,
          ansiPageGutter,
          32,
        ),
        children: wide
            ? [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: hero),
                    const SizedBox(width: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: _kScalerWidth, child: scaler),
                        const SizedBox(width: 12),
                        menu,
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _Hairline(),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _kIngredientsColumn,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _ColumnHeading('Ingredients'),
                          ingredients,
                          // The back-links close the ingredients column, only
                          // while something points here.
                          if (usesFailed || uses.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            _ColumnHeading(
                              usesFailed
                                  ? 'Used in'
                                  : usedInTabLabel(uses.length),
                            ),
                            backLinks,
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [const _ColumnHeading('Method'), method],
                      ),
                    ),
                  ],
                ),
              ]
            : [
                hero,
                const SizedBox(height: 20),
                _TabBar(
                  labels: tabs,
                  index: index,
                  onChanged: (i) => tab.value = i,
                  // The Method tab's chips carry scaled numbers, so the tab bar
                  // says what they are scaled to. Same servings state as the
                  // scaler.
                  trailing: index != 1
                      ? null
                      : Text(
                          'for ${formatQuantity(servings.value)} servings · '
                          '${formatQuantity(factor)}×',
                          style: ansiMono(size: 11, color: AnsiColors.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                const SizedBox(height: 4),
                if (index == 0)
                  ingredients
                else if (index == 1)
                  method
                else
                  backLinks,
              ],
      ),
    );
  }
}

/// The ingredients column's fixed width at [AnsiLayout.expanded]; the method
/// column takes the rest.
const double _kIngredientsColumn = 340;

/// The scaler's width: enough for "12 servings" on one line.
const double _kScalerWidth = 300;

/// The page's top: book line, title, week band and chips. At expanded it also
/// holds the scaler and the `⋯`.
class _Hero extends StatelessWidget {
  const _Hero({required this.recipe, this.band});

  final Recipe recipe;

  /// The planned-this-week line, between the title and the chips. Null from
  /// the Library, where there is no week to state.
  final Widget? band;

  @override
  Widget build(BuildContext context) {
    final title = recipe.title.isEmpty ? 'Untitled recipe' : recipe.title;
    final band = this.band;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_breadcrumb(recipe), style: ansiLabel(color: AnsiColors.herb)),
        const SizedBox(height: 8),
        Text(
          title,
          style: ansiSerif(size: AnsiType.display, weight: FontWeight.w700),
        ),
        if (band != null) ...[const SizedBox(height: 10), band],
        const SizedBox(height: 12),
        _Chips(recipe: recipe),
      ],
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
}

/// A column's name at [AnsiLayout.expanded] — the micro-label over a rule that
/// the tab bar's underline is doing on a phone.
class _ColumnHeading extends StatelessWidget {
  const _ColumnHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label.toUpperCase(), style: ansiLabel()),
        ),
        const _Hairline(),
      ],
    );
  }
}

/// The page's menu: favourite, per-line figures, Edit and, from a week, that
/// week's editor. In the header on a phone, in the hero at
/// [AnsiLayout.expanded].
class _RecipeMenu extends ConsumerWidget {
  const _RecipeMenu({
    required this.recipe,
    required this.showLineFigures,
    required this.offerLineFigures,
    required this.plannedWeek,
    required this.days,
    required this.inHeader,
  });

  final Recipe recipe;

  /// Whether the trigger is an [FHeaderAction], which asserts on an [FHeader]
  /// ancestor the hero does not have.
  final bool inHeader;

  /// Whether the lines are currently printing their own figures — the item
  /// says what the tap will do.
  final bool showLineFigures;

  /// Whether to offer that toggle at all: only where the lines it changes are
  /// on screen.
  final bool offerLineFigures;

  /// The week that plans this recipe, once checked against the week itself.
  /// Null from the Library, and then the second door does not exist.
  final String? plannedWeek;

  /// Which days of that week cook it, for the door's own label.
  final List<int> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final plannedWeek = this.plannedWeek;
    return FPopoverMenu(
      // `menuBuilder`, not `menu`: an item has to be able to dismiss the
      // menu it was picked from before it navigates or opens a dialog.
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            // The favourite star, household-shared like the recipe itself.
            FItem(
              prefix: Icon(favorite ? FLucideIcons.starOff : FLucideIcons.star),
              title: Text(favorite ? 'Unfavorite' : 'Favorite'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(
                  ref.write(
                    context,
                    favorite ? 'unfavourite it' : 'favourite it',
                    () => ref
                        .read(recipeRepositoryProvider)
                        .setFavorite(recipe.id, !favorite),
                  ),
                );
              },
            ),
            // One item for both readings: the lines print whichever figures the
            // panel is reading.
            if (offerLineFigures)
              FItem(
                prefix: const Icon(FLucideIcons.sigma),
                title: Text(
                  showLineFigures ? 'Hide line figures' : 'Show line figures',
                ),
                onPress: () {
                  unawaited(controller.hide());
                  ref.read(showLineFiguresProvider.notifier).toggle();
                },
              ),
            // Named "Edit recipe" only where the week door stands beside it.
            FItem(
              prefix: const Icon(FLucideIcons.pencil),
              title: Text(plannedWeek == null ? 'Edit' : 'Edit recipe'),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce('/recipes/${recipe.id}/edit');
              },
            ),
            // The door into week mode from the page. It names the days it
            // covers, because those are what it changes.
            if (plannedWeek != null)
              FItem(
                prefix: const Icon(FLucideIcons.calendarCog),
                title: Text(
                  editForThisWeekItem(
                    days,
                    ref.watch(weekShapeProvider).shortLabels,
                    weekKey: plannedWeek,
                  ),
                ),
                onPress: () {
                  unawaited(controller.hide());
                  context.pushOnce(
                    '/recipes/${recipe.id}/edit?week=$plannedWeek',
                  );
                },
              ),
            FItem(
              prefix: const Icon(FLucideIcons.trash2),
              title: const Text('Delete'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_confirmDelete(context, ref, recipe));
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => inHeader
          ? FHeaderAction(
              icon: const Icon(FLucideIcons.ellipsis),
              onPress: controller.toggle,
            )
          // In the hero there is no header to be an action of, so the glyph
          // stands on its own, sized to the row it sits in.
          : AnsiTap(
              onTap: controller.toggle,
              semanticsLabel: 'More',
              color: AnsiColors.muted,
              padding: const EdgeInsets.all(6),
              child: const Icon(FLucideIcons.ellipsis, size: 18),
            ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Recipe recipe,
) async {
  // A recipe something points at is not deleted, and the refusal names the
  // count. Read the keepAlive repository, not cached rows, so the answer is
  // true at the tap.
  //
  // Guarded: a check that threw must not read as "nothing points here". What
  // runs after an awaited dialog goes through the container and the host
  // (`hostContextOf`), never `ref`.
  final repository = ref.read(recipeRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final uses = await container.write(
    host,
    'check what uses this recipe',
    () => repository.usedIn(recipe.id),
  );
  if (uses == null) return;
  if (uses.isNotEmpty) {
    await refuseAnsi(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      host.context,
      title: 'Can’t delete this recipe',
      body: deleteRefusalText(
        recipes: uses.map((u) => u.recipeId).toSet().length,
        lines: uses.length,
      ),
    );
    return;
  }

  final ok = await askAnsi(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    title: 'Delete recipe?',
    body: 'This removes it from your recipes.',
    confirm: 'Delete',
    destructive: true,
  );
  if (ok) {
    final deleted = await container.writeOk(
      host,
      'delete that recipe',
      () => repository.deleteRecipe(recipe.id),
    );
    if (!deleted) return;
    // `go`, not a replacement: this page is pushed above the tab shell, so
    // `go('/')` lands on the Library branch, while `pushReplacement('/')` would
    // stack a second shell.
    if (context.mounted) context.go('/');
  }
}

/// A plain-text tab bar with an underline under the active tab (no filled
/// segmented pill), matching the design board.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.trailing,
  });

  /// Two tabs, or three while something points at this recipe.
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// A fact about the open tab at the far end of the bar (what the Method's
  /// chips are scaled to), or null.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AnsiColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _TabButton(
              label: labels[i],
              selected: index == i,
              onTap: () => onChanged(i),
            ),
            const SizedBox(width: 28),
          ],
          if (trailing != null)
            Expanded(
              child: Padding(
                // The tab labels' own bottom padding, so the two sit on one
                // baseline rather than the bar's edge.
                padding: const EdgeInsets.only(bottom: 10),
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ),
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
    final cook = recipe.cookTimeSeconds;
    final total = recipe.totalTimeSeconds;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (keeps != null) _Chip('keeps $keeps d', freshness: true),
        if (recipe.freezable)
          _Chip(freezer == null ? 'freezable' : 'freezable · $freezer d'),
        _Chip('serves ${formatQuantity(recipe.servingsBase)}'),
        // What one batch makes; a second pill when the yield states two
        // denominations. Independent of serves.
        for (final label in yieldPillLabels(recipe.yields)) _Chip(label),
        // The printed times, each only when the page (or a human) stated it —
        // never a derived or invented one.
        if (cook != null) _Chip('cook ${formatDuration(cook)}'),
        if (total != null) _Chip('${formatDuration(total)} total'),
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
          if (freshness) ...[const FreshnessBar(), const SizedBox(width: 8)],
          Text(text, style: ansiMono(size: 11, color: AnsiColors.herbDeep)),
        ],
      ),
    );
  }
}

/// The "Used in · N" back-links: one row per referencing line (the parent
/// recipe, what its line asks for, and that as a share of a batch), each
/// pushing the parent. An amount that does not resolve says why.
class _UsedInList extends StatelessWidget {
  const _UsedInList({required this.uses});

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
            onTap: () => context.pushOnce('/recipes/${use.recipeId}'),
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
                            measureLabel: use.measureLabel,
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

class _IngredientsTab extends ConsumerWidget {
  const _IngredientsTab({
    required this.recipe,
    required this.servings,
    required this.onServings,
    required this.showLineFigures,
    required this.costReading,
    required this.cost,
    required this.onReading,
    required this.showScaler,
    required this.weekStart,
    required this.overrides,
    required this.weekSummary,
  });

  final Recipe recipe;
  final double servings;
  final ValueChanged<double> onServings;

  /// Whether each line prints its own figures under its name (the `⋯`
  /// toggle). WHICH figures is [costReading]'s answer.
  final bool showLineFigures;

  /// Whether the panel — and therefore the lines — reads COST rather than
  /// macros.
  final bool costReading;

  /// The recipe's honest cost, or null while the ledger is loading.
  final RecipeCostSummary? cost;

  /// Flips the panel's reading; the argument is what it is to BECOME.
  final ValueChanged<bool> onReading;

  /// Whether the servings scaler opens the list. False at
  /// [AnsiLayout.expanded], where it sits in the hero.
  final bool showScaler;

  /// The first day of the week this page was opened from, once that week was
  /// found to plan the recipe. Null from the Library.
  final DateTime? weekStart;

  /// That week's deltas for this recipe, in stored order. Empty from the
  /// Library.
  final List<LineOverride> overrides;

  /// The week's own re-summation of the recipe, or null when the week varies
  /// nothing about it — the Library's figure is then exactly right.
  final RecipeMacroSummary? weekSummary;

  /// Opens the fix a named line's reason implies.
  ///
  /// An ingredient problem (stub, unknown row, missing density or piece weight)
  /// opens the ingredient's form; the nested reasons open the sub-recipe; a
  /// missing amount routes to the editor, since this page is read-only.
  void _fix(BuildContext context, MacroLineNote note) {
    final line = _lineById(recipe)[note.lineId];
    switch (note.reason) {
      case MacroLineReason.stubIngredient:
      case MacroLineReason.unknownIngredient:
      case MacroLineReason.needsDensity:
      case MacroLineReason.needsWeight:
        final id = line?.ingredientId;
        // Lands on the editing posture: the marker names a field to fill.
        if (id != null) context.pushOnce(ingredientDetailRoute(id, edit: true));
      case MacroLineReason.subRecipeUnresolved:
      case MacroLineReason.subRecipeIncomplete:
        final id = line?.subRecipeId;
        if (id != null) context.pushOnce('/recipes/$id');
      case MacroLineReason.noAmount:
      // A retired row's fix is not on the row — the row is gone. It is the
      // LINE, so the door is the editor, where the identity cell picks again.
      case MacroLineReason.removedIngredient:
        context.pushOnce('/recipes/${recipe.id}/edit');
      case MacroLineReason.imprecise:
      case MacroLineReason.optional:
        break; // excluded by rule — there is nothing to fix
    }
  }

  /// The muted second line under a row when the toggle is on: the row's macros
  /// at the amount shown, or the reason there are none.
  ///
  /// Figures are the summation's per-line record scaled by the page's factor,
  /// so nothing is converted twice. A folded multi-use row prints figures only
  /// when every use joined. [marked] and optional rows say nothing here; they
  /// already say it elsewhere.
  ({Macros? figures, String? note}) _macroLine(
    LineUses uses,
    RecipeMacroSummary summary,
    double factor, {
    required bool marked,
  }) {
    const nothing = (figures: null, note: null);
    if (!showLineFigures || costReading) return nothing;
    // `fiber: 0` is the additive identity, so folding one use does not strip
    // the fibre a row does state ([Macros.fiber]).
    var total = const Macros(kcal: 0, protein: 0, carb: 0, fat: 0, fiber: 0);
    for (final use in uses.uses) {
      final contribution = summary.lineMacros[use.id];
      if (contribution == null) {
        if (marked) return nothing;
        final reason = summary.notes
            .where((n) => n.lineId == use.id)
            .firstOrNull
            ?.reason;
        return reason == null || reason == MacroLineReason.optional
            ? nothing
            : (figures: null, note: incompleteLineNote(reason));
      }
      total += contribution;
    }
    return (figures: total.scaledBy(factor), note: null);
  }

  /// The second line when the panel is reading cost: what the row comes to at
  /// the amount shown, the unit price, and where and when, or the reason
  /// the row was left out. Scaled from the summation's per-line record, like
  /// [_macroLine].
  String? _costLine(LineUses uses, double factor) {
    final summary = cost;
    if (!showLineFigures || !costReading || summary == null) return null;
    var total = 0.0;
    UnitPrice? price;
    for (final use in uses.uses) {
      final contribution = summary.lineCosts[use.id];
      if (contribution == null) {
        final reason = [
          ...summary.unpriced,
          ...summary.notCounted,
        ].where((n) => n.lineId == use.id).firstOrNull?.reason;
        return reason == null ? null : costLineNote(reason);
      }
      total += contribution.cents;
      price ??= contribution.price;
    }
    return lineCostText(
      CostLine(cents: total, price: price),
      factor: factor,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factor = scaleFactorFor(recipe, servings);
    final summary = weekSummary ?? recipe.macros ?? const RecipeMacroSummary();
    // The panel's names and the rows' markers come from ONE list, keyed by
    // line id — one lookup, never a second computation that could disagree.
    final markers = {
      for (final note in fixableNotes(summary))
        if (note.lineId != null) note.lineId!: note,
    };
    final lines = [for (final group in recipe.groups) ...group.items];
    // The week's answer per line: struck where left out, the week's values
    // where stated, additions at the end. An include keeps the line's
    // `optional` flag here so the tag stays, lit.
    final entries = {
      for (final entry in draftLines(lines, overrides)) entry.line.id: entry,
    };
    final included = {
      for (final o in overrides)
        if (o.action == LineOverrideAction.include)
          if (o.recipeLineItemId != null) o.recipeLineItemId!,
    };
    final added = [
      for (final entry in entries.values)
        if (entry.added) scaleLineItem(entry.line, factor),
    ];

    final toggle = FiguresToggle(cost: costReading, onChanged: onReading);

    Widget line(({LineUses uses, bool excluded}) row) => _line(
      context,
      ref,
      row: row,
      summary: summary,
      markers: markers,
      included: included,
      factor: factor,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showScaler) ...[
          const SizedBox(height: 16),
          // A stretched stepper would spread its slack between the buttons, so
          // it is capped at the hero's width.
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kScalerWidth),
              child: _ScaleControl(
                servings: servings,
                factor: factor,
                onChanged: onServings,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
        for (final group in recipe.groups) ...[
          if (group.name != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                // The stored name verbatim — authors write the full heading
                // ("for the curry", design board), so no prefix is added here.
                group.name!,
                style: ansiSerif(
                  size: AnsiType.row,
                  color: AnsiColors.herbDeep,
                  weight: FontWeight.w400,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            const _Hairline(),
          ],
          for (final row in _weekRows(group.items, entries, factor)) line(row),
        ],
        // An override carries no group, so an added line has none to land in:
        // it sits after the last one, exactly where week mode puts it.
        for (final uses in groupLineUses(added))
          line((uses: uses, excluded: false)),
        // Below the list and clear of the scaler: the per-serving figure is not
        // driven by the stepper.
        const SizedBox(height: 22),
        // One strip, two readings of the same lines (ADR-0017).
        if (costReading)
          RecipeCostPanel(summary: cost, header: toggle)
        else
          RecipeMacroPanel(
            summary: weekSummary ?? recipe.macros,
            header: toggle,
            onFix: (note) => _fix(context, note),
            includedNames: [
              for (final item in lines)
                if (included.contains(item.id))
                  item.subRecipe?.title ?? item.ingredientName,
            ],
            // The week's summation drops optional lines before it runs, so only
            // the Library's summary can name them.
            optionalNames: weekSummary == null
                ? const []
                : droppedNames(
                    effectiveLines(lines, overrides: overrides),
                    LineDropReason.optional,
                  ),
          ),
      ],
    );
  }

  /// One display row with the week's answer on it: its doors, its macros and,
  /// where a week owns the page, the tag as the include switch.
  Widget _line(
    BuildContext context,
    WidgetRef ref, {
    required ({LineUses uses, bool excluded}) row,
    required RecipeMacroSummary summary,
    required Map<String, MacroLineNote> markers,
    required Set<String> included,
    required double factor,
  }) {
    final uses = row.uses;
    // A line this week does not cook is in no total, so it is waiting on
    // nothing and contributes nothing: it says one thing, that it is out.
    final note = row.excluded ? null : _firstNote(uses, markers);
    final macros = row.excluded
        ? const (figures: null, note: null)
        : _macroLine(uses, summary, factor, marked: note != null);
    // Under Cost the line says what it costs, the price behind it and where
    // that price came from — or, in the strip's own words, why it has none.
    final costNote = row.excluded ? null : _costLine(uses, factor);
    // The identity cell already says `ingredient removed · pick again`, so the
    // amount column does not repeat it.
    final saidInPlace = note?.reason == MacroLineReason.removedIngredient;
    // One tap is one intent: a folded row's every optional use is ticked in
    // together, because the row is what the person answered about.
    final optionalIds = [
      for (final use in uses.uses)
        if (use.optional || included.contains(use.id)) use.id,
    ];
    final week = weekStart;
    return RecipeIngredientLine(
      uses: uses,
      struck: row.excluded,
      included: uses.uses.any((u) => included.contains(u.id)),
      onToggleOptional: week == null || row.excluded || optionalIds.isEmpty
          ? null
          : (include) {
              final repository = ref.read(weekVariantRepositoryProvider);
              unawaited(
                ref.write(
                  context,
                  include ? 'include it this week' : 'leave it out this week',
                  // Sequential: each call is a read-modify-write of the
                  // recipe's whole set for that week.
                  () async {
                    for (final id in optionalIds) {
                      await repository.setLineIncluded(
                        week,
                        recipe.id,
                        id,
                        included: include,
                      );
                    }
                  },
                ),
              );
            },
      // A component's chip opens its target's page and an ingredient's name
      // opens its own. A struck line has neither.
      onOpenSubRecipe: row.excluded
          ? null
          : (id) => context.pushOnce('/recipes/$id'),
      onOpenIngredient: row.excluded
          ? null
          : (id) => context.pushOnce(ingredientDetailRoute(id)),
      macroMarker: note == null || saidInPlace
          ? null
          : incompleteLineNote(note.reason),
      macroLine: macros.figures,
      macroLineNote: macros.note ?? costNote,
      onFixMacro: note == null || saidInPlace
          ? null
          : () => _fix(context, note),
    );
  }
}

/// One group's rows in stored order as this week cooks them, scaled and folded
/// by identity. A line the week leaves out never joins a row that is still
/// cooked.
List<({LineUses uses, bool excluded})> _weekRows(
  List<LineItem> items,
  Map<String, WeekDraftLine> entries,
  double factor,
) {
  final drawn = <String, ({LineItem line, bool excluded})>{};
  for (final item in items) {
    final entry = entries[item.id];
    // A line the recipe lost while the page was open (the other phone's edit,
    // arriving mid-read) is simply not drawn.
    if (entry == null) continue;
    drawn[item.id] = (
      line: scaleLineItem(entry.line, factor),
      excluded: entry.excluded,
    );
  }
  final folded = {
    for (final uses in groupLineUses([
      for (final item in items)
        if (drawn[item.id] case (line: final line, excluded: false)) line,
    ]))
      uses.uses.first.id: uses,
  };
  final rows = <({LineUses uses, bool excluded})>[];
  for (final item in items) {
    final row = drawn[item.id];
    if (row == null) continue;
    if (row.excluded) {
      rows.add((
        uses: LineUses(
          ingredientId: row.line.ingredientId,
          subRecipeId: row.line.subRecipeId,
          uses: [row.line],
        ),
        excluded: true,
      ));
    } else {
      // Every folded row is emitted once, at its first use.
      final uses = folded[item.id];
      if (uses != null) rows.add((uses: uses, excluded: false));
    }
  }
  return rows;
}

/// The recipe's line items by id, for resolving a macro note's `lineId`. Read
/// off the unscaled recipe; scaling keeps ids.
Map<String, LineItem> _lineById(Recipe recipe) => {
  for (final group in recipe.groups)
    for (final item in group.items) item.id: item,
};

/// The first note that names any of a display row's sibling lines.
MacroLineNote? _firstNote(LineUses uses, Map<String, MacroLineNote> markers) {
  for (final use in uses.uses) {
    final note = markers[use.id];
    if (note != null) return note;
  }
  return null;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: AnsiStepperRow(
          small: true,
          leading: Expanded(
            child: Text(
              'Scale\nto',
              style: ansiSans(size: 13, color: AnsiColors.muted),
            ),
          ),
          onDecrement: servings > 1 ? () => onChanged(servings - 1) : null,
          onIncrement: () => onChanged(servings + 1),
          value: Expanded(
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
        ),
      ),
    );
  }
}

/// The method, with the cook's ticks on it.
///
/// Tapping a chip strikes it; tapping the row strikes the prose and every chip
/// in it, because a text decoration does not cross into widget spans.
/// Un-striking a step leaves each chip as it was. Keys are positional: `s2` for
/// the step, `s2:c0` for its nth chip.
class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.recipe,
    required this.servings,
    this.struck = const {},
    this.onToggle,
    this.weekExcluded = const {},
  });

  final Recipe recipe;
  final double servings;

  /// The struck keys, in the shape the class doc describes.
  final Set<String> struck;

  /// Toggles one of those keys. Null renders the method read-only.
  final ValueChanged<String>? onToggle;

  /// Line ids this week leaves out — muted in the method, never ruled through.
  final Set<String> weekExcluded;

  /// The chip ordinals struck within step [index].
  Set<int> _struckChips(int index) {
    final prefix = 's$index:c';
    return {
      for (final key in struck)
        if (key.startsWith(prefix)) int.parse(key.substring(prefix.length)),
    };
  }

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
              struck: struck.contains('s$i'),
              onToggle: onToggle == null ? null : () => onToggle!('s$i'),
              child: MethodStepText(
                step: tokenized[i],
                lineById: lineById,
                factor: factor,
                stepStruck: struck.contains('s$i'),
                struckChips: onToggle == null ? null : _struckChips(i),
                onToggleChip: onToggle == null
                    ? null
                    : (chip) => onToggle!('s$i:c$chip'),
                weekExcluded: weekExcluded,
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
            struck: struck.contains('s$i'),
            onToggle: onToggle == null ? null : () => onToggle!('s$i'),
            child: Text(
              plain[i],
              style: struck.contains('s$i')
                  ? ansiSans(
                      size: 16,
                      height: 1.4,
                      color: AnsiColors.muted,
                    ).copyWith(decoration: TextDecoration.lineThrough)
                  : ansiSans(size: 16, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

/// One step: a mono digit in its own column, then the step. With [onToggle] the
/// whole row is the tap target; chips keep their own taps because a child is
/// hit-tested first.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.number,
    required this.child,
    this.struck = false,
    this.onToggle,
  });

  final int number;
  final Widget child;
  final bool struck;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Padding(
              // Sits the digit on the first line of the prose beside it.
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$number',
                style: ansiMono(
                  size: 13,
                  color: struck ? AnsiColors.muted : AnsiColors.herb,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: child),
        ],
      ),
    );
    final onToggle = this.onToggle;
    if (onToggle == null) return row;
    return FTappable(
      onPress: onToggle,
      semanticsLabel: 'step $number',
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
