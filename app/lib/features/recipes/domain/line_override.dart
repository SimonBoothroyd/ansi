/// A recipe's lines, changed for one planned week. Pure Dart.
///
/// A variant is a set of deltas against the recipe ([LineOverride]), one set
/// per `(week, recipe)`, computed whole by [diffLineOverrides] and applied by
/// the `effectiveLines` seam. Values are absolute, not factors: the recipe
/// changing later leaves this week's amount alone.
library;

// Freezed needs the private `._` constructor before the factory (for the
// custom getter), which trips the unnamed-first sort lint.
// ignore_for_file: sort_unnamed_constructors_first
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import 'line_display.dart';
import 'recipe.dart';

part 'line_override.freezed.dart';

/// What one override does to the recipe's line.
enum LineOverrideAction {
  /// Keep a line the recipe marks `optional`, which the seam would otherwise
  /// drop.
  include,

  /// Leave a recipe line out this week. Week mode still shows it, struck, so it
  /// can be put back.
  exclude,

  /// Cook the line with these absolute values instead of the recipe's.
  replace,

  /// A line the recipe does not have. Its control is remove, not reset.
  add,
}

/// One delta against a recipe line for one week (`week_recipe_line_override`).
@freezed
abstract class LineOverride with _$LineOverride {
  const LineOverride._();

  const factory LineOverride({
    required LineOverrideAction action,

    /// The row's id. Empty on an override [diffLineOverrides] computed for a
    /// recipe line; the repository decides which row it lands on. An `add`
    /// carries its id from the moment it is drafted.
    @Default('') String id,

    /// The recipe line this is about; null exactly on [LineOverrideAction.add]
    /// (the server's `week_recipe_line_override_action_shape`).
    String? recipeLineItemId,
    String? ingredientId,

    /// Denormalised for display, so the week's lines need no join to the
    /// vocabulary.
    @Default('') String ingredientName,

    /// Carried through unchanged: a week cannot swap a sub-recipe, so a replace
    /// on a component line keeps the line's own target.
    String? subRecipeId,
    double? quantity,
    Unit? unit,
    String? measureId,
    Measure? measure,

    /// The target recipe's measure a component line is cooked in this week. A
    /// pointer at the word, so re-weighing the word moves this week's share
    /// with it.
    String? recipeMeasureId,
    String? note,
    int? sortOrder,
  }) = _LineOverride;

  /// Whether this row carries values of its own: a `replace` or an `add`.
  bool get carriesValues =>
      action == LineOverrideAction.replace || action == LineOverrideAction.add;
}

/// One line as week mode holds it, mid-edit. A recipe line keeps its own id; an
/// `added` line's id is the override row's. `excluded` lines stay on screen.
typedef WeekDraftLine = ({LineItem line, bool excluded, bool added});

/// The whole override set for `(week, recipe)`, computed from scratch against
/// [base] (the recipe's lines as loaded), so an edit reverted to the recipe's
/// value produces no row.
///
/// A changed line is one absolute [LineOverrideAction.replace]; a line with no
/// base an `add`; a base line excluded, or marked optional where the recipe
/// counts it, an `exclude`; a kept optional base line an `include`. Reorder and
/// regrouping are ignored.
List<LineOverride> diffLineOverrides({
  required Iterable<LineItem> base,
  required Iterable<WeekDraftLine> draft,
}) {
  final byId = {for (final line in base) line.id: line};
  final seen = <String>{};
  final overrides = <LineOverride>[];
  var added = 0;

  for (final entry in draft) {
    final line = entry.line;
    if (entry.added) {
      overrides.add(
        LineOverride(
          id: line.id,
          action: LineOverrideAction.add,
          ingredientId: line.ingredientId,
          ingredientName: line.ingredientName,
          subRecipeId: line.subRecipeId,
          quantity: line.quantity,
          unit: line.unit,
          measureId: line.measureId,
          measure: line.measure,
          recipeMeasureId: line.recipeMeasureId,
          note: _trimmed(line.note),
          sortOrder: added++,
        ),
      );
      continue;
    }
    final original = byId[line.id];
    // The recipe soft-deleted this line while the draft was open; nothing to
    // override.
    if (original == null) continue;
    seen.add(line.id);

    if (entry.excluded || (line.optional && !original.optional)) {
      overrides.add(
        LineOverride(
          action: LineOverrideAction.exclude,
          recipeLineItemId: line.id,
        ),
      );
      continue;
    }
    if (_differs(original, line)) {
      overrides.add(
        LineOverride(
          action: LineOverrideAction.replace,
          recipeLineItemId: line.id,
          ingredientId: line.ingredientId,
          ingredientName: line.ingredientName,
          subRecipeId: line.subRecipeId,
          quantity: line.quantity,
          unit: line.unit,
          measureId: line.measureId,
          measure: line.measure,
          recipeMeasureId: line.recipeMeasureId,
          note: _trimmed(line.note),
        ),
      );
      continue;
    }
    if (original.optional && !line.optional) {
      overrides.add(
        LineOverride(
          action: LineOverrideAction.include,
          recipeLineItemId: line.id,
        ),
      );
    }
  }

  // A base line missing from the draft (a remote edit arriving mid-draft) is an
  // exclusion, so it stays visible.
  for (final line in base) {
    if (!seen.contains(line.id)) {
      overrides.add(
        LineOverride(
          action: LineOverrideAction.exclude,
          recipeLineItemId: line.id,
        ),
      );
    }
  }
  return overrides;
}

