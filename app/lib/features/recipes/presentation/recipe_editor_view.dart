/// The recipe editor: create (`recipeId == null`) or edit a recipe.
///
/// Fields are uncontrolled (`initial` + `onChange`) and repeating children are
/// keyed by stable domain id, so a rebuild never resets a controller or moves
/// the caret. The ingredients are one flat reorderable list in which a heading
/// row starts each group; a moved line keeps its id, which keeps its method
/// chips pointing at it.
///
/// At [AnsiLayout.expanded] the same form is two columns. While a step has
/// focus, the lines its chips point at are lit; this follows focus, never the
/// pointer, and is never stored.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/reorder_grip.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/line_display.dart';
import '../domain/method_draft.dart';
import '../domain/recipe.dart';
import '../domain/recipe_measure_repository.dart';
import 'component_format.dart';
import 'component_quantity_sheet.dart';
import 'ingredient_line.dart';
import 'line_card.dart';
import 'line_target_picker.dart';
import 'method_editor.dart';
import 'recipe_chip.dart';
import 'recipe_header_form.dart';
import 'recipe_view_models.dart';

/// The query parameter that asks a new recipe's editor to hand the recipe back
/// instead of landing on its page.
const kHandBackQueryParam = 'handback';

/// The pushed route for a sub-recipe that does not exist yet. [title] prefills
/// the field; the editor pops with the saved recipe as a [SubRecipeTarget], or
/// null if backed out.
String newSubRecipeRoute({String title = ''}) {
  final name = title.trim();
  final seed = name.isEmpty ? '' : 'title=${Uri.encodeQueryComponent(name)}&';
  return '/recipes/new?$seed$kHandBackQueryParam=1';
}

class RecipeEditorView extends ConsumerWidget {
  const RecipeEditorView({
    this.recipeId,
    this.initialTitle,
    this.initialBookId,
    this.initialSectionId,
    this.handsBackTarget = false,
    super.key,
  });

  final String? recipeId;

  /// Seeds a new recipe's title (`/recipes/new?title=…`). Ignored when
  /// [recipeId] is set.
  final String? initialTitle;

  /// The shelf the door that opened this knew about — a section's
  /// `＋` carries both; every other door carries neither.
  final String? initialBookId;
  final String? initialSectionId;

  /// Whether Save pops with the recipe as a [SubRecipeTarget] rather than
  /// landing on its page. True only for [newSubRecipeRoute].
  final bool handsBackTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = recipeEditorProvider(
      recipeId,
      initialTitle: initialTitle,
      initialBookId: initialBookId,
      initialSectionId: initialSectionId,
    );
    final async = ref.watch(editor);
    final notifier = ref.read(editor.notifier);

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(
          recipeId == null ? 'New recipe' : 'Edit recipe',
          style: ansiHeaderTitle(),
        ),
        // With nothing beneath (a pasted link), back goes to the recipe when
        // editing and to the Library when creating.
        prefixes: [
          FHeaderAction.back(
            onPress: () => ansiBack(
              context,
              home: recipeId == null ? '/' : '/recipes/$recipeId',
            ),
          ),
        ],
        suffixes: [
          FButton(
            size: FButtonSizeVariant.sm,
            // Disabled until the draft has loaded — saving mid-load would hit
            // `state.requireValue` with nothing there.
            onPress: !async.hasValue
                ? null
                : () async {
                    // Both captured before the warning dialog, so the write
                    // still lands from handles the header cannot take with it.
                    final container = ProviderScope.containerOf(
                      context,
                      listen: false,
                    );
                    final host = hostContextOf(context);
                    if (!await _mayOrphanMeasures(context, notifier)) return;
                    // Through the write door, so a throw inside `save()` is
                    // reported. The authoring rules' refusals are caught and
                    // shown as sentences rather than toasted.
                    String? refused;
                    final saved = await container.write(
                      host,
                      'save the recipe',
                      () async {
                        try {
                          return await notifier.save();
                        } on RecipeMeasureRefused catch (e) {
                          refused = e.message;
                        } on RecipeMeasureInUse catch (e) {
                          refused = recipeMeasureDeleteRefusalText(
                            label: e.label,
                            lines: e.usage.lines,
                            recipes: e.usage.recipes.length,
                            weeks: e.usage.weeks,
                          );
                        }
                        return null;
                      },
                    );
                    if (refused case final said?) {
                      // The draft is untouched: nothing was written, and the
                      // sentence names the one thing to change.
                      await refuseAnsi(
                        // The host outlives the header — see [hostContextOf].
                        // ignore: use_build_context_synchronously
                        host.context,
                        title: 'That Save didn’t land',
                        body: said,
                      );
                      return;
                    }
                    if (saved == null || !context.mounted) return;
                    // Editing pops to the recipe page already beneath (a
                    // watched query shows the save). Creating replaces the
                    // editor with the new page; `go` would flatten the stack. A
                    // picker-pushed editor pops with the target instead,
                    // because its line is still open underneath.
                    if (recipeId != null) {
                      // Through the back helper, not a bare pop: an editor
                      // opened by a pasted link has nothing under it.
                      ansiBack(context, home: '/recipes/$recipeId');
                    } else if (handsBackTarget) {
                      ansiBack(
                        context,
                        home: '/recipes/${saved.id}',
                        result: saved.asSubRecipeTarget,
                      );
                    } else {
                      context.pushReplacement('/recipes/${saved.id}');
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      child: async.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, st) => AnsiErrorState(
          what: 'the editor',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(recipeEditorProvider(recipeId)),
        ),
        data: (recipe) => _EditorForm(recipe: recipe, notifier: notifier),
      ),
    );
  }
}

