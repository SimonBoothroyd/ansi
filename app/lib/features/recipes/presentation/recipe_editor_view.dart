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

import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../books/presentation/book_view_models.dart';
import '../../books/presentation/text_prompt.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/presentation/ingredient_picker.dart';
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
          style: miseHeaderTitle(),
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
              style: miseMono(size: 13, color: MiseColors.muted),
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
        color: MiseColors.paper,
        border: Border.all(color: MiseColors.line),
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
              final ingredient = await showIngredientPicker(context);
              if (ingredient != null) {
                notifier.addLineItem(group.id, ingredient);
              }
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

  /// The dropdown's choices: the honest unit set for the resolved vocab entry
  /// (tech-debt row `shopping/units`) plus the ingredient's live measures
  /// ("potato, large (299 g)"), falling back to the full catalog while
  /// unresolved. The stored selection stays selectable even outside the
  /// filter, so an existing line never renders an orphaned value.
  List<UnitChoice> _choices(Ingredient? ingredient, List<Measure> measures) {
    final allowed = ingredient == null
        ? [for (final u in kAllUnits) UnitOption(u)]
        : allowedUnitChoicesFor(ingredient, measures);
    final current = _selected;
    return allowed.contains(current) ? allowed : [...allowed, current];
  }

  /// The line's current selection: its measure when it has one (resolved or
  /// not — an unresolved id still renders as the stored count unit), else its
  /// plain unit.
  UnitChoice get _selected {
    final measure = item.measure;
    return measure == null ? UnitOption(item.unit) : MeasureOption(measure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ingredient = ref
        .watch(
          lineItemIngredientProvider(
            ingredientId: item.ingredientId,
            name: item.ingredientName,
          ),
        )
        .asData
        ?.value;
    final measures =
        ref
            .watch(ingredientMeasuresProvider(item.ingredientId))
            .asData
            ?.value ??
        const <Measure>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.ingredientName, style: miseSans(size: 15)),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                width: 92,
                child: FTextField(
                  hint: 'qty',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  control: FTextFieldControl.managed(
                    initial: TextEditingValue(
                      text: formatQuantity(item.quantity),
                    ),
                    onChange: (v) => notifier.setLineItemQuantity(
                      item.id,
                      v.text.trim().isEmpty ? null : double.tryParse(v.text),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FSelect<UnitChoice>.rich(
                  hint: 'unit',
                  // An unresolved measure_id renders as its honest count
                  // fallback — the note says why it's a plain "piece" until
                  // the measure row syncs in.
                  format: (c) => item.measureId != null && item.measure == null
                      ? '${c.label} (measure pending sync)'
                      : c.label,
                  control: FSelectControl<UnitChoice>.lifted(
                    value: _selected,
                    onChange: (c) => switch (c) {
                      UnitOption(:final unit) => notifier.setLineItemUnit(
                        item.id,
                        unit,
                      ),
                      MeasureOption(:final measure) =>
                        notifier.setLineItemMeasure(item.id, measure),
                      null => null,
                    },
                  ),
                  children: [
                    for (final c in _choices(ingredient, measures))
                      FSelectItem(title: Text(c.label), value: c),
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
            style: miseMono(size: 18, weight: FontWeight.w600),
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
            style: miseMono(size: 11, color: MiseColors.muted),
          ),
        ),
        const SizedBox(height: 14),
        FSwitch(
          label: Text('Freezes', style: miseSans(size: 15)),
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
        Expanded(child: Text(label, style: miseSans(size: 15))),
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
                ? miseMono(size: 13, color: MiseColors.muted)
                : miseMono(size: 15, weight: FontWeight.w600),
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
      child: Text(text, style: miseLabel()),
    );
  }
}
