/// The recipe editor — create (`recipeId == null`) or edit an existing recipe.
///
/// Fields are uncontrolled (`initial` + `onChange`) and every repeating child
/// is keyed by its stable domain id, so the notifier rebuilding the tree on
/// each edit never resets a controller or moves the caret.
///
/// The ingredient list is **one flat reorderable list**: a heading row starts
/// each group and the line rows after it belong to it, so dragging a line
/// under another heading files it there. Reordering a line and moving it
/// between groups are the same gesture, and a moved line keeps its id — which
/// is what keeps every method chip pointing at it.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/reorder_grip.dart';
import '../../../shared/write.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'component_quantity_sheet.dart';
import 'ingredient_line.dart';
import 'line_target_picker.dart';
import 'method_editor.dart';
import 'recipe_chip.dart';
import 'recipe_header_form.dart';
import 'recipe_view_models.dart';

/// The query parameter that asks a NEW recipe's editor to hand the recipe
/// back instead of landing on its page. One name, one place, so the route the
/// picker writes and the route the router reads agree.
const kHandBackQueryParam = 'handback';

/// The pushed route for a sub-recipe that does not exist yet — what a line
/// target picker opens when the thing the line wants has not been written.
///
/// [title] prefills the field with the words already typed into the picker's
/// search, and the editor pops with the saved recipe as a [SubRecipeTarget]
/// (or null if the person backed out) so the line waiting on it can be made.
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

  /// Seeds a NEW recipe's title (`/recipes/new?title=…`) — the query the
  /// Library's "nothing matches" state was searched for. Ignored when
  /// [recipeId] is set: an existing recipe already has a title.
  final String? initialTitle;

  /// The shelf the door that opened this knew about (0028 E3) — a section's
  /// `＋` carries both; every other door carries neither.
  final String? initialBookId;
  final String? initialSectionId;

  /// Whether Save should POP with the recipe as a [SubRecipeTarget] rather
  /// than land on its page — true only for the picker door
  /// ([newSubRecipeRoute]), where a line is being held open for it.
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
                    final saved = await ref.write(
                      context,
                      'save the recipe',
                      notifier.save,
                    );
                    if (saved == null || !context.mounted) return;
                    // Editing returns you to where you opened the editor;
                    // creating lands you on the thing you made. An existing
                    // recipe's page is already beneath the editor as a watched
                    // query, so a pop shows the save — replacing would stack a
                    // second copy of that page and cost a second back. A new
                    // recipe has only its opener beneath, so the editor is
                    // replaced (not `go`ne to: that would flatten the stack,
                    // back would leave the app and the iOS edge swipe would
                    // vanish on a page that looks exactly like a pushed one).
                    // …unless a picker pushed this to make a sub-recipe: that
                    // line is still open under the editor, and landing on the
                    // new recipe's page would abandon it.
                    if (recipeId != null) {
                      context.pop();
                    } else if (handsBackTarget) {
                      context.pop(saved.asSubRecipeTarget);
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

class _EditorForm extends StatelessWidget {
  const _EditorForm({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    // ONE flat list per recipe: a heading row starts each group, and every
    // line row after it belongs to it. A line dropped under another heading is
    // filed under that heading, so reordering a line and moving it to another
    // group are one gesture rather than two features.
    final rows = <Widget>[];
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
        rows.add(
          _LineItemEditor(
            key: ValueKey('line-${item.id}'),
            item: item,
            recipeId: recipe.id,
            notifier: notifier,
            dragIndex: rows.length,
          ),
        );
      }
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          // The header is the one the import review renders too: the notifier
          // is its host, so a section added there lands here without a second
          // copy.
          sliver: SliverList.list(children: [RecipeHeaderForm(host: notifier)]),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverReorderableList(
            itemCount: rows.length,
            itemBuilder: (context, index) => rows[index],
            onReorderItem: notifier.moveLine,
            proxyDecorator: liftedRow,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          // A list rather than one box: the slivers stay lazy, so a long
          // method's step cards are not all built to show the top of the page.
          sliver: SliverList.list(
            children: [
              _ListDoors(recipe: recipe, notifier: notifier),
              const SizedBox(height: 28),
              MethodEditor(recipe: recipe, notifier: notifier),
            ],
          ),
        ),
      ],
    );
  }
}

