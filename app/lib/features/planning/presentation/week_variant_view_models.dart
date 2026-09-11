/// The draft behind week mode: the recipe's lines as this week would cook
/// them, edited but not yet stored.
///
/// It keeps the recipe EXACTLY as loaded beside the edited list, because the
/// diff is computed against that original on every save and on every keystroke
/// the footer counts — recomputed whole, never accumulated, so a line edited
/// back to the recipe's value leaves nothing behind.
///
/// Nothing here writes. The editor's own **Save** does, which is the recipe
/// editor's posture rather than the meal sheet's write-through: a variant is
/// several decisions that only make sense together.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/line_override.dart';
import '../../recipes/domain/recipe.dart';
import '../data/planning_providers.dart';
import '../domain/planning.dart' show weekKeyOf;

part 'week_variant_view_models.g.dart';

const _uuid = Uuid();

/// The recipe as loaded, and the list week mode is editing.
class WeekVariant {
  const WeekVariant({required this.recipe, required this.lines});

  /// The recipe's own lines and groups, untouched — the base every diff runs
  /// against, and the words the tags quote back ("was 400 g Pork sausage").
  final Recipe recipe;

  /// Every recipe line in stored order, an excluded one still among them, then
  /// the lines this week adds.
  final List<WeekDraftLine> lines;

  /// The recipe's lines, flattened in group order.
  Iterable<LineItem> get base => [
    for (final group in recipe.groups) ...group.items,
  ];

  /// The override set this draft would store. Recomputed on every read — it is
  /// a pure function of the draft, and the footer's count and the save's rows
  /// must be the same answer.
  List<LineOverride> get overrides =>
      diffLineOverrides(base: base, draft: lines);

  /// The recipe line [id] came from, or null for an added line.
  LineItem? baseOf(String id) =>
      base.where((l) => l.id == id).firstOrNull;

  WeekVariant _withLines(List<WeekDraftLine> lines) =>
      WeekVariant(recipe: recipe, lines: lines);
}

/// Week mode's draft for one `(recipe, week)`. [weekKey] is the week's Monday
/// as `YYYY-MM-DD` — the query param the door opens the editor with.
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

  void setUnit(String id, Unit unit) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(unit: unit, measureId: null, measure: null),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  void setMeasure(String id, Measure measure) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(
        measureId: measure.id,
        measure: measure,
        unit: pieces,
      ),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// Ticking an optional line IN for the week, or a counted line OUT of it —
  /// the amount sheet's own switch, which the diff reads as an include or an
  /// exclusion (there is no third thing it could mean this week).
  void setOptional(String id, {required bool optional}) => _mapLine(
    id,
    (e) => (
      line: e.line.copyWith(optional: optional),
      excluded: e.excluded,
      added: e.added,
    ),
  );

  /// The line cooks something else this week. The note travels with it, as the
  /// recipe editor's own substitution does — never rewritten for you.
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

  /// The bin. On a RECIPE line it excludes — this screen cannot delete the
  /// recipe's line, and a row that vanished would be a hole nobody could see.
  /// On an added line it removes: there is nothing to go back to.
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

  /// A line added for this week only. Its id is the override row's from here
  /// on, so reopening the week lands on the same row rather than a new one.
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

  /// One line back to what the recipe says. Muted, no confirm — it is a draft
  /// action, and Save is still what stores it.
  void reset(String id) {
    final original = _current.baseOf(id);
    if (original == null) return;
    _mapLine(id, (_) => (line: original, excluded: false, added: false));
  }

  /// The whole variant back to the recipe. Save commits the clearing.
  void resetAll() {
    state = AsyncData(
      _current._withLines(draftLines(_current.base, const [])),
    );
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
String weekQueryParam(DateTime weekStart) => weekKeyOf(weekStart);