/// Asks before a Save that takes away the `makes` a live word stands on,
/// returning whether to go on (ADR-0018 rule 4).
///
/// Warns, never refuses, and deletes nothing: lines saying the word read as
/// unresolved until MAKES states that family again. Words already orphaned when
/// the editor opened are not re-reported.
Future<bool> _mayOrphanMeasures(
  BuildContext context,
  RecipeEditor notifier,
) async {
  final orphaned = notifier.measuresOrphanedBySave();
  if (orphaned.isEmpty) return true;
  final those = plural(
    orphaned.length,
    'that measure',
    plural: 'those measures',
  );
  return askAnsi(
    context,
    title: 'Leave $those on nothing?',
    body: recipeMeasuresOrphanedWarning(orphaned),
    confirm: 'Save anyway',
    cancel: 'Keep editing',
  );
}

/// The ingredients column's fixed width at [AnsiLayout.expanded]; the method
/// column absorbs any change in window width.
const double kEditorLinesColumn = 420;

/// The seam between the two columns — the recipe page's own.
const double kEditorColumnGap = 22;

class _EditorForm extends HookWidget {
  const _EditorForm({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    // Bumped when a drag starts, closing every open line card so rows cross the
    // list at one height.
    final collapseEpoch = useState(0);
    // Which step has the caret. View state, never stored, and read only at
    // expanded — on a phone the lines it would light are a scroll away.
    final focusedStep = useState<String?>(null);
    final onStepFocus = useCallback((String stepId, {required bool focused}) {
      // A step losing focus clears the lighting only if it is the step that
      // set it: the loss and the next gain arrive in either order.
      if (focused) {
        focusedStep.value = stepId;
      } else if (focusedStep.value == stepId) {
        focusedStep.value = null;
      }
    }, const []);
    final lit = wide
        ? _litLines(notifier, focusedStep.value)
        : const <String>{};

    // One flat list: a heading row starts each group and the line rows after it
    // belong to it.
    final rows = <Widget>[];
    var lineCount = 0;
    for (final group in recipe.groups) {
      rows.add(
        _GroupHeading(
          key: ValueKey('group-${group.id}'),
          group: group,
          notifier: notifier,
          removable: recipe.groups.length > 1,
        ),
      );
      for (final item in group.items) {
        lineCount++;
        rows.add(
          _LineItemEditor(
            key: ValueKey('line-${item.id}'),
            item: item,
            recipeId: recipe.id,
            notifier: notifier,
            dragIndex: rows.length,
            collapseEpoch: collapseEpoch.value,
            lit: lit.contains(item.id),
          ),
        );
      }
    }

    final lines = SliverReorderableList(
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
      onReorderItem: notifier.moveLine,
      // An open card closes as soon as a drag begins.
      onReorderStart: (_) => collapseEpoch.value++,
      proxyDecorator: liftedRow,
    );
    final doors = _ListDoors(recipe: recipe, notifier: notifier, stacked: wide);
    final method = MethodEditor(
      recipe: recipe,
      notifier: notifier,
      onStepFocus: wide ? onStepFocus : null,
      ringsCaretChip: wide,
    );

    return CustomScrollView(
      // A field left focused off-screen is scrolled back to on every keyboard
      // metrics change, so a drag dismisses the keyboard.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: wide
          ? [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ansiPageGutter,
                  8,
                  ansiPageGutter,
                  0,
                ),
                sliver: SliverList.list(
                  children: [_WideHeader(host: notifier)],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  ansiPageGutter,
                  20,
                  ansiPageGutter,
                  40,
                ),
                // One scroll, two columns, as slivers so the lines stay one
                // reorderable list and step cards build lazily.
                sliver: SliverCrossAxisGroup(
                  slivers: [
                    SliverConstrainedCrossAxis(
                      maxExtent: kEditorLinesColumn,
                      sliver: SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: EditorSectionHead(
                              label: 'INGREDIENTS',
                              count: _linesAndGroups(
                                lineCount,
                                recipe.groups.length,
                              ),
                            ),
                          ),
                          lines,
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: doors,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(left: kEditorColumnGap),
                      sliver: SliverList.list(children: [method]),
                    ),
                  ],
                ),
              ),
            ]
          : [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                // The same header the import review renders, hosted by the
                // notifier.
                sliver: SliverList.list(
                  children: [RecipeHeaderForm(host: notifier)],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: lines,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                // A list rather than one box, so step cards build lazily.
                sliver: SliverList.list(
                  children: [doors, const SizedBox(height: 28), method],
                ),
              ),
            ],
    );
  }
}