/// Whether [edited] differs from [original] in a field a `replace` carries.
/// `optional` is not one: it is an exclusion or inclusion.
bool _differs(LineItem original, LineItem edited) =>
    original.ingredientId != edited.ingredientId ||
    original.subRecipeId != edited.subRecipeId ||
    original.quantity != edited.quantity ||
    original.unit != edited.unit ||
    original.measureId != edited.measureId ||
    original.recipeMeasureId != edited.recipeMeasureId ||
    _trimmed(original.note) != _trimmed(edited.note);

String? _trimmed(String? note) {
  final text = note?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// [line] as this week cooks it: absolute values, with `optional` cleared so
/// the seam can run again without dropping a line the week edited.
LineItem applyOverride(LineItem line, LineOverride override) => line.copyWith(
  ingredientId: override.ingredientId,
  ingredientName: override.ingredientName.isEmpty
      ? line.ingredientName
      : override.ingredientName,
  subRecipeId: override.subRecipeId,
  subRecipe: override.subRecipeId == null ? null : line.subRecipe,
  quantity: override.quantity,
  // A line is in a unit or a word, never both; the override's choice clears the
  // other.
  unit: override.recipeMeasureId != null ? null : (override.unit ?? line.unit),
  measureId: override.measureId,
  measure: override.measure,
  recipeMeasureId: override.recipeMeasureId,
  note: override.note,
  optional: false,
  // A swap onto a different row is a repair, so the broken-link flag is
  // cleared; an amount-only replace keeps it.
  ingredientDeleted:
      line.ingredientDeleted &&
      (override.ingredientId == null ||
          override.ingredientId == line.ingredientId),
);

/// An added line as a [LineItem]. Its id is the override row's, so the editor
/// reopens on it and the next save lands on the same row.
LineItem addedLine(LineOverride override) => LineItem(
  id: override.id,
  ingredientName: override.ingredientName,
  // A row naming a recipe measure has no unit; one naming neither is malformed
  // and falls back to a bare count.
  unit: override.recipeMeasureId != null ? null : (override.unit ?? pieces),
  ingredientId: override.ingredientId,
  subRecipeId: override.subRecipeId,
  quantity: override.quantity,
  measureId: override.measureId,
  measure: override.measure,
  recipeMeasureId: override.recipeMeasureId,
  note: override.note,
);

/// [base] as week mode draws it: every recipe line (excluded ones struck, not
/// gone), then the additions. The inverse of [diffLineOverrides].
List<WeekDraftLine> draftLines(
  Iterable<LineItem> base,
  List<LineOverride> overrides,
) {
  final byLine = <String, LineOverride>{
    for (final o in overrides)
      if (o.recipeLineItemId != null) o.recipeLineItemId!: o,
  };
  return [
    for (final line in base)
      switch (byLine[line.id]?.action) {
        LineOverrideAction.exclude => (
          line: line,
          excluded: true,
          added: false,
        ),
        LineOverrideAction.replace => (
          line: applyOverride(line, byLine[line.id]!),
          excluded: false,
          added: false,
        ),
        LineOverrideAction.include => (
          line: line.copyWith(optional: false),
          excluded: false,
          added: false,
        ),
        LineOverrideAction.add ||
        null => (line: line, excluded: false, added: false),
      },
    for (final o in overrides)
      if (o.action == LineOverrideAction.add)
        (line: addedLine(o), excluded: false, added: true),
  ];
}

/// What an override did to its line. Both the editor's tag and the shopping
/// list's provenance segment read this one classification.
enum WeekChange {
  /// The line cooks something else this week.
  swapped,

  /// The same thing, a different amount (or a different note).
  amount,

  /// A line the recipe has not got.
  added,

  /// A recipe line left out this week.
  leftOut,

  /// An optional line the recipe would have dropped, ticked in.
  included,
}

/// The [WeekChange] [ov] describes against its recipe line ([base], null for an
/// addition).
WeekChange weekChangeOf(LineOverride ov, LineItem? base) => switch (ov.action) {
  LineOverrideAction.add => WeekChange.added,
  LineOverrideAction.exclude => WeekChange.leftOut,
  LineOverrideAction.include => WeekChange.included,
  LineOverrideAction.replace =>
    base != null &&
            (base.ingredientId != ov.ingredientId ||
                base.subRecipeId != ov.subRecipeId)
        ? WeekChange.swapped
        : WeekChange.amount,
};

/// The editor's tag on a changed line, quoting the recipe's own words ("this
/// week · was 400 g Pork sausage"). The ingredient's display name is never
/// rewritten.
String weekTagText(WeekChange change, LineItem? base) => switch (change) {
  WeekChange.swapped when base != null =>
    'this week · was ${amountOfLine(base)} ${base.ingredientName}',
  WeekChange.amount when base != null =>
    'this week · was ${amountOfLine(base)}',
  WeekChange.swapped || WeekChange.amount => 'this week · changed',
  WeekChange.added => 'this week · added',
  WeekChange.leftOut => 'this week · left out',
  WeekChange.included => 'this week · included',
};

/// The shopping list's provenance segment: "· this week, for Pork sausage". An
/// exclusion has none; it takes the list's echo row for a dropped line.
String? weekProvenanceSegment(WeekChange change, LineItem? base) =>
    switch (change) {
      WeekChange.swapped when base != null =>
        'this week, for ${base.ingredientName}',
      WeekChange.amount when base != null =>
        'this week, was ${amountOfLine(base)}',
      WeekChange.swapped || WeekChange.amount => 'this week, changed',
      WeekChange.added => 'this week, added',
      WeekChange.included => 'this week, ticked in',
      WeekChange.leftOut => null,
    };
