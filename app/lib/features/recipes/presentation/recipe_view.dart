/// The recipe page: grouped ingredients that scale live with a servings
/// control, plus the method — laid out as Ingredients / Method tabs.
///
/// The Ingredients tab closes with the per-serving macro panel (step 9,
/// [RecipeMacroPanel]) — the only number on this page the servings scaler
/// does not move.
///
/// The page's `⋯` menu can also print **each line's own macros under its
/// name**. These are the opposite of the panel: they are the line *as shown*,
/// so they DO move with the scaler. They read off the same summation the panel
/// does ([RecipeMacroSummary.lineMacros]) rather than converting anything
/// again, and a line the total left out says why instead of showing a zero.
///
/// **As a sub-recipe** (step 8.6 / D9, design board frame b) the page gains
/// two facts: a *"makes 1 cup"* pill beside serves (a second pill when the
/// yield states two denominations), and a THIRD tab — "Used in · N" — holding
/// the recipes that list this one as a component. The tab is conditional: it
/// renders only while the count is non-zero, so a recipe used in nothing keeps
/// the two-tab page it has always had. That same count is what D5's delete
/// refusal speaks — one query, two uses.
///
/// **Opened from a week that plans it, the page holds that week.** The
/// Ingredients tab draws the week's effective lines — a replaced amount as the
/// week states it, a line it leaves out struck, an added line after the last
/// group — and the `optional` tag becomes the switch that answers *this time,
/// yes*, writing the week's include row. The panel reads the week's own
/// re-summation, so ticking a line in recounts it. From the Library none of
/// that exists: where there is no week there is no decision to make.
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
import '../../../core/words.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_stepper_row.dart';
import '../../../shared/format.dart';
import '../../../shared/freshness_bar.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/incomplete_macros.dart';
import '../../../shared/method_step_text.dart';
import '../../../shared/write.dart';
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
import '../domain/recipe_macros.dart';
import '../domain/recipe_repository.dart';
import '../domain/scaling.dart';
import 'component_format.dart';
import 'ingredient_line.dart';
import 'recipe_chip.dart';
import 'recipe_macro_panel.dart';
import 'recipe_view_models.dart';

class RecipeView extends ConsumerWidget {
  const RecipeView({required this.recipeId, this.weekKey, super.key});

  final String recipeId;

