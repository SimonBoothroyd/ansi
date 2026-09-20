/// The recipe editor **in week mode**: the same list, the same two doors per
/// line, saving a diff against the recipe instead of the recipe.
///
/// It is reached by the recipe editor's own route with a `?week=` param, so
/// there is no second route and no second screen in the map — the mode is a
/// fact about what Save writes.
///
/// **What is not drawn, and why it is not drawn rather than locked.** The whole
/// header form (title, serves, times, shelf life, filing) and the whole method
/// are absent. A control drawn and refused has to be explained on every tap; a
/// control absent is a mode you understand in one look. The method is gone
/// rather than muted for a second reason: a step's chip points at a line id, an
/// added line has not got one, and an excluded line would orphan its chips.
///
/// Two carve-outs. **Serves survives as a sentence** — every amount on the
/// list is *per serves 4*, so dropping the number makes the list unreadable —
/// in one inert strip with the step count and the title. And there is **no
/// grip**: a reorder is not storable this week, and a drag that silently
/// reverts on reopen is worse than no drag.
///
/// **Wide is one column, deliberately.** With no header form and no method
/// there is no second column to make, so from [AnsiLayout.expanded] up this is
/// the same list at the same 640 measure, centred in the pane the sidebar
/// leaves. What the measure does buy is a column for the week's own statement
/// at the row's right end: every row is then one line and the changes read down
/// an edge, which is what makes the foot's *drops 5 changes* a count you can
/// check rather than one you take on trust.
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

  /// The week's first day as `YYYY-MM-DD` — the `?week=` param the door
  /// carries.
  final String weekKey;

  /// Puts the form down: onto the page it edits, or onto that page's own
  /// route when a pasted link left nothing under this one.
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
        // This form is a page over the recipe as that week plans it, so
        // that is where it belongs when nothing is under it.
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
                    // The same helper the chevron uses: a Save with nothing to
                    // pop must not write the diff and then strand the form.
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

/// The band that says whose lines these are, and that the recipe is not the
/// thing being changed. It names the DAYS this week plans the recipe on,
/// because the variant is per (week, recipe) and the door that opened it was
/// per meal.
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

/// The recipe's own facts, stated once and not editable here — serves above
/// all, because every amount on the list is per that number.
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

/// A group heading, inert: no rename, no bin, no add-group. The grouping is
/// the recipe's, and this screen does not edit the recipe.
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

/// One line in week mode: the shipped three-part row without its grip, plus
/// the tag that says what this week did to it and the reset that undoes it.
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
    // An optional line is a line this week has not asked for, which is what an
    // excluded line is too — so it reads the same: struck and muted. The
    // difference is only how it comes back, and each says so in its own slot
    // below the name.
    final struck = entry.excluded || item.optional;
    final muted = struck ? AnsiColors.muted : AnsiColors.ink;

    Future<void> editAmount() async {
      // **A component line gets the component sheet, measured or not.** The
      // ingredient sheet's offer cannot express a recipe at all — no `batch`,
      // no yield families, and no way to say one of the target's own words. It
      // opens such a line preselected on `piece`, and for a measured line it
      // hands back a unit written where `blob` was, which is the only place
      // that line's amount lived (ADR-0018). The component sheet asks the
      // question the line is actually about, and hands back exactly one
      // denomination.
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
          // The week says a line in the target's own word exactly as the
          // recipe does, so the ＋ is the same door here — and it is shut for
          // a line whose recipe row has not synced, which has no yields to
          // gate a word on.
          mayCoinWords: item.subRecipe != null,
        );
        if (measured == null) return;
        notifier
          ..setQuantity(item.id, measured.quantity)
          ..setOptional(item.id, optional: measured.optional);
        // Both null is a line whose word has gone and whose reader picked no
        // chip: it keeps the pointer it had rather than a unit nobody stated.
        if (measured.recipeMeasureId case final word?) {
          notifier.setRecipeMeasure(item.id, word);
        } else if (measured.unit case final picked?) {
          notifier.setUnit(item.id, picked);
        }
        return;
      }
      final ingredient = Ingredient(
        id: item.ingredientId ?? '',
        canonicalName: item.ingredientName,
        // A stand-in for a row this sheet is not really about; a line said
        // in a recipe's own word has no catalog unit to lend it.
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
        // No sub-recipe swaps in v1 (0043 D7): the component graph knows no
        // week, so a component swapped for one week would make it
        // week-dependent.
        suppressRecipes: true,
      );
      if (picked is PickedIngredient) {
        notifier.setIngredient(item.id, picked.ingredient);
      }
    }

    // The measure's own extra: the week's statement at the row's right end
    // instead of under the name, so a row is one line and the changes read
    // down an edge. Below expanded it stays under the name, where a phone has
    // no room for a second column.
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;

    final amount = Semantics(
      label: 'Amount',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: struck ? null : () => unawaited(editAmount()),
        child: SizedBox(
          // A measure that weighs a piece is a word (ADR-0016), so at the
          // measure the column is wide enough to say one — the only thing on
          // this list that can still take a row to two lines.
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

    // One slot per row, never two badges at once: a line this week has changed
    // says what it did and offers the undo; an untouched optional line says it
    // is optional and offers the way in. Ticking it in IS a change, so the
    // first takes over from the second.
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

/// The amount column at the measure — wide enough for a whole measure in its
/// own words (ADR-0016), where the phone's [kLineAmountWidth] wraps one.
const double kWeekAmountWidth = 118;

/// The column the week's own statement stands in at the measure: the tag and
/// the control that undoes it, set at the row's right end.
const double kWeekStatementWidth = 256;

/// The tag and its reset — one badge vocabulary on a recipe line, not two, so
/// it wears the `optional` tag's voice. The reset is the dish row's `−` idiom:
/// muted, not red, and no confirm, because Save is what stores it and back is
/// the undo.
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

  /// In its own column at the measure, so it sets from the row's right edge
  /// and the changes read down one line.
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

/// The `optional` tag, on the one screen where it is also the switch.
///
/// Week mode is where a household says what it is actually eating, and an
/// optional line is the question that asks most often: *are we doing the
/// parmesan this week?* Everywhere else the tag states a fact and the amount
/// sheet's **Optional** switch changes it; here the fact and the question are
/// the same thing, so the tag answers it in one tap — no second screen, no new
/// state, and Save still stores it. Ticking it in writes the `include` row the
/// diff already had words for, and the row swaps this slot for the week tag.
///
/// It wears `_WeekTag`'s own shape — a badge and the muted action beside it —
/// because that is the one badge vocabulary a recipe line has.
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
      // A badge is a small thing to hit; the row it sits under is not, so the
      // target is padded out to a comfortable one rather than drawn bigger.
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

/// The add door, in week mode's words. The line lands at the foot of the list
/// — an override carries no group, and no derivation reads one.
Future<void> _addLine(
  BuildContext context,
  String recipeId,
  WeekVariantDraft notifier,
) async {
  // The picker's search brings the keyboard, which shrinks the list under it:
  // the door can be unmounted by the time a row is tapped. The second sheet
  // opens from a context that outlives it, and the notifier is the screen's
  // own — never a `context.mounted` bail here, which would drop the pick.
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
