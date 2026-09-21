/// The draft behind week mode: the recipe's lines as this week would cook them,
/// edited but not stored until Save.
///
/// The recipe is kept as loaded, and the diff is recomputed whole against it on
/// every read, so a line edited back to the recipe's value leaves nothing
/// behind.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../../core/week_shape.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/component_quantity_sheet.dart'
    show targetWithMeasure;
import '../data/planning_providers.dart';

part 'week_variant_view_models.g.dart';

const _uuid = Uuid();

/// The recipe as loaded, and the list week mode is editing.
class WeekVariant {
  const WeekVariant({required this.recipe, required this.lines});

  /// The recipe as loaded — the base every diff runs against.
  final Recipe recipe;

  /// Every recipe line in stored order (excluded ones included), then the lines
  /// this week adds.
  final List<WeekDraftLine> lines;

  /// The recipe's lines, flattened in group order.
  Iterable<LineItem> get base => [
    for (final group in recipe.groups) ...group.items,
  ];

  /// The override set this draft would store, recomputed on every read.
  List<LineOverride> get overrides =>
      diffLineOverrides(base: base, draft: lines);

  /// The recipe line [id] came from, or null for an added line.
  LineItem? baseOf(String id) => base.where((l) => l.id == id).firstOrNull;

  WeekVariant _withLines(List<WeekDraftLine> lines) =>
      WeekVariant(recipe: recipe, lines: lines);
}

/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's first
/// day as `YYYY-MM-DD`.
@riverpod
class WeekVariantDraft extends _$WeekVariantDraft {
  @override
  Future<WeekVariant> build(String recipeId, String weekKey) async {
    final recipe = await ref
        .read(recipeRepositoryProvider)
        .watchRecipe(recipeId)
        .first;
    if (recipe == null) {
      throw StateError('no recipe $recipeId to edit for the week');
    }
    final stored = await ref
        .read(weekVariantRepositoryProvider)
        .loadOverrides(DateTime.parse(weekKey), recipeId);
    final base = [for (final group in recipe.groups) ...group.items];
    return WeekVariant(recipe: recipe, lines: draftLines(base, stored));
  }

  WeekVariant get _current => state.requireValue;

  void _mapLine(String id, WeekDraftLine Function(WeekDraftLine) f) {
    state = AsyncData(
      _current._withLines([
        for (final entry in _current.lines)
          if (entry.line.id == id) f(entry) else entry,
      ]),
    );
  }

  void setQuantity(String id, double? quantity) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(quantity: quantity),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Quantifies the line in a plain unit, clearing any measure. A line is in a
  /// unit or a word, never both; the server refuses a row carrying both.
  void setUnit(String id, Unit unit) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(
        unit: unit,
        measureId: null,
        measure: null,
        recipeMeasureId: null,
      ),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Quantifies a component line in one of the target recipe's own words
  /// (ADR-0018), clearing the unit. [word] is the measure row where the caller
  /// has it, since a just-coined word is not yet on the line's target.
  void setRecipeMeasure(
    String id,
    String recipeMeasureId, {
    RecipeMeasure? word,
  }) => _mapLine(id, (e) {
    final target = e.line.subRecipe;
    return (
      line: e.line.copyWith(
        unit: null,
        measureId: null,
        measure: null,
        recipeMeasureId: recipeMeasureId,
        subRecipe: target == null || word == null
            ? target
            : targetWithMeasure(target, word),
      ),
      excluded: e.excluded,
      added: e.added,
    );
  });

  void setMeasure(String id, Measure measure) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(
        measureId: measure.id,
        measure: measure,
        unit: pieces,
        // An ingredient's word is not a recipe's.
        recipeMeasureId: null,
      ),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Ticks an optional line in for the week, or a counted line out; the diff
  /// reads it as an include or an exclusion.
  void setOptional(String id, {required bool optional}) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(optional: optional),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Swaps the line's ingredient for this week. The note is kept as written.
  void setIngredient(String id, Ingredient ingredient) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(
        ingredientId: ingredient.id,
        ingredientName: ingredient.canonicalName,
        subRecipeId: null,
        subRecipe: null,
      ),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Excludes a recipe line (it stays visible); removes a line this week added.
  void removeOrExclude(String id) {
    final entry = _current.lines.where((e) => e.line.id == id).firstOrNull;
    if (entry == null) return;
    if (entry.added) {
      state = AsyncData(
        _current._withLines([
          for (final e in _current.lines)
            if (e.line.id != id) e,
        ]),
      );
      return;
    }
    _mapLine(id, (e) => (line: e.line, excluded: true, added: false));
  }

  /// Adds a line for this week only. Its id is the override row's, so reopening
  /// lands on the same row.
  void addLine(
    Ingredient ingredient, {
    double? quantity,
    Unit? unit,
    Measure? measure,
  }) {
    final line = LineItem(
      id: _uuid.v4(),
      ingredientId: ingredient.id,
      ingredientName: ingredient.canonicalName,
      unit: measure != null ? pieces : (unit ?? ingredient.defaultUnit),
      quantity: quantity,
      measureId: measure?.id,
      measure: measure,
    );
    state = AsyncData(
      _current._withLines([
        ..._current.lines,
        (line: line, excluded: false, added: true),
      ]),
    );
  }

  /// Puts one line back to what the recipe says.
  void reset(String id) {
    final original = _current.baseOf(id);
    if (original == null) return;
    _mapLine(id, (_) => (line: original, excluded: false, added: false));
  }

  /// The whole variant back to the recipe. Save commits the clearing.
  void resetAll() {
    state = AsyncData(_current._withLines(draftLines(_current.base, const [])));
  }

  /// Writes the recomputed set. Returns true when it landed.
  Future<bool> save() async {
    final draft = _current;
    await ref
        .read(weekVariantRepositoryProvider)
        .saveOverrides(
          DateTime.parse(weekKey),
          recipeId,
          overrides: draft.overrides,
        );
    return true;
  }
}

/// The week key a date belongs to, for the door that opens week mode.
String weekQueryParam(DateTime weekStart) => isoDateOf(weekStart);