  /// The week this page was opened FROM (`?week=YYYY-MM-DD`), carried by the
  /// Week's dish row and the Cook card's title. Null from the Library, and
  /// treated as null whenever that week does not actually plan this recipe —
  /// see [_RecipeBody].
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
                child: Text('Recipe not found', style: ansiSerif(size: 20)),
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
    final title = recipe.title.isEmpty ? 'Untitled recipe' : recipe.title;
    // The back-links: the tab exists only while something points here (D9),
    // and the same rows carry the count D5's delete refusal speaks. A
    // still-loading query reads as "nothing points here yet" — two tabs, the
    // page it has always had — never as a third empty pane.
    final usesAsync = ref.watch(recipeUsedInProvider(recipe.id));
    final uses = usesAsync.asData?.value ?? const <RecipeUse>[];
    // Load-bearing emptiness (D6): "nothing points here" and "we could not
    // find out" lead to different conclusions, so an errored query keeps the
    // tab and says so inside it rather than quietly removing the evidence.
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
    // A reading posture, held for the session (see [ShowLineMacros]) — the
    // menu offers it only from the tab it changes.
    final lineMacros = ref.watch(showLineMacrosProvider);
    // A PLANNED arrival: opened from the Week's dish row or the Cook card,
    // and still planned by the week that link names. The guard is the second
    // half — a link kept in a back stack after the meal was removed must not
    // offer a week the person has left — so the page asks the week rather
    // than trusting the parameter. From the Library there is no key, nothing
    // is watched, and the page is exactly what it was.
    final key = weekKey;
    final placement = key == null
        ? const (days: <int>[], edited: false)
        : ref.watch(weekRecipePlacementProvider(recipe.id, key));
    final plannedWeek = placement.days.isEmpty ? null : key;
    // What that week says about THIS recipe: its overrides — the same stream
    // the placement above already reads, asked a second question rather than
    // opened a second time — and its own re-summation, absent while the week
    // varies nothing, in which case the Library's figure is exactly right.
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

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        prefixes: [
          FHeaderAction.back(
            // A cold deep link lands here with no shell page beneath
            // (navigation.md §6), so there is nothing to pop: fall back to
            // the Library. Every other arrival — a push, or the editor's
            // Save replacing itself on a new recipe — has an opener under it.
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
                  // The per-line macro toggle lives here rather than in a
                  // control of its own: the page already has one door for its
                  // less-used verbs, and a second surface beside the panel
                  // would sit below the fold it changes.
                  if (index == 0)
                    FItem(
                      prefix: const Icon(FLucideIcons.sigma),
                      title: Text(
                        lineMacros ? 'Hide line macros' : 'Show line macros',
                      ),
                      onPress: () {
                        unawaited(controller.hide());
                        ref.read(showLineMacrosProvider.notifier).toggle();
                      },
                    ),
                  // Named "Edit recipe" only where the week door stands
                  // beside it: the rename exists so the two doors read as
                  // two, and from the Library there is only one.
                  FItem(
                    prefix: const Icon(FLucideIcons.pencil),
                    title: Text(plannedWeek == null ? 'Edit' : 'Edit recipe'),
                    onPress: () {
                      unawaited(controller.hide());
                      context.pushOnce('/recipes/${recipe.id}/edit');
                    },
                  ),
                  // The second door into week mode (the first is the row at
                  // the foot of the meal editor sheet). It is here because
                  // this is where a planned recipe is LOOKED at — the owner
                  // went looking on Cook and on the Week and found nothing.
                  // It names the days it covers, because what it changes is
                  // those days and not the recipe.
                  if (plannedWeek != null)
                    FItem(
                      prefix: const Icon(FLucideIcons.calendarCog),
                      title: Text(
                        editForThisWeekItem(
                          placement.days,
                          kWeekdayShort,
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
          // One band, under the title: which days of the week you came from
          // cook this, and whether the week varies it. It is what makes the
          // ⋯ menu's second item legible before it is opened.
          if (plannedWeek != null) ...[
            const SizedBox(height: 10),
            PlannedThisWeekBand(days: placement.days, edited: placement.edited),
          ],
          const SizedBox(height: 12),
          _Chips(recipe: recipe),
          const SizedBox(height: 20),
          _TabBar(
            labels: tabs,
            index: index,
            onChanged: (i) => tab.value = i,
            // The Method tab's chips carry live numbers, and nothing on that
            // tab says what they are scaled to — the scaler is a tab away.
            // Same servings state, so the two can never disagree.
            trailing: index != 1
                ? null
                : Text(
                    'for ${formatQuantity(servings.value)} servings · '
                    '${formatQuantity(scaleFactorFor(recipe, servings.value))}'
                    '×',
                    style: ansiMono(size: 11, color: AnsiColors.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const SizedBox(height: 4),
          if (index == 0)
            _IngredientsTab(
              recipe: recipe,
              servings: servings.value,
              onServings: (v) => servings.value = v,
              showLineMacros: lineMacros,
              weekStart: plannedWeek == null ? null : mondayOfKey(plannedWeek),
              overrides: overrides,
              weekSummary: weekSummary,
            )
          else if (index == 1)
            _MethodTab(recipe: recipe, servings: servings.value)
          else if (usesFailed)
            AnsiErrorState(
              what: 'what this is used in',
              error: usesAsync.error!,
              stackTrace: usesAsync.stackTrace,
              onRetry: () => ref.invalidate(recipeUsedInProvider(recipe.id)),
            )
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
    //
    // Guarded, because the alternative is the worst outcome this front knows
    // of: a check that threw would leave `uses` unknown, and an unknown that
    // reads as "nothing points here" turns a refusal into a delete.
    //
    // This page is a whole route and does not unmount under its dialogs, but
    // the rule is one rule (`hostContextOf`): what runs after an awaited
    // dialog goes through the container and the host, never `ref`.
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
      // `go`, not a replacement — the one post-action navigation where it is
      // right. This page is pushed ABOVE the whole tab shell, and the shell is
      // the bottom of the root stack; `go('/')` lands on the Library branch
      // exactly there, where back means "leave from home" (D3-b). A
      // `pushReplacement('/')` would instead stack a SECOND shell page over
      // the first.
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
    this.trailing,
  });

  /// Two tabs, or three while something points at this recipe (D9).
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// A fact about the tab that is open, at the far end of its own bar — what
  /// the Method's chip numbers are scaled to. Null on a tab that says it
  /// somewhere better (the Ingredients tab has the scaler itself).
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
        // What one batch MAKES (D2/D9) — a second pill continues the sentence
        // when the yield states two denominations ("makes 250 g" then
        // "· 16 tbsp").
        // Serves and makes are two independent facts; neither derives from
        // the other, so both sit here.
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
    required this.showLineMacros,
    required this.weekStart,
    required this.overrides,
    required this.weekSummary,
  });

  final Recipe recipe;
  final double servings;
  final ValueChanged<double> onServings;

  /// Whether each line prints its own macros under its name (the `⋯` toggle).
  final bool showLineMacros;

  /// The Monday of the week this page was opened from, once that week was
  /// found to actually plan the recipe. Null from the Library — and then every
  /// week-shaped thing below is inert, so the tab is exactly what it was.
  final DateTime? weekStart;

  /// That week's deltas for this recipe, in stored order. Empty from the
  /// Library.
  final List<LineOverride> overrides;

  /// The week's own re-summation of the recipe, or null when the week varies
  /// nothing about it — the Library's figure is then exactly right.
  final RecipeMacroSummary? weekSummary;

  /// Opens the fix a named line's reason implies (seam **D5**) — the marker
  /// is a door, and this is the one place that decides which door.
  ///
  /// A stub, an unknown row, a missing density or a missing piece weight is an
  /// INGREDIENT problem, so it opens the flesh-out form (ADR-0015: one number
  /// on the row fixes every bare count of it, in every recipe); the two
  /// nested reasons open the sub-recipe. A missing amount is a LINE problem —
  /// and the recipe page is read-only, so it routes to the editor rather than
  /// opening a sheet this screen has no writer for.
  void _fix(BuildContext context, MacroLineNote note) {
    final line = _lineById(recipe)[note.lineId];
    switch (note.reason) {
      case MacroLineReason.stubIngredient:
      case MacroLineReason.unknownIngredient:
      case MacroLineReason.needsDensity:
      case MacroLineReason.needsWeight:
        final id = line?.ingredientId;
        // A marker is a door onto a FIELD — the missing macros, density or
        // piece weight it just named — so it lands on the editing posture
        // rather than on a fact sheet that restates what the marker said.
        if (id != null) context.pushOnce(ingredientDetailRoute(id, edit: true));
      case MacroLineReason.subRecipeUnresolved:
      case MacroLineReason.subRecipeIncomplete:
        final id = line?.subRecipeId;
        if (id != null) context.pushOnce('/recipes/$id');
      case MacroLineReason.noAmount:
        context.pushOnce('/recipes/${recipe.id}/edit');
      case MacroLineReason.imprecise:
      case MacroLineReason.optional:
        break; // excluded by rule — there is nothing to fix
    }
  }

  /// The muted second line under a row's identity when the toggle is on: the
  /// row's macros AT THE AMOUNT SHOWN, or the reason there are none.
  ///
  /// Every figure comes from the summation's own per-line record scaled by the
  /// page's factor — the same multiplication the amount beside it went through
  /// — so nothing is converted twice and a line cannot read one way here and
  /// another inside the total. A row the summary left out prints its reason in
  /// the panel's words instead: never a zero, and never a partial, which is
  /// why a folded multi-use row prints figures only when EVERY use joined.
  /// [marked] rows already carry that reason under their amount, so they say
  /// nothing here rather than saying it twice — and an OPTIONAL row says
  /// nothing here either, because the tag on its name has already said it.
  ({Macros? figures, String? note}) _macroLine(
    LineUses uses,
    RecipeMacroSummary summary,
    double factor, {
    required bool marked,
  }) {
    const nothing = (figures: null, note: null);
    if (!showLineMacros) return nothing;
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
    // The week's answer per line, in the grammar week mode itself draws:
    // struck where it leaves one out, the week's absolute values where it
    // states them, its additions at the end. An include keeps the line's own
    // `optional` flag here, unlike the seam's — the tag has to go on saying
    // what kind of line this is, lit rather than gone.
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
        const SizedBox(height: 16),
        _ScaleControl(
          servings: servings,
          factor: factor,
          onChanged: onServings,
        ),
        const SizedBox(height: 20),
        for (final group in recipe.groups) ...[
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
          for (final row in _weekRows(group.items, entries, factor)) line(row),
        ],
        // An override carries no group, so an added line has none to land in:
        // it sits after the last one, exactly where week mode puts it.
        for (final uses in groupLineUses(added))
          line((uses: uses, excluded: false)),
        // Below the list, as the design board's Recipe frame drew it: the
        // strip reads as the sum of the lines above it, and it stays clear of
        // the scaler — a static per-serving figure sitting under a stepper
        // would invite the reading that the stepper drives it (it does not).
        const SizedBox(height: 22),
        RecipeMacroPanel(
          summary: weekSummary ?? recipe.macros,
          onFix: (note) => _fix(context, note),
          includedNames: [
            for (final item in lines)
              if (included.contains(item.id))
                item.subRecipe?.title ?? item.ingredientName,
          ],
          // The week's summation drops an optional line through the seam
          // before it runs, so its notes cannot name one; the Library's
          // summary names them itself and is left to.
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

  /// One display row, with the week's answer on it: the doors a line still
  /// has, the macros it contributes, and — where a week owns the page — the
  /// tag as the switch that ticks it in.
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
                  // recipe's whole set for that week, so two in flight would
                  // race over one another's answer.
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
      // A component's chip pushes its target's page (D7); an ingredient's
      // name is the same door onto its own page, so "what is this, and what
      // does it weigh" is one tap from the line that raised the question. A
      // struck line has neither: this week it is not part of the recipe.
      onOpenSubRecipe: row.excluded
          ? null
          : (id) => context.pushOnce('/recipes/$id'),
      onOpenIngredient: row.excluded
          ? null
          : (id) => context.pushOnce(ingredientDetailRoute(id)),
      macroMarker: note == null ? null : incompleteLineNote(note.reason),
      macroLine: macros.figures,
      macroLineNote: macros.note,
      onFixMacro: note == null ? null : () => _fix(context, note),
    );
  }
}

/// One group's rows, in stored order, as this week cooks them: each line at
/// the week's values and scaled to the servings on screen, folded by identity
/// as everywhere else.
///
/// The week forces one refinement on the fold: a line it leaves out never
/// joins a row that is still cooked, because the row would then print a struck
/// amount beside a live one under a single name.
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

/// The recipe's line items by id — what a macro note's `lineId` resolves to
/// when the marker is tapped. Read off the UNSCALED recipe: scaling mints new
/// [LineItem]s but keeps their ids, and the identity is all this needs.
Map<String, LineItem> _lineById(Recipe recipe) => {
  for (final group in recipe.groups)
    for (final item in group.items) item.id: item,
};

/// The first note that names any of a display row's sibling lines. A row can
/// fold several uses of one ingredient; one marker on the row is enough to
/// say the total is waiting on it.
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AnsiStepperRow(
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

/// One step: its number, then the step.
///
/// The number is a mono digit in a column of its own, not an ink disc. A disc
/// per step stacked a row of filled circles down the left of a page whose
/// whole argument is that the words come first — and the digit's job is only
/// to let a cook find their place again.
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
          SizedBox(
            width: 26,
            child: Padding(
              // Sits the digit on the first line of the prose beside it.
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$number',
                style: ansiMono(
                  size: 13,
                  color: AnsiColors.herb,
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
  }
}
