/// Riverpod ViewModels for the recipes UI.
///
/// Read models are thin streams off the repository; the editor is a small
/// [RecipeEditor] notifier holding the in-progress aggregate with immutable
/// mutators the editor view calls.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../data/recipe_providers.dart';
import '../domain/recipe.dart';

part 'recipe_view_models.g.dart';

const _uuid = Uuid();

/// The recipe list, newest first.
@riverpod
Stream<List<RecipeSummary>> recipeList(Ref ref) =>
    ref.watch(recipeRepositoryProvider).watchRecipes();

/// A single recipe aggregate, or null if it doesn't exist.
@riverpod
Stream<Recipe?> recipeById(Ref ref, String id) =>
    ref.watch(recipeRepositoryProvider).watchRecipe(id);

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by `allowedUnitsFor`. The repository only exposes
/// search (ADR-0004), so this searches by the denormalised name and matches on
/// id; null when the vocab row can't be resolved (the dropdown then falls back
/// to the full catalog).
@riverpod
Future<Ingredient?> lineItemIngredient(
  Ref ref, {
  required String ingredientId,
  required String name,
}) async {
  final matches = await ref
      .watch(ingredientRepositoryProvider)
      .search(name, limit: 10);
  for (final m in matches) {
    if (m.id == ingredientId) return m;
  }
  return null;
}

/// Editable recipe state. `build` loads an existing recipe (edit) or starts a
/// blank one with a fresh id and a single empty group (create).
@riverpod
class RecipeEditor extends _$RecipeEditor {
  @override
  Future<Recipe> build(String? recipeId) async {
    if (recipeId != null) {
      final existing = await ref
          .read(recipeRepositoryProvider)
          .watchRecipe(recipeId)
          .first;
      if (existing != null) return existing;
    }
    // New recipe: file it into the default book (Unsectioned) so it surfaces in
    // the Library the moment it's saved.
    final book = await ref.read(bookRepositoryProvider).ensureDefaultBook();
    return Recipe(
      id: _uuid.v4(),
      title: '',
      servingsBase: 2,
      bookId: book.id,
      groups: [IngredientGroup(id: _uuid.v4())],
    );
  }

  Recipe get _current => state.requireValue;
  void _set(Recipe r) => state = AsyncData(r);

  /// True while a [save] is in flight. A double-tapped Save would otherwise run
  /// the child-diff write twice concurrently.
  bool _saving = false;

  void setTitle(String title) => _set(_current.copyWith(title: title));

  void setServings(double servings) =>
      _set(_current.copyWith(servingsBase: servings <= 0 ? 1 : servings));

  /// Sets the fridge shelf life in days; null (or a non-positive value) leaves
  /// it unset — the cook plan then never splits this recipe.
  void setKeepsForDays(int? days) => _set(
    _current.copyWith(keepsForDays: (days == null || days <= 0) ? null : days),
  );

  /// Toggles whether the dish freezes. Clearing it also drops any freezer
  /// window (a non-freezable recipe has no freezer days). Positional bool to
  /// tear off directly as a `ValueChanged<bool>` for the switch.
  // ignore: avoid_positional_boolean_parameters
  void setFreezable(bool freezable) => _set(
    _current.copyWith(
      freezable: freezable,
      freezerDays: freezable ? _current.freezerDays : null,
    ),
  );

  /// Sets the freezer shelf life in days; null (or non-positive) means "no
  /// limit" — a freezable recipe merges however far the meal is.
  void setFreezerDays(int? days) => _set(
    _current.copyWith(freezerDays: (days == null || days <= 0) ? null : days),
  );

  /// Files the recipe into [bookId], clearing the section (a new book has none
  /// in common with the old one).
  void setBook(String bookId) =>
      _set(_current.copyWith(bookId: bookId, sectionId: null));

  /// Sets (or clears, with null) the section within the current book.
  void setSection(String? sectionId) =>
      _set(_current.copyWith(sectionId: sectionId));

  void addGroup() => _set(
    _current.copyWith(
      groups: [
        ..._current.groups,
        IngredientGroup(id: _uuid.v4()),
      ],
    ),
  );

