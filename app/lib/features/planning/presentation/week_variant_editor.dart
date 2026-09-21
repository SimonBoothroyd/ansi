/// The recipe editor in week mode: the same line list, saving a diff against
/// the recipe instead of the recipe. Reached by the editor's own route with a
/// `?week=` param.
///
/// The header form and the method are absent, not locked: a step's chip points
/// at a line id, which an added line lacks and an excluded line would orphan.
/// Serves survives as an inert sentence because every amount is per that
/// number. There is no reorder grip, since a week cannot store an order. Wide
/// is one column, with the week's statement at each row's right end.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/write.dart';
import '../../account/data/household_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../../recipes/domain/line_display.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/component_quantity_sheet.dart';
import '../../recipes/presentation/ingredient_line.dart';
import '../../recipes/presentation/line_target_picker.dart';
import '../domain/planning.dart' show PlanEntry;
import 'week_variant_format.dart';
import 'week_variant_view_models.dart';
import 'week_view_models.dart';

class WeekVariantEditorView extends ConsumerWidget {
  const WeekVariantEditorView({
    required this.recipeId,
    required this.weekKey,
    super.key,
  });

  final String recipeId;

  /// The week's first day as `YYYY-MM-DD` — the `?week=` param.
  final String weekKey;

  /// Back to the page this edits, or to its route when nothing is under this
  /// one.
  void _back(BuildContext context) =>
      ansiBack(context, home: '/recipes/$recipeId?week=$weekKey');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = weekVariantDraftProvider(recipeId, weekKey);
    final async = ref.watch(draft);
    final notifier = ref.read(draft.notifier);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text('Edit for this week', style: ansiHeaderTitle()),
        // Falls back to the recipe page as that week plans it.
        prefixes: [FHeaderAction.back(onPress: () => _back(context))],
        suffixes: [
          FButton(
            size: FButtonSizeVariant.sm,
            onPress: !async.hasValue
                ? null
                : () async {
                    final saved = await ref.write(
                      context,
                      "save this week's changes",
                      notifier.save,
                    );
                    if (saved == null || !context.mounted) return;
                    // The same helper as the chevron, so a Save with nothing to
                    // pop does not strand the form.
                    _back(context);
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      child: async.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: "this week's changes",
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(draft),
        ),
        data: (variant) =>
            _WeekList(variant: variant, weekKey: weekKey, notifier: notifier),
      ),
    );
  }
}

class _WeekList extends StatelessWidget {
  const _WeekList({
    required this.variant,
    required this.weekKey,
    required this.notifier,
  });

  final WeekVariant variant;
  final String weekKey;
  final WeekVariantDraft notifier;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final e in variant.lines) e.line.id: e};
    final overrides = variant.overrides;
    final changeById = {
      for (final o in overrides)
        (o.recipeLineItemId ?? o.id): weekChangeOf(
          o,
          variant.baseOf(o.recipeLineItemId ?? ''),
        ),
    };
    final recipe = variant.recipe;

    Widget row(WeekDraftLine entry) => _WeekLineRow(
      key: ValueKey('week-line-${entry.line.id}'),
      entry: entry,
      base: variant.baseOf(entry.line.id),
      change: changeById[entry.line.id],
      recipeId: recipe.id,
      notifier: notifier,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: [
        WeekVariantBand(title: recipe.title, weekKey: weekKey),
        _FromTheRecipe(recipe: recipe),
        for (final group in recipe.groups) ...[
          _GroupHeading(group: group),
          for (final item in group.items)
            if (byId[item.id] != null) row(byId[item.id]!),
        ],
        for (final entry in variant.lines)
          if (entry.added) row(entry),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: FButton(
            variant: FButtonVariant.outline,
            size: FButtonSizeVariant.sm,
            prefix: const Icon(FLucideIcons.plus),
            onPress: () => unawaited(_addLine(context, recipe.id, notifier)),
            child: const Text('Add ingredient'),
          ),
        ),
        if (overrides.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: FButton(
              variant: FButtonVariant.destructive,
              size: FButtonSizeVariant.sm,
              onPress: notifier.resetAll,
              child: Text(backToTheRecipeLabel(overrides.length)),
            ),
          ),
      ],
    );
  }
}

/// The band saying these are the week's lines, not the recipe's. It names the
/// days the week plans the recipe on, because the variant is per (week,
/// recipe).
class WeekVariantBand extends ConsumerWidget {
  const WeekVariantBand({
    required this.title,
    required this.weekKey,
    super.key,
  });