/// The list's own two doors, tight under the last line — the review screen's
/// pair, in the editor's words. A line added lands in the LAST group, which is
/// what makes *Add group* then *Add ingredient* read as one gesture; the drag
/// then puts it wherever it belongs.
class _ListDoors extends StatelessWidget {
  const _ListDoors({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: FButton(
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
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: FButton(
          variant: FButtonVariant.outline,
          size: FButtonSizeVariant.sm,
          prefix: const Icon(FLucideIcons.plus),
          onPress: notifier.addGroup,
          child: const Text('Add group'),
        ),
      ),
    ],
  );
}

/// One group's heading row: the name as an editable field, and the bin.
///
/// It is a row of the same flat list the lines are in — which is what lets a
/// line be dropped under it. The heading itself does not drag: reordering
/// *groups* is a separate question, and a line moving between them is what was
/// asked for.
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

/// The 7.7 two-step chain, with one more door at the first step (D7): the
/// picker (board frame c) → the quantity sheet (frame b for an ingredient,
/// frame d for a component) → the line lands fully quantified. Backing out of
/// the quantity sheet still adds the line in its default unit — the amount
/// cell re-opens the sheet.
Future<void> addLineToGroup(
  BuildContext context, {
  required IngredientGroup group,
  required String recipeId,
  required RecipeEditor notifier,
}) async {
  final name = group.name;
  // The picker's search brings the keyboard, which shrinks the editor's list
  // under it: the door can be unmounted by the time a row is tapped. The
  // second sheet opens from a context that outlives it (`hostContextOf`), and
  // [notifier] is the editor's own, kept alive by the page watching it — so
  // the line is added whatever became of the door. Never a `context.mounted`
  // bail here: it would drop the pick.
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
    super.key,
  });

  final LineItem item;

  /// The recipe being edited — what the identity picker excludes from its
  /// "Your recipes" section (a recipe cannot become its own component).
  final String recipeId;
  final RecipeEditor notifier;

  /// This row's position in the flat list — what the grip drags by.
  final int dragIndex;

  /// The amount cell's label. Every line prints what the recipe page prints;
  /// only an unresolved measure id adds anything, and what it adds is the
  /// honest count fallback with a note saying why the measure is not there.
  ///
  /// **Two reasons, two words.** A measure whose row has not synced down yet
  /// arrives on its own, and "pending sync" is a promise the app keeps; one
  /// the household deleted never arrives, and the same words would have the
  /// reader waiting on nothing.
  String get _label {
    if (item.measure == null && item.measureId != null) {
      final qty = formatQuantityIn(item.quantity, item.unit);
      final why = item.measureDeleted
          ? 'measure deleted'
          : 'measure pending sync';
      final unit = '${item.unit.label} · $why';
      return qty.isEmpty ? unit : '$qty $unit';
    }
    return amountOfLineItem(item);
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
        dragIndex: dragIndex,
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

    return _LineRow(
      amount: _label,
      dragIndex: dragIndex,
      usedIn: notifier.stepsUsing(item.id),
      onEditAmount: editQuantity,
      onEditIdentity: () => changeLineIdentity(
        context,
        recipeId: recipeId,
        item: item,
        notifier: notifier,
      ),
      onRemove: () => removeLineWithChips(context, item, notifier),
      identity: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: item.ingredientName,
              // A retired row's last known name, muted like the dangling
              // component one row down — same news, same voice.
              style: item.ingredientDeleted
                  ? ansiSans(size: 15, color: AnsiColors.muted)
                  : ansiSans(size: 15, weight: FontWeight.w500),
            ),
            ...noteSpans(item.note),
            ...optionalSpans(optional: item.optional),
            // The identity cell is already the picker's door, so the tag's
            // "pick again" is a thing the next tap actually does.
            ...removedIngredientSpans(removed: item.ingredientDeleted),
          ],
        ),
      ),
    );
  }
}