  void setGroupName(String groupId, String? name) => _mapGroup(
    groupId,
    (g) => g.copyWith(name: (name?.trim().isEmpty ?? true) ? null : name),
  );

  void removeGroup(String groupId) => _set(
    _current.copyWith(
      groups: _current.groups.where((g) => g.id != groupId).toList(),
    ),
  );

  /// Appends a line for [ingredient]. The 7.7 add flow hands the quantity +
  /// unit choice straight from the quantity sheet; without a [choice] the
  /// line starts in the ingredient's default unit.
  void addLineItem(
    String groupId,
    Ingredient ingredient, {
    double? quantity,
    UnitChoice? choice,
  }) => _mapGroup(
    groupId,
    (g) => g.copyWith(
      items: [
        ...g.items,
        LineItem(
          id: _uuid.v4(),
          ingredientId: ingredient.id,
          ingredientName: ingredient.canonicalName,
          quantity: quantity,
          // A measure line stores the honest count fallback — see [LineItem].
          unit: switch (choice) {
            MeasureOption() => pieces,
            UnitOption(:final unit) => unit,
            null => ingredient.defaultUnit,
          },
          measureId: switch (choice) {
            MeasureOption(:final measure) => measure.id,
            _ => null,
          },
          measure: switch (choice) {
            MeasureOption(:final measure) => measure,
            _ => null,
          },
        ),
      ],
    ),
  );

  void setLineItemQuantity(String itemId, double? quantity) =>
      _mapItem(itemId, (i) => i.copyWith(quantity: quantity));

  /// Quantifies the line in a plain unit, clearing any measure.
  void setLineItemUnit(String itemId, Unit unit) => _mapItem(
    itemId,
    (i) => i.copyWith(unit: unit, measureId: null, measure: null),
  );

  /// Quantifies the line in a named [measure] ("2 × potato, large"). The
  /// stored unit becomes the count fallback (`pieces`) — see [LineItem].
  void setLineItemMeasure(String itemId, Measure measure) => _mapItem(
    itemId,
    (i) => i.copyWith(unit: pieces, measureId: measure.id, measure: measure),
  );

  void removeLineItem(String itemId) => _set(
    _current.copyWith(
      groups: [
        for (final g in _current.groups)
          g.copyWith(items: g.items.where((i) => i.id != itemId).toList()),
      ],
    ),
  );

  /// Replaces the whole method from a single multiline field — one step per
  /// line. Blank lines are kept here so the field round-trips; [save] drops
  /// them on persist.
  void setStepsText(String text) =>
      _set(_current.copyWith(steps: text.split('\n')));

  /// Persists the recipe (dropping blank steps) and returns its id. A second
  /// call while the first is still writing is a no-op that returns the same id
  /// — a double-tapped Save must not race two child-diff writes.
  ///
  /// Also resets the provider: the editor is left after a save, and without an
  /// explicit reset a lingering instance (auto-dispose only fires once the
  /// last listener is gone, which navigation timing can defer) hands the old
  /// draft to the next "New recipe" open. Invalidate-on-save guarantees a
  /// fresh open always rebuilds from scratch — but only while this notifier is
  /// still alive: after an auto-dispose mid-write, touching `ref` throws.
  Future<String> save() async {
    final recipe = _current.copyWith(
      title: _current.title.trim(),
      steps: _current.steps
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    if (_saving) return recipe.id;
    _saving = true;
    try {
      await ref.read(recipeRepositoryProvider).saveRecipe(recipe);
    } finally {
      _saving = false;
    }
    if (ref.mounted) ref.invalidateSelf();
    return recipe.id;
  }

  void _mapGroup(String groupId, IngredientGroup Function(IngredientGroup) f) =>
      _set(
        _current.copyWith(
          groups: [
            for (final g in _current.groups)
              if (g.id == groupId) f(g) else g,
          ],
        ),
      );

  void _mapItem(String itemId, LineItem Function(LineItem) f) => _set(
    _current.copyWith(
      groups: [
        for (final g in _current.groups)
          g.copyWith(
            items: [
              for (final i in g.items)
                if (i.id == itemId) f(i) else i,
            ],
          ),
      ],
    ),
  );
}
