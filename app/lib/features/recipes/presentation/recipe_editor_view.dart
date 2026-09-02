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
import '../../books/data/book_providers.dart';
import '../../books/presentation/book_view_models.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
import '../../ingredients/presentation/quantity_unit_sheet.dart';
import '../domain/recipe.dart';
import 'format.dart';
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
                    if (context.mounted) context.go('/recipes/$id');
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
        const _Label('METHOD'),
        if (recipe.methodSteps != null)
          const _TokenizedMethodNotice()
        else
          FTextField.multiline(
            hint: 'One step per line',
            maxLines: 12,
            control: FTextFieldControl.managed(
              initial: TextEditingValue(text: recipe.steps.join('\n')),
              onChange: (v) => notifier.setStepsText(v.text),
            ),
          ),
      ],
    );
  }
}

/// What the METHOD slot shows for an IMPORTED recipe. Its method is a token
/// stream (ingredient chips + timers), which this plain-text field cannot
/// represent — rendering it as an empty box would read as "this recipe has no
/// method" and invite the user to type one over it. So the editor says so
/// plainly instead: the method is preserved untouched by a save, and stays
/// readable on the recipe page. Editing tokenized steps lands with the method
/// editor.
class _TokenizedMethodNotice extends StatelessWidget {
  const _TokenizedMethodNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AnsiColors.paper,
        border: Border.all(color: AnsiColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(FLucideIcons.info, size: 14, color: AnsiColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This recipe’s method was imported as ingredient chips and '
                'timers, which this text editor can’t show. It is kept exactly '
                'as it is when you save — read it on the recipe page.',
                style: ansiMono(
                  size: 11,
                  color: AnsiColors.muted,
                ).copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
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
            onPress: () async {
              // The 7.7 two-step chain: picker (frame a) → quantity + unit
              // chips (frame b) → the line lands fully quantified. Backing
              // out of the quantity sheet still adds the ingredient in its
              // default unit — the quantity control re-opens the sheet.
              final name = group.name;
              final ingredient = await showIngredientPicker(
                context,
                title: name == null || name.isEmpty
                    ? 'Add an ingredient'
                    : 'Add to “$name”',
              );
              if (ingredient == null || !context.mounted) return;
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
            },
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
    // A component line (step 8.6 / D1) has no ingredient to look up — the
    // empty id resolves to nothing and the row falls through to the same
    // stub-shaped stand-in an unsynced vocab row gets. Lane U replaces this
    // identity cell with the recipe chip the board draws.
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
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: editQuantity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                            _label,
                            style: ansiMono(size: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          FLucideIcons.pencil,
                          size: 12,
                          color: AnsiColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
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