/// What the ingredients column's head says it holds — the frame's own words.
String _linesAndGroups(int lines, int groups) {
  final counted = '$lines ${plural(lines, 'line')}';
  return groups > 1 ? '$counted · $groups groups' : counted;
}

/// The lines the focused step's chips point at, read off the draft on every
/// build. A step id the draft no longer has lights nothing.
Set<String> _litLines(RecipeEditor notifier, String? stepId) {
  if (stepId == null) return const {};
  for (final step in notifier.methodDraft()) {
    if (step.id != stepId) continue;
    return {
      for (final span in step.spans)
        if (span is RefSpan) ...span.refs,
    };
  }
  return const {};
}

/// The wide editor's header: the phone's sections in the phone's order on three
/// rows. Title and filing sit on the columns' axis, the four small facts share
/// row two, and MEASURES takes the full width directly under the MAKES cell it
/// depends on.
class _WideHeader extends StatelessWidget {
  const _WideHeader({required this.host});

  final RecipeHeaderHost host;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kEditorLinesColumn,
            child: RecipeHeaderForm(
              host: host,
              sections: const [RecipeHeaderSection.title],
            ),
          ),
          const SizedBox(width: kEditorColumnGap),
          Expanded(
            child: RecipeHeaderForm(
              host: host,
              sections: const [RecipeHeaderSection.fileUnder],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(height: 1, color: AnsiColors.line),
      const SizedBox(height: 15),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, section) in const [
            RecipeHeaderSection.serves,
            RecipeHeaderSection.makes,
            RecipeHeaderSection.times,
            RecipeHeaderSection.shelfLife,
          ].indexed) ...[
            if (i > 0) const SizedBox(width: 18),
            Expanded(
              child: RecipeHeaderForm(
                host: host,
                sections: [section],
                dense: true,
                timeCaptions: false,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      RecipeHeaderForm(
        host: host,
        sections: const [RecipeHeaderSection.measures],
      ),
    ],
  );
}

/// The list's two doors, under the last line. An added line lands in the last
/// group. [stacked] in the wide editor, where the column is too narrow for the
/// pair side by side.
class _ListDoors extends StatelessWidget {
  const _ListDoors({
    required this.recipe,
    required this.notifier,
    this.stacked = false,
  });

  final Recipe recipe;
  final RecipeEditor notifier;

