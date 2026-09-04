/// The recipe editor — create (`recipeId == null`) or edit an existing recipe.
///
/// Fields are uncontrolled (`initial` + `onChange`) and every repeating child
/// is keyed by its stable domain id, so the notifier rebuilding the tree on
/// each edit never resets a controller or moves the caret.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'component_quantity_sheet.dart';
import 'line_target_picker.dart';
import 'method_editor.dart';
import 'recipe_chip.dart';
import 'recipe_header_form.dart';
import 'recipe_view_models.dart';

class RecipeEditorView extends ConsumerWidget {
  const RecipeEditorView({
    this.recipeId,
    this.initialTitle,
    this.initialBookId,
    this.initialSectionId,
    super.key,
  });

  final String? recipeId;

  /// Seeds a NEW recipe's title (`/recipes/new?title=…`) — the query the
  /// Library's "nothing matches" state was searched for. Ignored when
  /// [recipeId] is set: an existing recipe already has a title.
  final String? initialTitle;

  /// The shelf the door that opened this knew about (0028 E3) — a section's
  /// `＋` carries both; every other door carries neither.
  final String? initialBookId;
  final String? initialSectionId;

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
        prefixes: [FHeaderAction.back(onPress: () => context.pop())],
        suffixes: [
          FButton(
            size: FButtonSizeVariant.sm,
            // Disabled until the draft has loaded — saving mid-load would hit
            // `state.requireValue` with nothing there.
            onPress: !async.hasValue
                ? null
                : () async {
                    // Through the write door: unguarded, a throw inside
                    // `save()` shows only as the editor not navigating, which
                    // reads as a laggy button rather than a lost recipe.
                    final id = await ref.write(
                      context,
                      'save the recipe',
                      notifier.save,
                    );
                    if (id == null || !context.mounted) return;
                    // Editing returns you to where you opened the editor;
                    // creating lands you on the thing you made. An existing
                    // recipe's page is already beneath the editor as a watched
                    // query, so a pop shows the save — replacing would stack a
                    // second copy of that page and cost a second back. A new
                    // recipe has only its opener beneath, so the editor is
                    // replaced (not `go`ne to: that would flatten the stack,
                    // back would leave the app and the iOS edge swipe would
                    // vanish on a page that looks exactly like a pushed one).
                    if (recipeId != null) {
                      context.pop();
                    } else {
                      context.pushReplacement('/recipes/$id');
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

class _EditorForm extends StatelessWidget {
  const _EditorForm({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // The header is the one the import review renders too: the notifier is
        // its host, so a section added there lands here without a second copy.
        RecipeHeaderForm(host: notifier),
        const SizedBox(height: 24),
        for (final group in recipe.groups)
          _GroupEditor(
            key: ValueKey(group.id),
            group: group,
            recipeId: recipe.id,
            notifier: notifier,
            removable: recipe.groups.length > 1,
          ),
        const SizedBox(height: 4),
        FButton(
          variant: FButtonVariant.outline,
          prefix: const Icon(FLucideIcons.plus),
          onPress: notifier.addGroup,
          child: const Text('Add group'),
        ),
        const SizedBox(height: 28),
        MethodEditor(recipe: recipe, notifier: notifier),
      ],
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.recipeId,
    required this.notifier,
    required this.removable,
    super.key,
  });

  final IngredientGroup group;

  /// The recipe being edited — what the picker excludes from its "Your
  /// recipes" section, and what the cycle guard is asked about (D5).
  final String recipeId;
  final RecipeEditor notifier;
  final bool removable;

  /// The 7.7 two-step chain, with one more door at the first step (D7): the
  /// picker (board frame c) → the quantity sheet (frame b for an ingredient,
  /// frame d for a component) → the line lands fully quantified. Backing out
  /// of the quantity sheet still adds the line in its default unit — the
  /// quantity control re-opens the sheet.
  Future<void> _addLine(BuildContext context) async {
    final name = group.name;
    // The picker's search brings the keyboard, which shrinks the editor's
    // list under it: this group card can be unmounted by the time a row is
    // tapped. The second sheet opens from a context that outlives the card
    // (`hostContextOf`), and [notifier] is the editor's own, kept alive by
    // the page watching it — so the line is added whatever became of the
    // card. Never a `context.mounted` bail here: it would drop the pick.
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
          onSetYield: () => host.context.pushOnce('/recipes/${target.id}/edit'),
        );
        notifier.addComponentLineItem(
          group.id,
          target,
          quantity: result?.quantity,
          unit: result?.unit,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                FButton.icon(
                  variant: FButtonVariant.ghost,
                  onPress: () => notifier.removeGroup(group.id),
                  child: const Icon(FLucideIcons.trash2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (final item in group.items)
            _LineItemEditor(
              key: ValueKey(item.id),
              item: item,
              recipeId: recipeId,
              notifier: notifier,
            ),
          const SizedBox(height: 4),
          FButton(
            variant: FButtonVariant.secondary,
            size: FButtonSizeVariant.sm,
            prefix: const Icon(FLucideIcons.plus),
            onPress: () => _addLine(context),
            child: const Text('Add ingredient'),
          ),
        ],
      ),
    );
  }
}

class _LineItemEditor extends ConsumerWidget {
  const _LineItemEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
    super.key,
  });

  final LineItem item;

  /// The recipe being edited — what the identity picker excludes from its
  /// "Your recipes" section (a recipe cannot become its own component).
  final String recipeId;
  final RecipeEditor notifier;

  /// The quantity control's label: quantity + measure/unit — an unresolved
  /// measure id renders its honest count fallback with a pending note.
  String get _label {
    final qty = formatQuantity(item.quantity);
    final measure = item.measure;
    final unit = measure != null
        ? measure.label
        : item.measureId != null
        ? '${item.unit.label} · measure pending sync'
        : item.unit.label;
    return qty.isEmpty ? unit : '$qty $unit';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A component line (step 8.6 / D1) has no ingredient to look up: its
    // identity is the recipe chip, and its amount is edited against the
    // target's yields, not an ingredient's units.
    if (item.isComponent) {
      return _ComponentLineEditor(
        item: item,
        recipeId: recipeId,
        notifier: notifier,
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
      // An unresolved vocab row still gets a working sheet: a stub-shaped
      // stand-in scoped to the stored unit's family (no macros, no density —
      // nothing is invented for it).
      final sheetIngredient =
          ingredient ??
          Ingredient(
            id: item.ingredientId ?? '',
            canonicalName: item.ingredientName,
            defaultUnit: item.measure != null ? pieces : item.unit,
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
            : UnitOption(item.unit),
        pendingMeasure: pending,
        // An ingredient line offers the Optional switch (D6a); the component
        // branch above never reaches here, so the sheet never offers it
        // on a sub-recipe.
        initialOptional: item.optional,
      );
      if (result is! QuantitySaved) return;
      notifier.setLineItemQuantity(item.id, result.quantity);
      notifier.setLineItemOptional(item.id, optional: result.optional);
      switch (result.choice) {
        case MeasureOption(:final measure):
          notifier.setLineItemMeasure(item.id, measure);
        case UnitOption(:final unit):
          // An unresolved measure id survives an unrelated re-save; only an
          // explicit chip pick clears it (degrade-don't-destroy).
          if (!pending || result.unitPicked) {
            notifier.setLineItemUnit(item.id, unit);
          }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IdentityCell(
                  onTap: () => changeLineIdentity(
                    context,
                    recipeId: recipeId,
                    item: item,
                    notifier: notifier,
                  ),
                  child: Text(item.ingredientName, style: ansiSans(size: 15)),
                ),
                _UsedInSteps(count: notifier.stepsUsing(item.id)),
                const SizedBox(height: 6),
                _QuantityControl(label: _label, onTap: editQuantity),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => removeLineWithChips(context, item, notifier),
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ),
    );
  }
}

/// The identity cell, tappable (0022 D6). The Review screen has had
/// "tap to change" since step 8; the editor never has — which is why a swap
/// meant delete + re-add, a fresh `line_item_id`, and every chip pointing at
/// the old line going silently dangling.
class _IdentityCell extends StatelessWidget {
  const _IdentityCell({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      children: [
        Flexible(child: child),
        const SizedBox(width: 6),
        const Icon(FLucideIcons.pencil, size: 12, color: AnsiColors.muted),
      ],
    ),
  );
}

/// What depends on this line — the quiet count that makes the substitution
/// notice and the removal prompt read as consequences rather than surprises.
class _UsedInSteps extends StatelessWidget {
  const _UsedInSteps({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'used in $count ${count == 1 ? 'step' : 'steps'}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}

/// Tap the identity → the shipped picker → the line keeps its id and takes a
/// new one. Chips survive by construction; D3 then relabels them.
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

/// Removing a referenced line asks first (D3's sibling). Confirming converts
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
        '$steps ${steps == 1 ? 'step mentions' : 'steps mention'} '
        '${item.ingredientName}.',
    body:
        'Remove those chips too? Their words stay in the sentences — only '
        'the links go.',
    confirm: 'Remove',
  );
  if (confirmed) notifier.removeLineItem(item.id);
}

/// A component line in the editor (step 8.6 / D1, board frame a's identity
/// cell on an editor row): the recipe chip where the ingredient name sits, and
/// the same quantity control — opening the batch-math sheet instead of the
/// ingredient one.
///
/// A component whose target has not synced (or was deleted) keeps its stored
/// text and says so; the amount stays editable in batches, which needs no
/// target at all.
class _ComponentLineEditor extends StatelessWidget {
  const _ComponentLineEditor({
    required this.item,
    required this.recipeId,
    required this.notifier,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final target = item.subRecipe;
    final label = componentAmountText(item.quantity, item.unit);

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
        onSetYield: target == null
            ? null
            : () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      if (result == null) return;
      notifier
        ..setLineItemQuantity(item.id, result.quantity)
        ..setLineItemUnit(item.id, result.unit);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IdentityCell(
                  onTap: () => changeLineIdentity(
                    context,
                    recipeId: recipeId,
                    item: item,
                    notifier: notifier,
                  ),
                  child: target != null
                      ? RecipeChip(title: target.title)
                      : Text(
                          '${item.ingredientName} · linked recipe missing',
                          style: ansiSans(size: 15, color: AnsiColors.muted),
                        ),
                ),
                _UsedInSteps(count: notifier.stepsUsing(item.id)),
                const SizedBox(height: 6),
                _QuantityControl(label: label, onTap: editQuantity),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => removeLineWithChips(context, item, notifier),
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ),
    );
  }
}

/// The tap-to-edit amount pill both line-editor rows wear.
class _QuantityControl extends StatelessWidget {
  const _QuantityControl({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: ansiMono(size: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(FLucideIcons.pencil, size: 12, color: AnsiColors.muted),
          ],
        ),
      ),
    );
  }
}