  final String title;
  final String weekKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(viewedWeekProvider).asData?.value;
    final days = <int>{
      for (final e in plan?.entries ?? const <PlanEntry>[])
        if (e.recipeTitle == title) e.dayOfWeek,
    }.toList()..sort();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AnsiColors.herbSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THIS WEEK ONLY',
            style: ansiMono(
              size: 9.5,
              color: AnsiColors.herbDeep,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(title, style: ansiSans(size: 16, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            weekScopeLine(
              weekKey,
              days,
              ref.watch(weekShapeProvider).shortLabels,
            ),
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
          Text(
            'The recipe is not changed.',
            style: ansiMono(size: 10.5, color: AnsiColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The recipe's own facts, inert — serves above all, because every amount is
/// per that number.
class _FromTheRecipe extends StatelessWidget {
  const _FromTheRecipe({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: Text(
      fromTheRecipeLine(recipe),
      style: ansiMono(size: 10.5, color: AnsiColors.muted),
    ),
  );
}

/// An inert group heading; the grouping is the recipe's.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({required this.group});

  final IngredientGroup group;

  @override
  Widget build(BuildContext context) {
    final name = group.name?.trim() ?? '';
    if (name.isEmpty) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
      child: Text(name, style: ansiSans(size: 13, color: AnsiColors.muted)),
    );
  }
}

/// One line in week mode: the editor row without its grip, plus the week's tag
/// and its reset.
class _WeekLineRow extends ConsumerWidget {
  const _WeekLineRow({
    required this.entry,
    required this.base,
    required this.change,
    required this.recipeId,
    required this.notifier,
    super.key,
  });

  final WeekDraftLine entry;

  /// The recipe's own line, for the tag to quote back. Null on an addition.
  final LineItem? base;
  final WeekChange? change;
  final String recipeId;
  final WeekVariantDraft notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = entry.line;
    // An untaken optional line reads like an excluded one: struck and muted.
    final struck = entry.excluded || item.optional;
    final muted = struck ? AnsiColors.muted : AnsiColors.ink;

    Future<void> editAmount() async {
      // A component line always gets the component sheet: the ingredient sheet
      // cannot offer `batch`, yield families or the target's own words. See
      // ADR-0018.
      if (item.subRecipeId != null || item.recipeMeasureId != null) {
        final target =
            item.subRecipe ??
            SubRecipeTarget(
              id: item.subRecipeId ?? '',
              title: item.ingredientName,
            );
        final measured = await showComponentQuantitySheet(
          context,
          target: target,
          initialQuantity: item.quantity,
          initialUnit: item.unit,
          initialMeasureId: item.recipeMeasureId,
          initialOptional: item.optional,
          // Coining a word needs the target's yields, so it is closed for a
          // recipe row that has not synced.
          mayCoinWords: item.subRecipe != null,
        );
        if (measured == null) return;
        notifier
          ..setQuantity(item.id, measured.quantity)
          ..setOptional(item.id, optional: measured.optional);
        // Both null: the line's word has gone and no chip was picked, so it
        // keeps the pointer it had.
        if (measured.recipeMeasureId case final id?) {
          notifier.setRecipeMeasure(item.id, id, word: measured.measure);
        } else if (measured.unit case final picked?) {
          notifier.setUnit(item.id, picked);
        }
        return;
      }
      final ingredient = Ingredient(
        id: item.ingredientId ?? '',
        canonicalName: item.ingredientName,
        // A stand-in row: a line said in a recipe's own word has no catalog
        // unit.
        defaultUnit: item.measure != null ? pieces : (item.unit ?? pieces),
        status: IngredientStatus.stub,
      );
      final measure = item.measure;
      final result = await showQuantityUnitSheet(
        context,
        ingredient: ingredient,
        initialQuantity: item.quantity,
        initialChoice: measure != null
            ? MeasureOption(measure)
            : UnitOption(item.unit ?? pieces),
        initialOptional: item.optional,
      );
      if (result is! QuantitySaved) return;
      notifier
        ..setQuantity(item.id, result.quantity)
        ..setOptional(item.id, optional: result.optional);
      switch (result.choice) {
        case MeasureOption(:final measure):
          notifier.setMeasure(item.id, measure);
        case RecipeMeasureOption(:final measure):
          notAWordForAnIngredient(measure);
        case UnitOption(:final unit):
          notifier.setUnit(item.id, unit);
      }
    }

    Future<void> editIdentity() async {
      final picked = await showLineTargetPicker(
        context,
        editingRecipeId: recipeId,
        title: 'Change ${item.ingredientName} to',
        subtitle: 'for this week only',
        // No sub-recipe swaps: the component graph knows no week.
        suppressRecipes: true,
      );
      if (picked is PickedIngredient) {
        notifier.setIngredient(item.id, picked.ingredient);
      }
    }

    // Wide puts the week's statement at the row's right end; a phone keeps it
    // under the name.
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;

    final amount = Semantics(
      label: 'Amount',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: struck ? null : () => unawaited(editAmount()),
        child: SizedBox(
          // A measure that weighs a piece is a word (ADR-0016), so the wide
          // column is wide enough to say one.
          width: wide ? kWeekAmountWidth : kLineAmountWidth,
          child: Text(
            amountOfLine(item).isEmpty ? '—' : amountOfLine(item),
            style: ansiMono(
              size: 14,
              color: AnsiColors.muted,
            ).copyWith(decoration: struck ? TextDecoration.lineThrough : null),
          ),
        ),
      ),
    );

    final identity = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: struck ? null : () => unawaited(editIdentity()),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: item.ingredientName,
              style: ansiSans(size: 15, weight: FontWeight.w500, color: muted)
                  .copyWith(
                    decoration: struck ? TextDecoration.lineThrough : null,
                  ),
            ),
            ...noteSpans(item.note),
          ],
        ),
      ),
    );

    // One slot per row: a changed line shows its change and the undo; an
    // untouched optional line shows the way in.
    final statement = change != null
        ? _WeekTag(
            change: change!,
            base: base,
            alignEnd: wide,
            onReset: () => change == WeekChange.added
                ? notifier.removeOrExclude(item.id)
                : notifier.reset(item.id),
          )
        : item.optional
        ? _OptionalSwitch(
            alignEnd: wide,
            onTap: () =>
                notifier.setOptional(item.id, optional: !item.optional),
          )
        : null;

    final bin = struck
        ? null
        : FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => notifier.removeOrExclude(item.id),
            child: const Icon(FLucideIcons.x),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 5, 20, 5),
      child: Row(
        crossAxisAlignment: wide
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: wide
            ? [
                amount,
                const SizedBox(width: 10),
                Expanded(child: identity),
                const SizedBox(width: 10),
                SizedBox(
                  width: kWeekStatementWidth,
                  child: statement ?? const SizedBox.shrink(),
                ),
                const SizedBox(width: 4),
                if (bin != null) bin else const SizedBox(width: 12),
              ]
            : [
                amount,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [identity, ?statement],
                  ),
                ),
                const SizedBox(width: 4),
                ?bin,
              ],
      ),
    );
  }
}

