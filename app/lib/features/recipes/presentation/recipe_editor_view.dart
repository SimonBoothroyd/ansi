/// The recipe editor — create (`recipeId == null`) or edit an existing recipe.
///
/// Fields are uncontrolled (`initial` + `onChange`) and every repeating child
/// is keyed by its stable domain id, so the notifier rebuilding the tree on
/// each edit never resets a controller or moves the caret.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/units/units.dart';
import '../../../shared/guarded_navigation.dart';
import '../../books/data/book_providers.dart';
import '../../books/presentation/book_view_models.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/recipe.dart';
import 'component_format.dart';
import 'component_quantity_sheet.dart';
import 'format.dart';
import 'line_target_picker.dart';
import 'method_editor.dart';
import 'recipe_chip.dart';
import 'recipe_view_models.dart';

class RecipeEditorView extends ConsumerWidget {
  const RecipeEditorView({this.recipeId, super.key});

  final String? recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recipeEditorProvider(recipeId));
    final notifier = ref.read(recipeEditorProvider(recipeId).notifier);

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
                    final id = await notifier.save();
                    // Replace the editor with the saved recipe, rather than
                    // `go`: `go` would flatten the stack to one page, so back
                    // would leave the app and the iOS edge-swipe would vanish
                    // on a page that looks exactly like a pushed one. A
                    // replacement swaps the top page and leaves whatever the
                    // editor was opened from underneath it.
                    if (context.mounted) {
                      context.pushReplacement('/recipes/$id');
                    }
                  },
            child: const Text('Save'),
          ),
        ],
      ),
      child: async.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) {
          debugPrint('recipe editor load failed: $e');
          return Center(
            child: Text(
              'Could not open the editor.',
              style: ansiMono(size: 13, color: AnsiColors.muted),
            ),
          );
        },
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
        const _Label('TITLE'),
        FTextField(
          hint: 'e.g. Weeknight Chicken Curry',
          control: FTextFieldControl.managed(
            initial: TextEditingValue(text: recipe.title),
            onChange: (v) => notifier.setTitle(v.text),
          ),
        ),
        const SizedBox(height: 20),
        const _Label('SERVES'),
        _ServesStepper(
          servings: recipe.servingsBase,
          onChanged: notifier.setServings,
        ),
        const SizedBox(height: 20),
        const _MakesLabel(),
        _MakesSection(recipe: recipe, notifier: notifier),
        const SizedBox(height: 20),
        const _Label('SHELF LIFE'),
        _ShelfLifeSection(recipe: recipe, notifier: notifier),
        const SizedBox(height: 20),
        const _Label('FILE UNDER'),
        _FilingPicker(recipe: recipe, notifier: notifier),
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
    final picked = await showLineTargetPicker(
      context,
      editingRecipeId: recipeId,
      title: name == null || name.isEmpty
          ? 'Add an ingredient'
          : 'Add to “$name”',
    );
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case PickedIngredient(:final ingredient):
        final result = await showQuantityUnitSheet(
          context,
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
          context,
          target: target,
          onSetYield: () => context.pushOnce('/recipes/${target.id}/edit'),
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
    required this.notifier,
    super.key,
  });

  final LineItem item;
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
      return _ComponentLineEditor(item: item, notifier: notifier);
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
      );
      if (result is! QuantitySaved) return;
      notifier.setLineItemQuantity(item.id, result.quantity);
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
                Text(item.ingredientName, style: ansiSans(size: 15)),
                const SizedBox(height: 6),
                _QuantityControl(label: _label, onTap: editQuantity),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => notifier.removeLineItem(item.id),
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ),
    );
  }
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
  const _ComponentLineEditor({required this.item, required this.notifier});

  final LineItem item;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    final target = item.subRecipe;
    final label = componentAmountText(item.quantity, item.unit);

    Future<void> editQuantity() async {
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
            : () => context.pushOnce('/recipes/${target.id}/edit'),
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
                if (target != null)
                  RecipeChip(title: target.title)
                else
                  Text(
                    '${item.ingredientName} · linked recipe missing',
                    style: ansiSans(size: 15, color: AnsiColors.muted),
                  ),
                const SizedBox(height: 6),
                _QuantityControl(label: label, onTap: editQuantity),
              ],
            ),
          ),
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: () => notifier.removeLineItem(item.id),
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

/// "MAKES · optional" — the label the board's frame h draws, with the optional
/// half in sentence case beside the eyebrow.
class _MakesLabel extends StatelessWidget {
  const _MakesLabel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('MAKES', style: ansiLabel()),
          const SizedBox(width: 6),
          Text(
            '· optional',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ],
      ),
    );
  }
}