/// A component line in the editor (step 8.6 / D1, board frame a's identity
/// cell on an editor row): the recipe chip where the ingredient name sits, and
/// the same amount cell — opening the batch-math sheet instead of the
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
    required this.dragIndex,
  });

  final LineItem item;
  final String recipeId;
  final RecipeEditor notifier;
  final int dragIndex;

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
        initialOptional: item.optional,
        onSetYield: target == null
            ? null
            : () => host.context.pushOnce('/recipes/${target.id}/edit'),
      );
      if (result == null) return;
      notifier
        ..setLineItemQuantity(item.id, result.quantity)
        ..setLineItemUnit(item.id, result.unit)
        ..setLineItemOptional(item.id, optional: result.optional);
    }

    return _LineRow(
      amount: componentAmountText(item.quantity, item.unit),
      dragIndex: dragIndex,
      usedIn: notifier.stepsUsing(item.id),
      onEditAmount: editQuantity,
      onEditIdentity: () => changeLineIdentity(
        context,
        recipeId: recipeId,
        item: item,
        notifier: notifier,
      ),
      onRemove: () => removeLineWithChips(context, item, notifier),
      // A dangling link reads as the plain text it stored, muted, and says why
      // there is no chip — the recipe page's own degradation.
      identity: target != null
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
    );
  }
}

/// The editor's ingredient line, in the ONE layout the app prints everywhere:
/// `[amount] [name] [note]` on a single row, the amount in its own fixed
/// column so every identity left-aligns.
///
/// The row carries the two doors it has always had — the amount cell opens the
/// quantity sheet, the identity cell opens the target picker — plus the grip
/// that drags it and the bin that removes it. *used in N steps* is a second
/// muted line under the name, and only when there is one: it is a fact about
/// the line, not a control.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.amount,
    required this.identity,
    required this.usedIn,
    required this.dragIndex,
    required this.onEditAmount,
    required this.onEditIdentity,
    required this.onRemove,
  });

  final String amount;
  final Widget identity;
  final int usedIn;
  final int dragIndex;
  final VoidCallback onEditAmount;
  final VoidCallback onEditIdentity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DragGrip(index: dragIndex),
          // The cell is named, because what it prints is the recipe page's
          // amount and a count line's amount is a bare number: "1" tells a
          // reader nothing about what it opens or what it measures.
          Semantics(
            label: 'Amount',
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onEditAmount,
              child: SizedBox(
                width: kLineAmountWidth,
                child: Text(
                  amount.isEmpty ? '—' : amount,
                  style: ansiMono(size: 14, color: AnsiColors.muted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IdentityCell(onTap: onEditIdentity, child: identity),
                _UsedInSteps(count: usedIn),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: onRemove,
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ),
    );
  }
}

/// The note, as the modifier every three-part line prints it: a hairline
/// separator, then muted italic. Empty when the line carries none.
List<InlineSpan> noteSpans(String? note) {
  final text = note?.trim();
  if (text == null || text.isEmpty) return const [];
  return [
    TextSpan(
      text: '  ·  ',
      style: ansiSans(size: 15, color: AnsiColors.line),
    ),
    TextSpan(
      text: text,
      style: ansiSans(
        size: 14,
        color: AnsiColors.muted,
      ).copyWith(fontStyle: FontStyle.italic),
    ),
  ];
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
        'used in $count ${plural(count, 'step')}',
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
        '$steps ${plural(steps, 'step mentions', plural: 'steps mention')} '
        '${item.ingredientName}.',
    body:
        'Remove those chips too? Their words stay in the sentences — only '
        'the links go.',
    confirm: 'Remove',
  );
  if (confirmed) notifier.removeLineItem(item.id);
}