/// The wide amount column, wide enough for a whole measure in words (ADR-0016).
const double kWeekAmountWidth = 118;

/// The wide column for the week's tag and its undo.
const double kWeekStatementWidth = 256;

/// The week tag and its reset, in the `optional` tag's style. The reset is
/// muted with no confirm: Save stores it and back undoes it.
class _WeekTag extends StatelessWidget {
  const _WeekTag({
    required this.change,
    required this.base,
    required this.onReset,
    this.alignEnd = false,
  });

  final WeekChange change;
  final LineItem? base;
  final VoidCallback onReset;

  /// Align to the row's right edge (the wide column).
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: alignEnd ? 0 : 4),
    child: Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FBadge(
          variant: FBadgeVariant.secondary,
          child: Text(
            weekTagText(change, base),
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReset,
          child: Text(
            change == WeekChange.added ? '✕ remove' : '↺ reset',
            style: ansiMono(size: 10, color: AnsiColors.muted),
          ),
        ),
      ],
    ),
  );
}

/// The `optional` tag as a one-tap switch. Ticking it in writes the diff's
/// `include` row, and the slot becomes the week tag.
class _OptionalSwitch extends StatelessWidget {
  const _OptionalSwitch({required this.onTap, this.alignEnd = false});

  final VoidCallback onTap;

  /// See [_WeekTag.alignEnd].
  final bool alignEnd;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'optional · tap to include this week',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Padded out to a comfortable tap target.
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        padding: EdgeInsets.only(top: alignEnd ? 0 : 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const OptionalTag(),
            Text(
              '＋ include this week',
              style: ansiMono(size: 10, color: AnsiColors.muted),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The add door. The line lands at the foot of the list: an override carries no
/// group.
Future<void> _addLine(
  BuildContext context,
  String recipeId,
  WeekVariantDraft notifier,
) async {
  // The picker's keyboard can unmount this door before a row is tapped, so the
  // second sheet opens from a context that outlives it. Never bail on
  // `context.mounted` here: that drops the pick.
  final host = hostContextOf(context);
  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipeId,
    subtitle: 'for this week only',
    suppressRecipes: true,
  );
  if (picked is! PickedIngredient) return;
  final result = await showQuantityUnitSheet(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    ingredient: picked.ingredient,
  );
  final saved = result is QuantitySaved ? result : null;
  notifier.addLine(
    picked.ingredient,
    quantity: saved?.quantity,
    unit: switch (saved?.choice) {
      UnitOption(:final unit) => unit,
      _ => null,
    },
    measure: switch (saved?.choice) {
      MeasureOption(:final measure) => measure,
      _ => null,
    },
  );
}