/// The MAKES numbers block (step 8.6 / D2 · D9, design board frame h): what
/// one batch yields, in up to TWO denominations.
///
/// Serves and makes are two independent facts — serves is how the recipe
/// portions, makes is how much comes out — and neither derives from the other.
/// The second denomination's selector offers only the OTHER families: two ways
/// of saying one batch ("makes 250 g · 16 tbsp"), never two numbers in one
/// family. It can only be added once the first is stated, which is what the
/// migration's CHECK says too — a save must not be able to bounce off it.
class _MakesSection extends HookWidget {
  const _MakesSection({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  /// The units a yield may be stated in: everything an ingredient line can say
  /// except the imprecise words — "makes a pinch" is not a yield, and `batch`
  /// is what a yield is measured *against*, never in.
  static final List<Unit> _units = [
    for (final u in kIngredientUnits)
      if (u.family != UnitFamily.imprecise) u,
  ];

  @override
  Widget build(BuildContext context) {
    final unit = useState<Unit>(recipe.yieldUnit ?? g);
    final unit2 = useState<Unit?>(recipe.yieldUnit2);
    final hasFirst = recipe.yieldQty != null && recipe.yieldUnit != null;
    final showSecond = recipe.yieldQty2 != null || unit2.value != null;

    // The second slot's offer: the other families only.
    final otherFamilies = [
      for (final u in _units)
        if (u.family != unit.value.family) u,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _YieldRow(
          key: const ValueKey('yield-1'),
          quantity: recipe.yieldQty,
          unit: unit.value,
          units: _units,
          onChanged: (qty, u) {
            unit.value = u;
            notifier.setYield(qty, u);
          },
        ),
        if (hasFirst && showSecond) ...[
          const SizedBox(height: 8),
          _YieldRow(
            key: const ValueKey('yield-2'),
            quantity: recipe.yieldQty2,
            unit: unit2.value ?? otherFamilies.first,
            units: otherFamilies,
            onRemove: () {
              unit2.value = null;
              notifier.setSecondYield(null, null);
            },
            onChanged: (qty, u) {
              unit2.value = u;
              notifier.setSecondYield(qty, u);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'the second slot only offers the other families — two ways of '
              'saying one batch, never two numbers in one family',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
          ),
        ] else if (hasFirst) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FButton(
              variant: FButtonVariant.ghost,
              size: FButtonSizeVariant.sm,
              prefix: const Icon(FLucideIcons.plus),
              onPress: () => unit2.value = otherFamilies.first,
              child: const Text('Another denomination'),
            ),
          ),
        ],
      ],
    );
  }
}

/// One "amount + unit" yield row, with the second slot's remove affordance.
class _YieldRow extends StatelessWidget {
  const _YieldRow({
    required this.quantity,
    required this.unit,
    required this.units,
    required this.onChanged,
    this.onRemove,
    super.key,
  });

  final double? quantity;
  final Unit unit;
  final List<Unit> units;
  final void Function(double? quantity, Unit unit) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: FTextField(
            hint: 'amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            control: FTextFieldControl.managed(
              initial: TextEditingValue(text: formatQuantity(quantity)),
              onChange: (v) => onChanged(
                v.text.trim().isEmpty ? null : double.tryParse(v.text.trim()),
                unit,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FSelect<String>.rich(
            format: (id) => unitById(id)?.label ?? '—',
            control: FSelectControl<String>.lifted(
              value: unit.id,
              onChange: (id) {
                final picked = id == null ? null : unitById(id);
                if (picked != null) onChanged(quantity, picked);
              },
            ),
            children: [
              for (final u in units)
                FSelectItem(title: Text(u.label), value: u.id),
            ],
          ),
        ),
        if (onRemove != null) ...[
          const SizedBox(width: 4),
          FButton.icon(
            variant: FButtonVariant.ghost,
            onPress: onRemove,
            child: const Icon(FLucideIcons.x),
          ),
        ],
      ],
    );
  }
}

class _ServesStepper extends StatelessWidget {
  const _ServesStepper({required this.servings, required this.onChanged});

