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
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_repository.dart';

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

/// The recipes that list [id] as a component — the "Used in · N" tab's rows
/// (step 8.6 / D9), and the same count D5's delete refusal speaks.
///
/// It re-reads whenever the recipe itself changes, which is what a link
/// written on this device (or synced in from the other one) moves.
@riverpod
Future<List<RecipeUse>> recipeUsedIn(Ref ref, String id) {
  ref.watch(recipeByIdProvider(id));
  return ref.watch(recipeRepositoryProvider).usedIn(id);
}

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
  for (final m in matches.rows) {
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
      if (existing != null) return _tokenized(existing);
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
      methodSteps: const [],
    );
  }

  /// One method shape from here on (0022 D8): a recipe opened with the legacy
  /// plain [Recipe.steps] becomes one text token per line, so the editor, the
  /// recipe page and cook mode all read the same thing. Nothing is
  /// re-tokenized, re-matched or re-fetched — a line of prose is a line of
  /// prose.
  Recipe _tokenized(Recipe recipe) => recipe.methodSteps != null
      ? recipe
      : recipe.copyWith(methodSteps: methodFromPlainSteps(recipe.steps));

  Recipe get _current => state.requireValue;
  void _set(Recipe r) => state = AsyncData(r);

  /// Editor-session step ids, index-aligned with `methodSteps`. Minted on
  /// load, carried through reorder, and never persisted — see
  /// [stableStepKey] for why the wire format holds none.
  List<String> _stepIds = const [];

  /// True while a [save] is in flight. A double-tapped Save would otherwise run
  /// the child-diff write twice concurrently.
  bool _saving = false;

  void setTitle(String title) => _set(_current.copyWith(title: title));

  void setServings(double servings) =>
      _set(_current.copyWith(servingsBase: servings <= 0 ? 1 : servings));

  /// Sets what one batch MAKES — the first denomination (step 8.6 / D2, board
  /// frame h). Both halves are set or neither is, and clearing the first also
  /// drops the second: the migration pins "a second denomination only when the
  /// first is stated", and a save that bounces off a CHECK is not a state the
  /// editor should be able to reach.
  void setYield(double? qty, Unit? unit) {
    final stated = qty != null && qty > 0 && unit != null;
    _set(
      _current.copyWith(
        yieldQty: stated ? qty : null,
        yieldUnit: stated ? unit : null,
        yieldQty2: stated ? _current.yieldQty2 : null,
        yieldUnit2: stated ? _current.yieldUnit2 : null,
      ),
    );
  }

  /// Sets (or clears, with nulls) the optional SECOND denomination — "makes
  /// 250 g · 16 tbsp". Ignored while no first denomination is stated, and a
  /// unit in the first's own family is refused: the pair exists to bridge two
  /// families, and two numbers in one family would be a second fact about the
  /// same one.
  void setSecondYield(double? qty, Unit? unit) {
    if (_current.yieldQty == null || _current.yieldUnit == null) return;
    final stated = qty != null && qty > 0 && unit != null;
    if (stated && unit.family == _current.yieldUnit!.family) return;
    _set(
      _current.copyWith(
        yieldQty2: stated ? qty : null,
        yieldUnit2: stated ? unit : null,
      ),
    );
  }

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

  /// Appends a **component** line pointing at [target] (step 8.6 / D1). It is
  /// an ordinary line with the other identity: no ingredient id, no measure
  /// (measures are an ingredient concept), and a `batch` default so a line
  /// backed out of the quantity sheet still means something honest.
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
  }) => _mapGroup(
    groupId,
    (g) => g.copyWith(
      items: [
        ...g.items,
        LineItem(
          id: _uuid.v4(),
          subRecipeId: target.id,
          subRecipe: target,
          ingredientName: target.title,
          quantity: quantity,
          unit: unit ?? batches,
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

  /// Re-points a line at another ingredient, **keeping the line's id** (0022
  /// D6).
  ///
  /// The id is the load-bearing part twice over. It makes `saveRecipe`'s child
  /// diff issue an UPDATE rather than a soft-delete + INSERT — and it is what
  /// keeps every chip that references this line pointing at it. Delete +
  /// re-add, the only route the editor used to offer, minted a fresh
  /// `line_item_id` and left every chip silently dangling.
  ///
  /// The measure goes with the old ingredient: "potato, medium = 213 g" says
  /// nothing about a fennel bulb.
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
          unit: i.unit.family == ingredient.defaultUnit.family
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
          unit: i.unit.family == UnitFamily.batch ? i.unit : batches,
        ),
      );

  void _setIdentity(
    String itemId,
    {
    required String name,
    required LineItem Function(LineItem) item,
  }) {
    final before = lineById()[itemId];
    if (before == null) return;
    _mapItem(itemId, item);
    // D3 fires ONLY on an identity change — never on a quantity, unit,
    // measure or note edit. Re-picking the same ingredient changes nothing.
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

  /// The substitution being read through this sitting, or null. **Session
  /// state, not a column** — the swap and the read-through happen in one
  /// sitting, and a save clears it.
  Substitution? substitution() => _substitution;
  Substitution? _substitution;

  /// What every relabelled chip used to say, so "keep the old word" is one
  /// tap. Same session lifetime as [substitution].
  List<ChipRelabel> relabels() => List.unmodifiable(_relabels);
  final List<ChipRelabel> _relabels = [];

  /// D3's revert: the chip keeps its ref and takes its printed word back.
  /// Re-pointing "sausages" from Pork sausage to Italian sausage is the case
  /// where the old word was right all along.
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

  // --- the method (0022) ------------------------------------------------

  /// Every line of this recipe by id — what the fold derives a chip's live
  /// amount from, and what the line picker offers.
  Map<String, LineItem> lineById() => {
    for (final group in _current.groups)
      for (final item in group.items) item.id: item,
  };

  /// The method as the editor holds it: one sentence per step, with the ranges
  /// that are chips. Derived from the tokens, so there is one source of truth.
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
    _set(
      _current.copyWith(methodSteps: [for (final d in drafts) toTokens(d)]),
    );
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
  void editStep(String stepId, String text) =>
      _mapStep(stepId, (d) => applyEdit(d, text));

  void addMethodStep() {
    final drafts = addStep(methodDraft(), id: _uuid.v4());
    _setMethod(drafts);
  }

  void removeMethodStep(String stepId) =>
      _setMethod(removeStep(methodDraft(), stepId));

  void moveMethodStep(String stepId, int by) =>
      _setMethod(moveStep(methodDraft(), stepId, by));

  /// Chips the range `[start, end)` of [stepId] — **changing no text**.
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
  /// This is the ONE place a selection rewrites text, and it is deliberate: a
  /// timer's words ARE [formatTimerRange]'s output, occupying a locked range
  /// with the seconds in the span record, so the round-trip never re-parses
  /// the string it printed. The timer sheet's "Goes in as" shows exactly what
  /// will land before it lands.
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

  /// Re-points the chip at [index] of [stepId] — **this chip only**, and
  /// without touching the sentence. The line's identity picker is what moves
  /// every chip at once (D3).
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
  /// the sheet's Word field and D3's "keep the old word" call it alike.
  void renameChip(String stepId, int index, String word) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(d, index, span: d.spans[index], word: word)
        : d,
  );

  /// The D9 override: display only. No quantity is invented, moved or summed
  /// by flipping it.
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
  void removeChip(String stepId, int index) =>
      _mapStep(stepId, (d) => removeSpan(d, index));

  /// What a convert-to-plain-text would cost, for the confirm to count (D5).
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

  /// D5, the one lossy act in the editor: every chip and timer becomes
  /// ordinary words. Each step keeps its OWN prose, byte-identical to what its
  /// card was showing — no sentence changes, only the links go.
  ///
  /// **There is no reverse, and the copy says why.** Tokenization happens only
  /// inside the import call, which grounds each ref by index into the same
  /// extraction it just read (§4.6). There is no endpoint that takes free text
  /// and returns tokens, and building one would ship user prose to a model
  /// over a route ADR-0004 never opened.
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

  /// The group a chip's *new* line lands in — the first one, minted if this
  /// recipe somehow has none.
  String ensureGroupId() {
    if (_current.groups.isNotEmpty) return _current.groups.first.id;
    final id = _uuid.v4();
    _set(_current.copyWith(groups: [IngredientGroup(id: id)]));
    return id;
  }

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
    final kept = lineById().keys.toSet();
    final method = [
      for (final step in _current.methodSteps ?? const <MethodStep>[])
        if (toDraft(step, id: '').text.trim().isNotEmpty) step,
    ];
    final recipe = _current.copyWith(
      title: _current.title.trim(),
      // The plain shape is write-never, read-legacy from 0022 on (D8).
      steps: const [],
      // A dangling ref can never reach the database, however the editor got
      // here — the invariant is enforced on the way out, not trusted.
      methodSteps: pruneDanglingRefs(method, kept),
    );
    if (_saving) return recipe.id;
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
