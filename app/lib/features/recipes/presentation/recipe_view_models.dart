/// Riverpod ViewModels for the recipes UI: thin read streams off the
/// repository, and the [RecipeEditor] notifier holding the in-progress
/// aggregate.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../data/recipe_providers.dart';
import '../domain/component_math.dart';
import '../domain/line_reorder.dart';
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_cost.dart';
import '../domain/recipe_header_edits.dart';
import '../domain/recipe_measure_authoring.dart';
import '../domain/recipe_repository.dart';
import 'component_quantity_sheet.dart' show targetWithMeasure;
import 'method_editing.dart';
import 'recipe_header_form.dart';

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

/// The recipes that list [id] as a component: the "Used in · N" rows and the
/// count the delete refusal speaks. Re-reads whenever the recipe changes.
@riverpod
Future<List<RecipeUse>> recipeUsedIn(Ref ref, String id) {
  ref.watch(recipeByIdProvider(id));
  return ref.watch(recipeRepositoryProvider).usedIn(id);
}

/// Every recipe's cost, keyed by recipe id (ADR-0017). A separate stream from
/// [recipeList]: a cost moves when a receipt lands, and money stays apart from
/// macros.
@riverpod
Stream<Map<String, RecipeCostSummary>> recipeCosts(Ref ref) =>
    ref.watch(recipeRepositoryProvider).watchRecipeCosts();

/// Whether the recipe page prints each ingredient line's own figures under its
/// name.
///
/// A reading posture, neither stored nor synced: keep-alive so it survives
/// moving between recipes, reset with the app. Which figures print is
/// [CostReading]'s answer.
@Riverpod(keepAlive: true)
class ShowLineFigures extends _$ShowLineFigures {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Whether the recipe panel reads cost rather than macros. A session posture
/// held like [ShowLineFigures].
@Riverpod(keepAlive: true)
class CostReading extends _$CostReading {
  @override
  bool build() => false;