  final double servings;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FButton.icon(
          onPress: servings > 1 ? () => onChanged(servings - 1) : null,
          child: const Icon(FLucideIcons.minus),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            formatQuantity(servings),
            style: ansiMono(size: 18, weight: FontWeight.w600),
          ),
        ),
        FButton.icon(
          onPress: () => onChanged(servings + 1),
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

/// The shelf-life inputs that make a recipe batchable (step 5): how long it
/// keeps in the fridge (drives cook-plan clustering), whether it freezes, and
/// the freezer window. Fridge days unset ⇒ the cook plan never splits it.
class _ShelfLifeSection extends StatelessWidget {
  const _ShelfLifeSection({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepperRow(
          label: 'Keeps in the fridge',
          days: recipe.keepsForDays,
          unsetText: 'not set',
          onChanged: notifier.setKeepsForDays,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Drives the batch cook plan — how far apart the same dish can be '
            'planned before it becomes two things to cook.',
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
        ),
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Freezes', style: ansiSans(size: 15)),
          value: recipe.freezable,
          onChange: notifier.setFreezable,
        ),
        if (recipe.freezable) ...[
          const SizedBox(height: 12),
          _StepperRow(
            label: 'Keeps in the freezer',
            days: recipe.freezerDays,
            unsetText: 'no limit',
            onChanged: notifier.setFreezerDays,
          ),
        ],
      ],
    );
  }
}

/// A label with a nullable "N days" stepper. Stepping below 1 clears the value
/// (rendered as [unsetText]); stepping up from unset starts at 1.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.days,
    required this.unsetText,
    required this.onChanged,
  });

  final String label;
  final int? days;
  final String unsetText;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = days;
    return Row(
      children: [
        Expanded(child: Text(label, style: ansiSans(size: 15))),
        FButton.icon(
          onPress: value == null
              ? null
              : () => onChanged(value <= 1 ? null : value - 1),
          child: const Icon(FLucideIcons.minus),
        ),
        SizedBox(
          width: 84,
          child: Text(
            value == null ? unsetText : '$value ${value == 1 ? 'day' : 'days'}',
            textAlign: TextAlign.center,
            style: value == null
                ? ansiMono(size: 13, color: AnsiColors.muted)
                : ansiMono(size: 15, weight: FontWeight.w600),
          ),
        ),
        FButton.icon(
          onPress: () => onChanged((value ?? 0) + 1),
          child: const Icon(FLucideIcons.plus),
        ),
      ],
    );
  }
}

/// Picks the book + section the recipe is filed under. Book choices come from
/// the Library; the section list follows the chosen book, plus an "Unsectioned"
/// option (value `''`) and a "+" that creates a new section inline.
class _FilingPicker extends ConsumerWidget {
  const _FilingPicker({required this.recipe, required this.notifier});

  final Recipe recipe;
  final RecipeEditor notifier;

  static const _unsectioned = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).asData?.value ?? const [];
    if (books.isEmpty) return const SizedBox.shrink();

    final currentBookId = recipe.bookId ?? books.first.id;
    final currentBook = books.firstWhere(
      (b) => b.id == currentBookId,
      orElse: () => books.first,
    );
    final bookNames = {for (final b in books) b.id: b.name};
    final sectionNames = {for (final s in currentBook.sections) s.id: s.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FSelect<String>.rich(
          format: (id) => bookNames[id] ?? '—',
          control: FSelectControl<String>.lifted(
            value: currentBookId,
            onChange: (id) {
              if (id != null) notifier.setBook(id);
            },
          ),
          children: [
            for (final b in books)
              FSelectItem(title: Text(b.name), value: b.id),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FSelect<String>.rich(
                format: (id) => id == _unsectioned
                    ? 'Unsectioned'
                    : (sectionNames[id] ?? 'Unsectioned'),
                control: FSelectControl<String>.lifted(
                  value: recipe.sectionId ?? _unsectioned,
                  onChange: (id) => notifier.setSection(
                    (id == null || id == _unsectioned) ? null : id,
                  ),
                ),
                children: [
                  const FSelectItem(
                    title: Text('Unsectioned'),
                    value: _unsectioned,
                  ),
                  for (final s in currentBook.sections)
                    FSelectItem(title: Text(s.name), value: s.id),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FButton.icon(
              variant: FButtonVariant.secondary,
              onPress: () async {
                final name = await promptForText(
                  context,
                  title: 'New section',
                  hint: 'Name it anything',
                  confirm: 'Add',
                );
                if (name != null && name.trim().isNotEmpty) {
                  final id = await ref
                      .read(bookRepositoryProvider)
                      .createSection(currentBookId, name);
                  notifier.setSection(id);
                }
              },
              child: const Icon(FLucideIcons.plus),
            ),
          ],
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: ansiLabel()),
    );
  }
}
