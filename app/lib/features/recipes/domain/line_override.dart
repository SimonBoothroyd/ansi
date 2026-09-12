/// A recipe's lines, changed for ONE planned week — PURE DART (invariant 2).
///
/// The variant is a set of **deltas** against the recipe, not a copy of it: a
/// swap, an amount, an addition, an exclusion, an optional line ticked back
/// in. One set per `(week, recipe)`, so every day that plans the recipe that
/// week cooks the same lines and the cook plan still batches them into one
/// pot.
///
/// Two things live here: the delta itself ([LineOverride]) and the function
/// that computes a whole set from what somebody edited ([diffLineOverrides]).
/// Applying a set is the `effectiveLines` seam's job — the ONE place a rule
/// about which lines count is written, so the shop and the week's macros
/// cannot disagree about what this week cooks.
///
/// **Amounts are absolute.** A replace carries the quantity, unit, measure,
/// note and target it is cooked at, not a factor against the recipe — so the
/// recipe moving 400 g to 500 g next month leaves this week at the 400 g
/// somebody asked for.
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
  /// Keep a line the recipe marks `optional`. Without it the seam drops the
  /// line, which is the rule this action exists to suspend for one week.
  include,

  /// Leave a recipe line out this week. The line is still SHOWN in week mode,
  /// struck through, because somebody opening the week next has to be able to
  /// see what is missing and put it back.
  exclude,

  /// Cook the line with these absolute values instead of the recipe's.
  replace,

  /// A line the recipe has not got. It carries no recipe line behind it, so
  /// its control is *remove* rather than *reset*.
  add,
}

/// One delta against a recipe line for one week (`week_recipe_line_override`).
@freezed
abstract class LineOverride with _$LineOverride {
  const LineOverride._();

  const factory LineOverride({
    required LineOverrideAction action,

    /// The row's id. Empty on an override [diffLineOverrides] has just
    /// computed for a RECIPE line: which row it lands on is the repository's
    /// business, since a line may already have one standing. An `add` carries
    /// its own id from the moment it is drafted — the drafted line and the row
    /// that stores it are the same thing.
    @Default('') String id,

    /// The recipe line this is about; null exactly on [LineOverrideAction.add]
    /// (the server's `week_recipe_line_override_action_shape`).
    String? recipeLineItemId,
    String? ingredientId,

    /// Denormalised for display, exactly as `plan_entry.recipe_title` is: the
    /// week's lines are read without a join back to the vocabulary.
    @Default('') String ingredientName,

    /// Ships as a column only in v1: the week rules on WHICH lines it cooks,
    /// not on what they point at, so a sub-recipe swap for one week has no
    /// door. A replace on a component line carries the line's own target back
    /// unchanged.
    String? subRecipeId,
    double? quantity,
    Unit? unit,
    String? measureId,
    Measure? measure,
    String? note,
    int? sortOrder,
  }) = _LineOverride;

  /// Whether this row carries values of its own — a `replace` or an `add`.
  /// `include` and `exclude` are statements about a line and carry nothing.
  bool get carriesValues =>
      action == LineOverrideAction.replace || action == LineOverrideAction.add;
}

/// One line as week mode is holding it, mid-edit.
///
/// A line the recipe owns keeps its own id, so the diff can find the line it
/// is about. An `added` line's id is the override row's id from the start.
/// `excluded` is the bin's answer on a recipe line — the row stays on screen.
typedef WeekDraftLine = ({LineItem line, bool excluded, bool added});

/// The whole override set for `(week, recipe)`, computed from scratch against
/// [base] — the recipe's lines as they were loaded when week mode opened.
///
/// Recomputing rather than accumulating is what stops no-ops piling up: a line
/// edited and then edited back to the recipe's own value produces **no row at
/// all**, so the count the footer states and the tags the list draws can never
/// describe a change nobody made.
///
/// The rules:
///
/// * a draft line whose ingredient / quantity / unit / measure / note differs
///   from its base → one [LineOverrideAction.replace] carrying all of them,
///   absolute;
/// * a draft line with no base behind it → [LineOverrideAction.add];
/// * a base line the draft excluded, or one the draft marked `optional` that
///   the recipe counts → [LineOverrideAction.exclude]. The amount sheet's
///   Optional switch is the same control the bin is, from the other side: this
///   week drops the line either way, so it stores one action rather than two
///   that would have to mean the same thing;
/// * a base line the recipe marks `optional` that the draft keeps →
///   [LineOverrideAction.include];
/// * anything else → no row.
///
/// Reorder and regrouping are ignored: not storable in v1, and therefore not
/// offered (week mode draws no grip).
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
          note: _trimmed(line.note),
          sortOrder: added++,
        ),
      );
      continue;
    }
    final original = byId[line.id];
    // A base line the recipe no longer has — a soft delete that landed while
    // the draft was open. There is nothing for an override to be about.
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

  // A base line the draft dropped entirely is an exclusion: week mode keeps
  // every recipe line on screen, so this is the other phone's edit arriving
  // mid-draft rather than a gesture — and an override that silently vanished
  // would be a hole nobody could see.
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