  /// One door over the other, for the wide editor's 420 column.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final addLine = FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: const Icon(FLucideIcons.plus),
      onPress: () => unawaited(
        addLineToGroup(
          context,
          group: recipe.groups.last,
          recipeId: recipe.id,
          notifier: notifier,
        ),
      ),
      child: const Text('Add ingredient'),
    );
    final addGroup = FButton(
      variant: FButtonVariant.outline,
      size: FButtonSizeVariant.sm,
      prefix: const Icon(FLucideIcons.plus),
      onPress: notifier.addGroup,
      child: const Text('Add group'),
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [addLine, const SizedBox(height: 8), addGroup],
      );
    }
    return Row(
      children: [
        Expanded(child: addLine),
        const SizedBox(width: 8),
        Expanded(child: addGroup),
      ],
    );
  }
}

/// One group's heading row: the name as an editable field, and the bin. A row
/// of the same flat list as the lines, which is what lets a line be dropped
/// under it. Headings do not drag.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({
    required this.group,
    required this.notifier,
    required this.removable,
    super.key,
  });

  final IngredientGroup group;
  final RecipeEditor notifier;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: FTextField(
              hint: 'Group name (optional)',
              control: FTextFieldControl.managed(
                initial: TextEditingValue(text: group.name ?? ''),
                onChange: (v) => notifier.setGroupName(group.id, v.text),
              ),
            ),
          ),
          if (removable) ...[
            const SizedBox(width: 8),
            Semantics(
              label: 'Delete group',
              button: true,
              child: FButton.icon(
                variant: FButtonVariant.ghost,
                onPress: () => notifier.removeGroup(group.id),
                child: const Icon(FLucideIcons.trash2, size: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The add-line chain: the target picker, then the quantity sheet, then the
/// line lands quantified. Backing out of the quantity sheet still adds the line
/// in its default unit.
Future<void> addLineToGroup(
  BuildContext context, {
  required IngredientGroup group,
  required String recipeId,
  required RecipeEditor notifier,
}) async {
  final name = group.name;
  // The picker's keyboard can unmount the door before a row is tapped, so the
  // second sheet opens from `hostContextOf` and [notifier] is the page's own.
  // Never bail on `context.mounted` here: it would drop the pick.
  final host = hostContextOf(context);
  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipeId,
    title: name == null || name.isEmpty
        ? 'Add an ingredient'
        : 'Add to “$name”',
  );
  if (picked == null) return;
  switch (picked) {
    case PickedIngredient(:final ingredient):
      final result = await showQuantityUnitSheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        ingredient: ingredient,
      );
      notifier.addLineItem(
        group.id,
        ingredient,
        quantity: result is QuantitySaved ? result.quantity : null,
        choice: result is QuantitySaved ? result.choice : null,
      );
    case PickedSubRecipe(:final target):
      final result = await showComponentQuantitySheet(
        // The host outlives the row — see [hostContextOf].
        // ignore: use_build_context_synchronously
        host.context,
        target: target,
        // A picked recipe is a stored one, so its words can be coined from
        // the dock — the ＋ writes them onto IT, not onto this recipe.
        mayCoinWords: true,
        onSetYield: () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      notifier.addComponentLineItem(
        group.id,
        target,
        quantity: result?.quantity,
        unit: result?.unit,
        recipeMeasureId: result?.recipeMeasureId,
        // The word itself, because one coined behind the ＋ a tap ago is not
        // in the target the picker handed over.
        recipeMeasure: result?.measure,
        optional: result?.optional ?? false,
      );
  }
}

class _LineItemEditor extends ConsumerWidget {
  const _LineItemEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.dragIndex,
    required this.collapseEpoch,
    this.lit = false,
    super.key,
  });

  final LineItem item;

  /// The recipe being edited — what the identity picker excludes from its
  /// "Your recipes" section (a recipe cannot become its own component).
  final String recipeId;
  final RecipeEditor notifier;

  /// This row's position in the flat list — what the grip drags by.
  final int dragIndex;

  /// Bumped by the list when a drag starts: this card closes with the rest.
  final int collapseEpoch;

  /// Whether the step being written points at this line. See [LineCard.lit].
  final bool lit;

  /// The amount cell's label: what the recipe page prints. An unresolved
  /// measure id falls back to the count with a note, "pending sync" for a row
  /// not yet synced and a different word for one the household deleted.
  String get _label {
    final stored = item.unit;
    if (item.measure == null && item.measureId != null && stored != null) {
      final qty = formatQuantityIn(item.quantity, stored);
      final why = item.measureDeleted
          ? 'measure deleted'
          : 'measure pending sync';
      final unit = '${stored.label} · $why';
      return qty.isEmpty ? unit : '$qty $unit';
    }
    return amountOfLineItem(item);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A component line has no ingredient: its amount is edited against the
    // target's yields.
    if (item.isComponent) {
      return _ComponentLineEditor(
        item: item,
        recipeId: recipeId,
        notifier: notifier,
        dragIndex: dragIndex,
        collapseEpoch: collapseEpoch,
        lit: lit,
      );
    }

    final ingredient = ref
        .watch(
          lineItemIngredientProvider(
            ingredientId: item.ingredientId ?? '',
            name: item.ingredientName,
          ),
        )
        .asData
        ?.value;

    Future<void> editQuantity() async {
      // An unresolved vocab row gets a stub stand-in scoped to the stored
      // unit's family, with no macros or density.
      final sheetIngredient =
          ingredient ??
          Ingredient(
            id: item.ingredientId ?? '',
            canonicalName: item.ingredientName,
            // A stand-in for a row this sheet is not really about; a line
            // said in a recipe's own word has no catalog unit to lend it.
            defaultUnit: item.measure != null ? pieces : (item.unit ?? pieces),
            status: IngredientStatus.stub,
          );
      final pending = item.measureId != null && item.measure == null;
      final measure = item.measure;
      final result = await showQuantityUnitSheet(
        context,
        ingredient: sheetIngredient,
        initialQuantity: item.quantity,
        initialChoice: measure != null
            ? MeasureOption(measure)
            : UnitOption(item.unit ?? pieces),
        pendingMeasure: pending,
      );
      if (result is! QuantitySaved) return;
      notifier.setLineItemQuantity(item.id, result.quantity);
      switch (result.choice) {
        case MeasureOption(:final measure):
          notifier.setLineItemMeasure(item.id, measure);
        // This door is the INGREDIENT sheet, which never offers one; a
        // component's own words are picked on the component dock.
        case RecipeMeasureOption(:final measure):
          notAWordForAnIngredient(measure);
        case UnitOption(:final unit):
          // An unresolved measure id survives an unrelated re-save; only an
          // explicit chip pick clears it (degrade-don't-destroy).
          if (!pending || result.unitPicked) {
            notifier.setLineItemUnit(item.id, unit);
          }
      }
    }

    // A retired row's last known name, muted like a dangling component — same
    // news, same voice. The card's `change ›` is the repair the tag asks for.
    final nameStyle = item.ingredientDeleted
        ? ansiSans(size: 15, color: AnsiColors.muted)
        : ansiSans(size: 15, weight: FontWeight.w500);

    return _EditorLine(
      item: item,
      recipeId: recipeId,
      notifier: notifier,
      amount: _label,
      dragIndex: dragIndex,
      collapseEpoch: collapseEpoch,
      lit: lit,
      onEditAmount: editQuantity,
      rowIdentity: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: item.ingredientName, style: nameStyle),
            ...noteSpans(item.note),
            ...optionalSpans(optional: item.optional),
            ...removedIngredientSpans(removed: item.ingredientDeleted),
          ],
        ),
      ),
      headIdentity: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: item.ingredientName, style: nameStyle),
            ...removedIngredientSpans(removed: item.ingredientDeleted),
          ],
        ),
      ),
    );
  }
}

