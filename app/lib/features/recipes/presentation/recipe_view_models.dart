/// Riverpod ViewModels for the recipes UI.
///
/// Read models are thin streams off the repository; the editor is a small
/// [RecipeEditor] notifier holding the in-progress aggregate with immutable
/// mutators the editor view calls.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../data/recipe_providers.dart';
import '../domain/line_reorder.dart';
import '../domain/method_draft.dart';
import '../domain/method_step.dart';
import '../domain/recipe.dart';
import '../domain/recipe_header_edits.dart';
import '../domain/recipe_repository.dart';
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

/// Whether the recipe page prints each ingredient line's own macros under its
/// name, beneath the per-serving panel's total.
///
/// A **reading posture**, not a household fact: it changes what one person is
/// looking at right now, so it is neither written to the recipe nor synced.
/// Keep-alive rather than per-page so the choice survives moving between
/// recipes — a reader comparing two recipes' lines should not have to switch it
/// back on — and it resets with the app, which is as long as a posture lasts.
@Riverpod(keepAlive: true)
class ShowLineMacros extends _$ShowLineMacros {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

/// Resolves the vocab [Ingredient] behind an editor line item, so its unit
/// dropdown can be filtered by [allowedUnitsFor]. The repository only exposes
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
///
/// [RecipeEditor.build]'s [initialTitle] seeds a NEW draft's title — what
/// `/recipes/new?title=…` carries from the Library's "nothing matches" state,
/// so a search for a recipe you were about to write becomes that recipe rather
/// than an empty form. It is part of the family key, so arriving with a
/// different title is a different draft.
///
/// [initialBookId] and [initialSectionId] are the same idea for the FILING
/// (0028 E3): `/recipes/new?book=…&section=…` is what a section's `＋` hands
/// over, so the recipe lands on the shelf you tapped instead of in whichever
/// book `ensureDefaultBook` returns. They key the family too — the same
/// blank form filed into two different sections is two drafts.
///
/// It `implements MethodEditing` (seam D4) — a declaration, not a refactor:
/// every member of that interface was already here, written for the step cards.
/// The import review's adapter implements the same surface, so the cards can
/// host on either screen without two of them existing. The same holds for
/// [RecipeHeaderHost]: the header form renders over this notifier here and over
/// the import controller at review.
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
      if (existing != null) return _tokenized(existing);
    }
    // New recipe: filed from the start, so FILE UNDER states a fact rather
    // than asking a question. The shelf you tapped when it is one of the
    // section doors; otherwise the default book, unsectioned, as before.
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

  // --- the header ---------------------------------------------------
  //
  // Every rule — both halves of a yield or neither, the other-family lock,
  // no freezer window on a dish that does not freeze — is `RecipeHeaderEdits`,
  // shared with the import review's host; these only seat the result.

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

  /// Appends a line for [ingredient]. The 7.7 add flow hands the quantity +
  /// unit choice straight from the quantity sheet; without a [choice] the
  /// line starts in the ingredient's default unit.
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
  @override
  void addComponentLineItem(
    String groupId,
    SubRecipeTarget target, {
    double? quantity,
    Unit? unit,
    bool optional = false,
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
          optional: optional,
        ),
      ],
    ),
  );

  /// Moves the ingredient line at flat row [from] to row [to] — the editor's
  /// whole reorder-and-refile gesture (`line_reorder.dart` holds the rule, and
  /// the import review's list obeys the same one).
  ///
  /// **The line object is carried across, not rebuilt**, so its id survives
  /// the move and every method chip pointing at it still does. A group left
  /// empty by the move is kept: the heading is the human's.
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

  /// Sets the line's note — the modifier the recipe page prints after the name
  /// ("Garlic · peeled and crushed"). Blank clears it, so the field and the
  /// absence of a note are the same gesture.
  ///
  /// It goes through [_mapItem], never [_setIdentity]: a note says nothing
  /// about what the line IS, so it must not relabel a single method chip.
  void setLineItemNote(String itemId, String? note) {
    final text = note?.trim() ?? '';
    _mapItem(itemId, (i) => i.copyWith(note: text.isEmpty ? null : text));
  }

  /// Marks the line optional, or not (the card's flag row). A fact
  /// about the line, never about its amount: the quantity and unit are
  /// untouched, and what changes is what a total covers.
  void setLineItemOptional(String itemId, {required bool optional}) =>
      _mapItem(itemId, (i) => i.copyWith(optional: optional));

  /// Re-points a line at another ingredient, **keeping the line's id** (0022
  /// D6).
  ///
  /// The id is the load-bearing part twice over. It makes `saveRecipe`'s child
  /// diff issue an UPDATE rather than a soft-delete + INSERT — and it is what
  /// keeps every chip that references this line pointing at it. Delete +
  /// re-add would mint a fresh `line_item_id` and leave every chip silently
  /// dangling.
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
          // The picker only offers live rows, so a re-point is exactly the
          // repair the tag asked for: it stops reading as removed the moment
          // the pick lands, not on the next reload.
          ingredientDeleted: false,
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
          ingredientDeleted: false,
          unit: i.unit.family == UnitFamily.batch ? i.unit : batches,
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
  @override
  Substitution? substitution() => _substitution;
  Substitution? _substitution;

  /// Each relabelled chip's previous word, so "keep the old word" is one tap.
  /// Same session lifetime as [substitution].
  @override
  List<ChipRelabel> relabels() => List.unmodifiable(_relabels);
  final List<ChipRelabel> _relabels = [];

  /// D3's revert: the chip keeps its ref and takes its printed word back.
  /// Re-pointing "sausages" from Pork sausage to Italian sausage is the case
  /// where the old word was right all along.
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

  // --- the method (0022) ------------------------------------------------

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
  /// This is the ONE place a selection rewrites text, and it is deliberate: a
  /// timer's words ARE [formatTimerRange]'s output, occupying a locked range
  /// with the seconds in the span record, so the round-trip never re-parses
  /// the string it printed. The timer sheet's "Goes in as" shows exactly what
  /// will land before it lands.
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

  /// Re-points the chip at [index] of [stepId] — **this chip only**, and
  /// without touching the sentence. The line's identity picker is what moves
  /// every chip at once (D3).
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
  /// the sheet's Word field and D3's "keep the old word" call it alike.
  @override
  void renameChip(String stepId, int index, String word) => _mapStep(
    stepId,
    (d) => index < d.spans.length
        ? respan(d, index, span: d.spans[index], word: word)
        : d,
  );

  /// The D9 override: display only. No quantity is invented, moved or summed
  /// by flipping it.
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

  /// What a convert-to-plain-text would cost, for the confirm to count (D5).
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

  /// D5, the one lossy act in the editor: every chip and timer becomes
  /// ordinary words. Each step keeps its OWN prose, byte-identical to what its
  /// card was showing — no sentence changes, only the links go.
  ///
  /// **There is no reverse, and the copy says why.** Tokenization happens only
  /// inside the import call, which grounds each ref by index into the same
  /// extraction it just read (§4.6). There is no endpoint that takes free text
  /// and returns tokens, and building one would ship user prose to a model
  /// over a route ADR-0004 never opened.
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
  /// add-a-line door is open here (seam D4).
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

  /// Persists the recipe (dropping blank steps) and returns it as written. A
  /// second call while the first is still writing is a no-op that returns the
  /// same recipe — a double-tapped Save must not race two child-diff writes.
  ///
  /// It hands back the whole [Recipe], not just the id, because a caller that
  /// pushed this editor to MAKE a sub-recipe needs its title and yields to
  /// build the line that was waiting on it.
  ///
  /// Also resets the provider: the editor is left after a save, and without an
  /// explicit reset a lingering instance (auto-dispose only fires once the
  /// last listener is gone, which navigation timing can defer) hands the old
  /// draft to the next "New recipe" open. Invalidate-on-save guarantees a
  /// fresh open always rebuilds from scratch — but only while this notifier is
  /// still alive: after an auto-dispose mid-write, touching `ref` throws.
  Future<Recipe> save() async {
    final kept = lineById().keys.toSet();
    final method = [
      for (final step in _current.methodSteps ?? const <MethodStep>[])
        if (toDraft(step, id: '').text.trim().isNotEmpty) step,
    ];
    final recipe = _current.copyWith(
      // The backstop for a title field that was never left.
      title: cleanName(_current.title, NameKind.title),
      // The plain shape is write-never, read-legacy from 0022 on (D8).
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