/// Whether [edited] states a different thing to cook, or a different amount of
/// it, than [original] — the five fields a `replace` carries.
///
/// The `optional` flag is deliberately NOT one of them: it is an exclusion or
/// an inclusion, never a replacement.
bool _differs(LineItem original, LineItem edited) =>
    original.ingredientId != edited.ingredientId ||
    original.subRecipeId != edited.subRecipeId ||
    original.quantity != edited.quantity ||
    original.unit != edited.unit ||
    original.measureId != edited.measureId ||
    _trimmed(original.note) != _trimmed(edited.note);

String? _trimmed(String? note) {
  final text = note?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// [line] as this week cooks it — absolute values, all of them, and `optional`
/// cleared because a line somebody edited this week is a line they want. That
/// clearing is what lets the seam run twice without the recipe's own rule
/// firing over the week's answer.
LineItem applyOverride(LineItem line, LineOverride override) => line.copyWith(
  ingredientId: override.ingredientId,
  ingredientName: override.ingredientName.isEmpty
      ? line.ingredientName
      : override.ingredientName,
  subRecipeId: override.subRecipeId,
  subRecipe: override.subRecipeId == null ? null : line.subRecipe,
  quantity: override.quantity,
  unit: override.unit ?? line.unit,
  measureId: override.measureId,
  measure: override.measure,
  note: override.note,
  optional: false,
  // A swap onto a DIFFERENT row is a repair, so the base line's broken-link
  // flag does not ride along: the override's ingredient is read with the
  // liveness guard, so the row this now names is a live one. An amount-only
  // replace re-points nothing and keeps whatever the line already said.
  ingredientDeleted:
      line.ingredientDeleted &&
      (override.ingredientId == null ||
          override.ingredientId == line.ingredientId),
);

/// An added line as a [LineItem], so every derivation downstream reads one
/// shape. Its id is the override row's, which is what lets the editor reopen
/// on it and the next save land on the same row.
LineItem addedLine(LineOverride override) => LineItem(
  id: override.id,
  ingredientName: override.ingredientName,
  unit: override.unit ?? pieces,
  ingredientId: override.ingredientId,
  subRecipeId: override.subRecipeId,
  quantity: override.quantity,
  measureId: override.measureId,
  measure: override.measure,
  note: override.note,
);

/// [base] as week mode draws it: every recipe line still on the list — an
/// excluded one struck rather than gone, because somebody opening this next
/// has to see what is missing and be able to put it back — then the additions.
///
/// The exact inverse of [diffLineOverrides]: draft these lines, change
/// nothing, and the diff gives [overrides] back.
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

/// What an override did to its line, as the kind of change it is.
///
/// One classification, two vocabularies: the editor's tag ("this week · was
/// 400 g Pork sausage") and the shopping list's provenance segment ("· this
/// week, for Pork sausage") both read this, so the words a shopper sees and
/// the words the editor showed cannot describe different changes.
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

/// The [WeekChange] [ov] describes, against the recipe line it is about
/// ([base], null for an addition).
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

/// The editor's tag on one changed line — the recipe's own words quoted back,
/// so the reader can undo the change in their head before undoing it with the
/// button.
///
/// The ingredient is named exactly as the app stores it: a display name is
/// never rewritten to fit a sentence.
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

/// The shopping list's extra provenance segment — "Ragù · cook Tue · this
/// week, for Pork sausage". The same four changes the editor's tags name, in
/// the voice a provenance line speaks, so a shopper and an editor cannot
/// describe one change two ways.
///
/// An exclusion is NOT one of these: there is no row left to hang a segment
/// on, so it takes the echo row the list already prints for a dropped line.
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