  /// A verb rather than a setter so the call site names the reading it asks
  /// for.
  // ignore: use_setters_to_change_properties
  void show({required bool cost}) => state = cost;
}

/// Resolves the vocab [Ingredient] behind an editor line item so its units can
/// be filtered by [allowedUnitsFor]. The repository only exposes search
/// (ADR-0004), so this searches by name and matches on id; null when
/// unresolved.
@riverpod
Future<Ingredient?> lineItemIngredient(
  Ref ref, {
  required String ingredientId,
  required String name,
}) async {
  final matches = await ref
      .watch(ingredientRepositoryProvider)
      .search(name, limit: 10);
  for (final m in matches.rows) {
    if (m.id == ingredientId) return m;
  }
  return null;
}

/// Editable recipe state. `build` loads an existing recipe or starts a blank
/// one with a fresh id and one empty group.
///
/// [initialTitle], [initialBookId] and [initialSectionId] seed a new draft from
/// the route (`/recipes/new?title=…&book=…&section=…`) and are part of the
/// family key. Implements [MethodEditing] and [RecipeHeaderHost], the surfaces
/// the step cards and header form also host on at import review.
@riverpod
class RecipeEditor extends _$RecipeEditor
    implements MethodEditing, RecipeHeaderHost {
  @override
  Future<Recipe> build(
    String? recipeId, {
    String? initialTitle,
    String? initialBookId,
    String? initialSectionId,
  }) async {
    if (recipeId != null) {
      final existing = await ref
          .read(recipeRepositoryProvider)
          .watchRecipe(recipeId)
          .first;
      if (existing != null) {
        _yieldsAsOpened = existing.yields;
        return _tokenized(existing);
      }
    }
    // A new recipe is filed from the start: the section door's shelf, otherwise
    // the default book, unsectioned.
    final bookId =
        initialBookId ??
        (await ref.read(bookRepositoryProvider).ensureDefaultBook()).id;
    return Recipe(
      id: _uuid.v4(),
      title: initialTitle?.trim() ?? '',
      servingsBase: 2,
      bookId: bookId,
      sectionId: initialSectionId,
      groups: [IngredientGroup(id: _uuid.v4())],
      methodSteps: const [],
    );
  }

  /// A recipe with legacy plain [Recipe.steps] becomes one text token per line,
  /// so every reader sees one method shape. Nothing is re-tokenized or
  /// re-matched.
  Recipe _tokenized(Recipe recipe) => recipe.methodSteps != null
      ? recipe
      : recipe.copyWith(methodSteps: methodFromPlainSteps(recipe.steps));

  Recipe get _current => state.requireValue;
  void _set(Recipe r) => state = AsyncData(r);

  /// Editor-session step ids, index-aligned with `methodSteps`. Never
  /// persisted; see [stableStepKey].
  List<String> _stepIds = const [];

  /// True while a [save] is in flight. A double-tapped Save would otherwise run
  /// the child-diff write twice concurrently.
  bool _saving = false;

  /// What the recipe said a batch makes when this editor opened, for the orphan
  /// question (ADR-0018 rule 4). Empty for a new recipe.
  List<YieldDenomination> _yieldsAsOpened = const [];

  /// The live words this Save would orphan: those the recipe can hold now but
  /// not once it says what the draft says. Usually empty. Warns, never refuses.
  List<RecipeMeasure> measuresOrphanedBySave() => recipeMeasuresOrphanedBy(
    measures: _current.measures,
    from: _yieldsAsOpened,
    to: _current.yields,
  );

  // --- the header ---------------------------------------------------
  //
  // Every rule lives in `RecipeHeaderEdits`, shared with the import review's
  // host; these only seat the result.

  @override
  Recipe get header => _current;

  @override
  void setTitle(String title) => _set(_current.copyWith(title: title));

  @override
  void setServings(double servings) => _set(_current.withServings(servings));

  @override
  void setYield(double? qty, Unit? unit) => _set(_current.withYield(qty, unit));

  @override
  void setSecondYield(double? qty, Unit? unit) =>
      _set(_current.withSecondYield(qty, unit));

  @override
  void setMeasures(List<RecipeMeasure> measures) =>
      _set(_current.withMeasures(measures));

  @override
  void setCookTime(int? seconds) => _set(_current.withCookTime(seconds));

  @override
  void setTotalTime(int? seconds) => _set(_current.withTotalTime(seconds));

  @override
  void setKeepsForDays(int? days) => _set(_current.withKeepsForDays(days));

  @override
  void setFreezable(bool freezable) => _set(_current.withFreezable(freezable));

  @override
  void setFreezerDays(int? days) => _set(_current.withFreezerDays(days));

  @override
  void setBook(String bookId) => _set(_current.withBook(bookId));

  @override
  void setSection(String? sectionId) => _set(_current.withSection(sectionId));

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

  /// Appends a line for [ingredient] with the quantity sheet's [choice], or in
  /// the ingredient's default unit without one.
  @override
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
            RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
              measure,
            ),
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