/// A component line in the editor: the recipe chip where the ingredient name
/// sits, and an amount cell that opens the batch-math sheet. A target that has
/// not synced or was deleted keeps its stored text; the amount stays editable
/// in batches.
class _ComponentLineEditor extends StatelessWidget {
  const _ComponentLineEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.dragIndex,
    required this.collapseEpoch,
    this.lit = false,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;
  final int dragIndex;
  final int collapseEpoch;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final target = item.subRecipe;

    Future<void> editQuantity() async {
      // The sheet's keyboard can unmount this row; the yield door pushes
      // from a context that outlives it.
      final host = hostContextOf(context);
      final result = await showComponentQuantitySheet(
        context,
        target:
            target ??
            SubRecipeTarget(
              id: item.subRecipeId ?? '',
              title: item.ingredientName,
            ),
        initialQuantity: item.quantity,
        initialUnit: item.unit,
        // The line's pointer, so the sheet opens on the word. The word itself
        // is read off the target.
        initialMeasureId: item.recipeMeasureId,
        initialOptional: item.optional,
        // No ＋ when the target row has not synced: there are no yields to gate
        // a word on.
        mayCoinWords: target != null,
        onSetYield: target == null
            ? null
            : () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      if (result == null) return;
      notifier
        ..setLineItemQuantity(item.id, result.quantity)
        ..setLineItemOptional(item.id, optional: result.optional);
      // Exactly one of the two, and each setter clears the other (ADR-0018).
      // Both null is a line whose word has gone and no chip was picked; it
      // keeps its pointer.
      if (result.recipeMeasureId case final id?) {
        notifier.setLineItemRecipeMeasure(item.id, id, word: result.measure);
      } else if (result.unit case final picked?) {
        notifier.setLineItemUnit(item.id, picked);
      }
    }

    return _EditorLine(
      item: item,
      recipeId: recipeId,
      notifier: notifier,
      // Read off the target's live measures, not the resolution: a word can be
      // alive yet unresolvable, and that row must still read `3 blob`.
      amount: componentAmountText(
        item.quantity,
        item.unit,
        measureLabel: recipeMeasureOfLine(item)?.label,
      ),
      dragIndex: dragIndex,
      collapseEpoch: collapseEpoch,
      lit: lit,
      onEditAmount: editQuantity,
      // A dangling link reads as the plain text it stored, muted, and says why
      // there is no chip — the recipe page's own degradation.
      rowIdentity: target != null
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                RecipeChip(title: target.title, size: 14),
                if (item.note != null && item.note!.trim().isNotEmpty)
                  Text(
                    item.note!.trim(),
                    style: ansiSans(
                      size: 14,
                      color: AnsiColors.muted,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                if (item.optional) const OptionalTag(),
              ],
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.ingredientName,
                    style: ansiSans(size: 15, color: AnsiColors.muted),
                  ),
                  ...noteSpans('linked recipe missing'),
                  ...optionalSpans(optional: item.optional),
                ],
              ),
            ),
      headIdentity: target != null
          ? RecipeChip(title: target.title, size: 14)
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: item.ingredientName,
                    style: ansiSans(size: 15, color: AnsiColors.muted),
                  ),
                  ...noteSpans('linked recipe missing'),
                ],
              ),
            ),
    );
  }
}

/// The editor's ingredient line as an expanding [LineCard]. At rest it is the
/// app's one row layout plus a grip; tapping opens the card holding the
/// identity (`change ›`), the optional flag, the amount and the note.
class _EditorLine extends StatelessWidget {
  const _EditorLine({
    required this.item,
    required this.recipeId,
    required this.notifier,
    required this.amount,
    required this.rowIdentity,
    required this.headIdentity,
    required this.dragIndex,
    required this.collapseEpoch,
    required this.onEditAmount,
    this.lit = false,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;
  final String amount;

  /// The identity as the row states it: the name with its note, its
  /// `optional` tag and whatever the line is wearing.
  final Widget rowIdentity;

  /// The identity as the card's head says it — the name alone, because the
  /// note and the flag are controls of their own inside the card.
  final Widget headIdentity;

  final int dragIndex;
  final int collapseEpoch;
  final VoidCallback onEditAmount;

  /// Whether the step being written points at this line. See [LineCard.lit].
  final bool lit;

  @override
  Widget build(BuildContext context) => LineCard(
    dragIndex: dragIndex,
    collapseEpoch: collapseEpoch,
    lit: lit,
    // A saved recipe has no line that needs the user, and it has no wall of
    // boxes either: the border is what "open" looks like.
    borderAtRest: false,
    collapsed: (onExpand) => _CollapsedLine(
      amount: amount,
      identity: rowIdentity,
      onExpand: onExpand,
    ),
    expanded: (onCollapse) => _OpenLine(
      item: item,
      identity: headIdentity,
      amount: amount,
      usedIn: notifier.stepsUsing(item.id),
      onEditAmount: onEditAmount,
      onChangeIdentity: () => changeLineIdentity(
        context,
        recipeId: recipeId,
        item: item,
        notifier: notifier,
      ),
      onRemove: () => removeLineWithChips(context, item, notifier),
      onCollapse: onCollapse,
      onOptional: (on) => notifier.setLineItemOptional(item.id, optional: on),
      onNote: (text) => notifier.setLineItemNote(item.id, text),
    ),
  );
}

/// The line at rest. One gesture: anywhere on it opens the card.
class _CollapsedLine extends StatelessWidget {
  const _CollapsedLine({
    required this.amount,
    required this.identity,
    required this.onExpand,
  });

  final String amount;
  final Widget identity;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Edit the line',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onExpand,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kLineAmountWidth,
            child: Text(
              amount.isEmpty ? '—' : amount,
              style: ansiMono(size: 14, color: AnsiColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: identity),
          const SizedBox(width: 8),
          const Icon(FLucideIcons.pencil, size: 14, color: AnsiColors.herb),
        ],
      ),
    ),
  );
}