  /// Appends a component line pointing at [target]: no ingredient id or
  /// ingredient measure, and a `batch` default.
  ///
  /// [recipeMeasureId] is one of the target's own words (ADR-0018) and takes
  /// the unit's place. [recipeMeasure] is that word's row where the caller has
  /// it; a word just coined is not yet in [target] (see [targetWithMeasure]).
  @override
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
    String? recipeMeasureId,
    RecipeMeasure? recipeMeasure,
    bool optional = false,
  }) => _mapGroup(
    groupId,
    (g) => g.copyWith(
      items: [
        ...g.items,
        LineItem(
          id: _uuid.v4(),
          subRecipeId: target.id,
          subRecipe: recipeMeasure == null
              ? target
              : targetWithMeasure(target, recipeMeasure),
          ingredientName: target.title,
          quantity: quantity,
          unit: recipeMeasureId != null ? null : (unit ?? batches),
          recipeMeasureId: recipeMeasureId,
          optional: optional,
        ),
      ],
    ),
  );

  /// Moves the ingredient line at flat row [from] to row [to]; the rule is in
  /// `line_reorder.dart`. The line object is carried across, so its id and
  /// method chips survive. A group left empty is kept.
  void moveLine(int from, int to) {
    final items = moveLineRow(
      [for (final g in _current.groups) g.items],
      from: from,
      to: to,
    );
    _set(
      _current.copyWith(
        groups: [
          for (final (i, g) in _current.groups.indexed)
            g.copyWith(items: items[i]),
        ],
      ),
    );
  }

  void setLineItemQuantity(String itemId, double? quantity) =>
      _mapItem(itemId, (i) => i.copyWith(quantity: quantity));

  /// Quantifies the line in a plain unit, clearing any ingredient or recipe
  /// measure. A line is said in a unit or a word, never both; the database
  /// refuses a row with both, and a refused upload drops the whole crud
  /// transaction.
  void setLineItemUnit(String itemId, Unit unit) => _mapItem(
    itemId,
    (i) => i.copyWith(
      unit: unit,
      measureId: null,
      measure: null,
      recipeMeasureId: null,
    ),
  );

  /// Quantifies a component line in one of the target recipe's own words
  /// (ADR-0018), clearing the unit. [word] is the row behind the pointer where
  /// the caller has it ([targetWithMeasure]).
  void setLineItemRecipeMeasure(
    String itemId,
    String recipeMeasureId, {
    RecipeMeasure? word,
  }) => _mapItem(itemId, (i) {
    final target = i.subRecipe;
    return i.copyWith(
      unit: null,
      measureId: null,
      measure: null,
      recipeMeasureId: recipeMeasureId,
      subRecipe: target == null || word == null
          ? target
          : targetWithMeasure(target, word),
    );
  });

  /// Quantifies the line in a named [measure] ("2 × potato, large"). The
  /// stored unit becomes the count fallback (`pieces`) — see [LineItem].
  void setLineItemMeasure(String itemId, Measure measure) => _mapItem(
    itemId,
    (i) => i.copyWith(
      unit: pieces,
      measureId: measure.id,
      measure: measure,
      // The same XOR from the other side: an ingredient's word is not a
      // recipe's, and one line cannot be counted in both.
      recipeMeasureId: null,
    ),
  );

  /// Sets the line's note; blank clears it. Goes through [_mapItem], never
  /// [_setIdentity], so no method chip is relabelled.
  void setLineItemNote(String itemId, String? note) {
    final text = note?.trim() ?? '';
    _mapItem(itemId, (i) => i.copyWith(note: text.isEmpty ? null : text));
  }

  /// Marks the line optional or not. Quantity and unit are untouched.
  void setLineItemOptional(String itemId, {required bool optional}) =>
      _mapItem(itemId, (i) => i.copyWith(optional: optional));

  /// Re-points a line at another ingredient, keeping the line's id.
  ///
  /// The id makes `saveRecipe`'s child diff issue an UPDATE rather than delete
  /// + INSERT, and keeps every chip that references the line pointing at it.
  /// The ingredient measure is cleared with the old ingredient.
  void setLineItemIngredient(String itemId, Ingredient ingredient) =>
      _setIdentity(
        itemId,
        name: ingredient.canonicalName,
        item: (i) => i.copyWith(
          ingredientId: ingredient.id,
          subRecipeId: null,
          subRecipe: null,
          ingredientName: ingredient.canonicalName,
          measureId: null,
          measure: null,
          // The picker only offers live rows, so a re-point clears the removed
          // tag at once.
          ingredientDeleted: false,
          // A re-point onto an ingredient drops any recipe measure with it:
          // `blob` is a word for a recipe, and this line no longer names one.
          recipeMeasureId: null,
          unit: i.unit?.family == ingredient.defaultUnit.family
              ? i.unit
              : ingredient.defaultUnit,
        ),
      );

  /// The component half of [setLineItemIngredient] — the line becomes a
  /// sub-recipe reference, under the same identity XOR.
  void setLineItemSubRecipe(String itemId, SubRecipeTarget target) =>
      _setIdentity(
        itemId,
        name: target.title,
        item: (i) => i.copyWith(
          ingredientId: null,
          subRecipeId: target.id,
          subRecipe: target,
          ingredientName: target.title,
          measureId: null,
          measure: null,
          ingredientDeleted: false,
          // The new target's words are not this line's old ones, so the
          // pointer goes and the line falls back to whole batches.
          recipeMeasureId: null,
          unit: i.unit?.family == UnitFamily.batch ? i.unit : batches,
        ),
      );

  void _setIdentity(
    String itemId, {
    required String name,
    required LineItem Function(LineItem) item,
  }) {
    final before = lineById()[itemId];
    if (before == null) return;
    _mapItem(itemId, item);
    // A substitution fires only on an identity change, never on a quantity,
    // unit, measure or note edit. Re-picking the same ingredient is a no-op.
    if (before.ingredientName == name) return;
    final relabelled = relabelRefs(methodDraft(), lineId: itemId, label: name);
    if (relabelled.relabels.isEmpty) return;
    _setMethod(relabelled.steps);
    _relabels
      ..removeWhere(
        (r) => relabelled.relabels.any(
          (n) => n.stepId == r.stepId && n.spanIndex == r.spanIndex,
        ),
      )
      ..addAll(relabelled.relabels);
    _substitution = (
      oldName: before.ingredientName,
      newName: name,
      stepIds: {for (final r in relabelled.relabels) r.stepId},
    );
  }

  /// The substitution being read through this sitting, or null. Session state;
  /// a save clears it.
  @override
  Substitution? substitution() => _substitution;
  Substitution? _substitution;

  /// Each relabelled chip's previous word, so "keep the old word" is one tap.
  /// Same session lifetime as [substitution].
  @override
  List<ChipRelabel> relabels() => List.unmodifiable(_relabels);
  final List<ChipRelabel> _relabels = [];

  /// Reverts a relabel: the chip keeps its ref and takes its printed word back.
  @override
  void keepOldWord(ChipRelabel relabel) {
    renameChip(relabel.stepId, relabel.spanIndex, relabel.oldWord);
    _relabels.remove(relabel);
    if (_relabels.isEmpty) _substitution = null;
  }

  /// The step indexes whose chips point at [itemId] — the *"used in 2 steps"*
  /// line, and the count the removal prompt speaks.
  int stepsUsing(String itemId) =>
      stepsMentioning(methodDraft(), itemId).length;

  /// Removes a line. Chips pointing at it become plain words, so the sentence
  /// survives and only the link dies — and `save`'s prune would do it anyway.
  void removeLineItem(String itemId) {
    var steps = methodDraft();
    for (final index in stepsMentioning(steps, itemId)) {
      final step = steps[index];
      for (var i = step.spans.length - 1; i >= 0; i--) {
        final span = step.spans[i];
        if (span is RefSpan && span.refs.contains(itemId)) {
          steps = [...steps]..[index] = removeSpan(steps[index], i);
        }
      }
    }
    _setMethod(steps);
    _set(
      _current.copyWith(
        groups: [
          for (final g in _current.groups)
            g.copyWith(items: g.items.where((i) => i.id != itemId).toList()),
        ],
      ),
    );
  }

  // --- the method -------------------------------------------------------

  /// Every line of this recipe by id — what the fold derives a chip's live
  /// amount from, and what the line picker offers.
  @override
  Map<String, LineItem> lineById() => {
    for (final group in _current.groups)
      for (final item in group.items) item.id: item,
  };

  /// The method as the editor holds it: one sentence per step, with the ranges
  /// that are chips. Derived from the tokens, so there is one source of truth.
  @override
  List<MethodDraftStep> methodDraft() {
    final steps = _current.methodSteps ?? const <MethodStep>[];
    if (_stepIds.length != steps.length) {
      _stepIds = [
        for (var i = 0; i < steps.length; i++)
          if (i < _stepIds.length) _stepIds[i] else _uuid.v4(),
      ];
    }
    final lines = lineById();
    return [
      for (final (i, step) in steps.indexed)
        toDraft(step, id: _stepIds[i], lineById: lines),
    ];
  }

  void _setMethod(List<MethodDraftStep> drafts) {
    _stepIds = [for (final d in drafts) d.id];
    _set(_current.copyWith(methodSteps: [for (final d in drafts) toTokens(d)]));
  }

  void _mapStep(String stepId, MethodDraftStep Function(MethodDraftStep) f) {
    final drafts = methodDraft();
    final i = drafts.indexWhere((d) => d.id == stepId);
    if (i < 0) return;
    final next = f(drafts[i]);
    // Forui registers its onChange as a plain controller listener, so a
    // no-op edit must not re-enter state: it would round-trip forever.
    if (next == drafts[i]) return;
    _setMethod([...drafts]..[i] = next);
  }

  /// One keystroke in a step card. Span arithmetic (and chip demotion) lives
  /// in [applyEdit]; this only re-seats the result.
  @override
  void editStep(String stepId, String text) =>
      _mapStep(stepId, (d) => applyEdit(d, text));

  @override
  void addMethodStep() {
    final drafts = addStep(methodDraft(), id: _uuid.v4());
    _setMethod(drafts);
  }

  @override
  void removeMethodStep(String stepId) =>
      _setMethod(removeStep(methodDraft(), stepId));

  @override
  void moveMethodStep(String stepId, int by) =>
      _setMethod(moveStep(methodDraft(), stepId, by));

  /// Chips the range `[start, end)` of [stepId] — **changing no text**.
  @override
  void chipRange(
    String stepId, {
    required int start,
    required int end,
    required List<String> refs,
    ChipAmountRule? amountRule,
  }) => _mapStep(
    stepId,
    (d) => annotate(
      d,
      RefSpan(
        start: start,
        end: end,
        refs: refs,
        amountRule:
            amountRule ??
            amountRuleFor(
              methodDraft(),
              lineId: refs.first,
              stepId: stepId,
              offset: start,
            ),
      ),
    ),
  );

  /// Marks `[start, end)` of [stepId] as a timer.
  ///
  /// The one place a selection rewrites text: a timer's words are
  /// [formatTimerRange]'s output in a locked range, with the seconds in the
  /// span record, so the round-trip never re-parses them.
  @override
  void timerRange(
    String stepId, {
    required int start,
    required int end,
    required int lowSeconds,
    required int highSeconds,
  }) => _mapStep(stepId, (d) {
    final span = TimerSpan(
      start: start,
      end: end,
      lowSeconds: lowSeconds,
      highSeconds: highSeconds,
    );
    final marked = annotate(d, span);
    final index = marked.spans.indexWhere((s) => s.start == start);
    if (index < 0) return marked;
    return respan(
      marked,
      index,
      span: span,
      word: formatTimerRange(lowSeconds, highSeconds),
    );
  });

  /// The no-selection door: splices [word] in at the caret and chips it.
  @override
  void insertChip(
    String stepId, {
    required int offset,
    required String word,
    required List<String> refs,
  }) => _mapStep(
    stepId,
    (d) => insertSpan(
      d,
      offset: offset,
      word: word,
      span: RefSpan(
        start: 0,
        end: 0,
        refs: refs,
        amountRule: amountRuleFor(
          methodDraft(),
          lineId: refs.first,
          stepId: stepId,
          offset: offset,
        ),
      ),
    ),
  );

  /// The no-selection door for a timer: inserts [formatTimerRange]'s own
  /// output, so the round-trip never re-parses the string it printed.
  @override
  void insertTimer(
    String stepId, {
    required int offset,
    required int lowSeconds,
    required int highSeconds,
  }) => _mapStep(
    stepId,
    (d) => insertSpan(
      d,
      offset: offset,
      word: formatTimerRange(lowSeconds, highSeconds),
      span: TimerSpan(
        start: 0,
        end: 0,
        lowSeconds: lowSeconds,
        highSeconds: highSeconds,
      ),
    ),
  );

  /// Re-points only the chip at [index] of [stepId], without touching the
  /// sentence.
  @override
  void repointChip(String stepId, int index, List<String> refs) => _mapStep(
    stepId,
    (d) => switch (d.spans.elementAtOrNull(index)) {
      final RefSpan span => respan(
        d,
        index,
        span: span.copyWith(refs: refs),
        word: spanWord(d, index),
      ),
      _ => d,
    },
  );

  /// Renames the chip's word. The one place that changes what a chip says —
  /// the sheet's Word field and the substitution's "keep the old word" both
  /// call it.
  @override
  void renameChip(String stepId, int index, String word) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(d, index, span: d.spans[index], word: word)
        : d,
  );

  /// The show-amount override: display only. No quantity is invented, moved
  /// or summed by flipping it.
  @override
  void setChipAmountRule(String stepId, int index, ChipAmountRule rule) =>
      _mapStep(
        stepId,
        (d) => switch (d.spans.elementAtOrNull(index)) {
          final RefSpan span => respan(
            d,
            index,
            span: span.copyWith(amountRule: rule),
            word: spanWord(d, index),
          ),
          _ => d,
        },
      );

  /// Re-times a timer. Its text becomes [formatTimerRange]'s output again, so
  /// the round-trip still never re-parses the string it printed.
  @override
  void setTimerSpan(String stepId, int index, int low, int high) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(
            d,
            index,
            span: TimerSpan(
              start: 0,
              end: 0,
              lowSeconds: low,
              highSeconds: high,
            ),
            word: formatTimerRange(low, high),
          )
        : d,
  );

  /// Drops a chip or timer, **keeping its word**: the sentence survives and
  /// only the link dies.
  @override
  void removeChip(String stepId, int index) =>
      _mapStep(stepId, (d) => removeSpan(d, index));

  /// What a convert-to-plain-text would cost, for the confirm to count.
  @override
  ({int chips, int timers}) methodLinkCounts() {
    var chips = 0;
    var timers = 0;
    for (final step in methodDraft()) {
      for (final span in step.spans) {
        if (span is RefSpan) chips++;
        if (span is TimerSpan) timers++;
      }
    }
    return (chips: chips, timers: timers);
  }

  /// The one lossy act in the editor: every chip and timer becomes ordinary
  /// words, each step's prose unchanged.
  ///
  /// There is no reverse: tokenization happens only inside the import call, and
  /// no endpoint takes free text and returns tokens (ADR-0004).
  @override
  void convertMethodToPlainText() {
    final prose = flattenMethod(
      _current.methodSteps ?? const [],
      lineById: lineById(),
    );
    _relabels.clear();
    _substitution = null;
    _stepIds = const [];
    _set(_current.copyWith(methodSteps: methodFromPlainSteps(prose)));
  }

  /// The recipe editor owns the whole recipe, so the chip picker's
  /// add-a-line door is open here.
  @override
  bool get canAddLine => true;

  @override
  String? get addLineReason => null;

  /// The group a chip's *new* line lands in — the first one, minted if this
  /// recipe somehow has none.
  @override
  String ensureGroupId() {
    if (_current.groups.isNotEmpty) return _current.groups.first.id;
    final id = _uuid.v4();
    _set(_current.copyWith(groups: [IngredientGroup(id: id)]));
    return id;
  }

  /// Persists the recipe (dropping blank steps) and returns it as written, so a
  /// caller making a sub-recipe gets its title and yields. A second call while
  /// the first is writing returns the same recipe.
  ///
  /// Also invalidates the provider so the next "New recipe" rebuilds from
  /// scratch, but only while this notifier is alive: after an auto-dispose
  /// mid-write, touching `ref` throws.
  Future<Recipe> save() async {
    final kept = lineById().keys.toSet();
    final method = [
      for (final step in _current.methodSteps ?? const <MethodStep>[])
        if (toDraft(step, id: '').text.trim().isNotEmpty) step,
    ];
    final recipe = _current.copyWith(
      // The backstop for a title field that was never left.
      title: cleanName(_current.title, NameKind.title),
      // The plain-text shape is read for legacy rows and never written.
      steps: const [],
      // A dangling ref can never reach the database, however the editor got
      // here — the invariant is enforced on the way out, not trusted.
      methodSteps: pruneDanglingRefs(method, kept),
    );
    if (_saving) return recipe;
    _saving = true;
    // The substitution flag lives for one sitting; a save is the end of it.
    _relabels.clear();
    _substitution = null;
    try {
      await ref.read(recipeRepositoryProvider).saveRecipe(recipe);
    } finally {
      _saving = false;
    }
    if (ref.mounted) ref.invalidateSelf();
    return recipe;
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