/// The open line. `change ›` and the bin, which can break a method chip, stand
/// under the count of steps that quote the line.
class _OpenLine extends StatelessWidget {
  const _OpenLine({
    required this.item,
    required this.identity,
    required this.amount,
    required this.usedIn,
    required this.onEditAmount,
    required this.onChangeIdentity,
    required this.onRemove,
    required this.onCollapse,
    required this.onOptional,
    required this.onNote,
  });

  final LineItem item;
  final Widget identity;
  final String amount;
  final int usedIn;
  final VoidCallback onEditAmount;
  final VoidCallback onChangeIdentity;
  final VoidCallback onRemove;
  final VoidCallback onCollapse;
  final ValueChanged<bool> onOptional;
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LineCardHead(
        identity: _HeadIdentity(onChange: onChangeIdentity, child: identity),
        onRemove: onRemove,
        onCollapse: onCollapse,
      ),
      _UsedInSteps(count: usedIn),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OptionalFlagToggle(value: item.optional, onChanged: onOptional),
      ),
      const SizedBox(height: 12),
      LineCardRow(
        label: 'AMOUNT',
        child: Align(
          alignment: Alignment.centerLeft,
          child: LineCardAmountChip(label: amount, onTap: onEditAmount),
        ),
      ),
      const SizedBox(height: 12),
      LineCardNotesField(initial: item.note, onChanged: onNote),
    ],
  );
}

/// The card's head: the identity, which opens the line target picker behind
/// `change ›`. The swap keeps the line's id so method chips keep pointing at
/// it.
class _HeadIdentity extends StatelessWidget {
  const _HeadIdentity({required this.child, required this.onChange});

  final Widget child;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Change what this line is',
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onChange,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          child,
          Text('change ›', style: ansiMono(size: 10, color: AnsiColors.herb)),
        ],
      ),
    ),
  );
}

/// How many steps quote this line. Shown only on the open card, so collapsed
/// rows keep one height.
class _UsedInSteps extends StatelessWidget {
  const _UsedInSteps({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'used in $count ${plural(count, 'step')}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// Tap the identity → the shipped picker → the line keeps its id and takes a
/// new one. Chips survive by construction and are then relabelled.
Future<void> changeLineIdentity(
  BuildContext context, {
  required String recipeId,
  required LineItem item,
  required RecipeEditor notifier,
}) async {
  final picked = await showLineTargetPicker(
    context,
    editingRecipeId: recipeId,
    title: 'Change ${item.ingredientName} to',
  );
  if (picked == null) return;
  switch (picked) {
    case PickedIngredient(:final ingredient):
      notifier.setLineItemIngredient(item.id, ingredient);
    case PickedSubRecipe(:final target):
      notifier.setLineItemSubRecipe(item.id, target);
  }
}

/// Removing a referenced line asks first. Confirming converts
/// its chips to plain words — the sentences survive, only the links die.
Future<void> removeLineWithChips(
  BuildContext context,
  LineItem item,
  RecipeEditor notifier,
) async {
  final steps = notifier.stepsUsing(item.id);
  if (steps == 0) {
    notifier.removeLineItem(item.id);
    return;
  }
  final confirmed = await askAnsi(
    context,
    title:
        '$steps ${plural(steps, 'step mentions', plural: 'steps mention')} '
        '${item.ingredientName}.',
    body:
        'Remove those chips too? Their words stay in the sentences — only '
        'the links go.',
    confirm: 'Remove',
  );
  if (confirmed) notifier.removeLineItem(item.id);
}
