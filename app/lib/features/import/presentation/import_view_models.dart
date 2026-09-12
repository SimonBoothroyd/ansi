/// Riverpod ViewModels for the import flow (step 8): intake → reconcile →
/// commit, held in one [ImportController] the intake and reconciliation views
/// share.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../recipes/domain/method_draft.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/domain/recipe_header_edits.dart';
import '../../recipes/presentation/recipe_header_form.dart';
import '../data/import_providers.dart';
import '../domain/header_draft.dart';
import '../domain/import_repository.dart';
import '../domain/import_stage.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/method_draft_bridge.dart';
import '../domain/preview_recipe.dart';
import '../domain/reconciliation_payload.dart';
import '../domain/review_groups.dart';

part 'import_view_models.g.dart';

/// The import session state machine.
sealed class ImportState {
  const ImportState();
}

/// Nothing started yet — the intake screen's resting state.
class ImportIdle extends ImportState {
  const ImportIdle();
}

/// Extraction + matching is running server-side (the `import-recipe` edge
/// function).
///
/// It carries the checklist the reading screen draws: one row per stage the
/// SERVER said this import would walk, each finished row frozen at the elapsed
/// time the server reported for it, the running one ticking. Nothing here is
/// an estimate — before the plan's first event arrives, [rows] is simply
/// empty.
class ImportLoading extends ImportState {
  const ImportLoading({required this.rows, required this.fromPhotos});

  /// The checklist, in the server's order. Empty until the plan arrives.
  final List<StageProgress> rows;

  /// Which door this import came through — the only thing the screen's wording
  /// needs beyond the stage ids.
  final bool fromPhotos;
}

/// The payload is back; the user is resolving lines. Immutable — every edit
/// produces a new instance so the reconciliation view rebuilds.
class ImportReconciling extends ImportState {
  ImportReconciling({
    required this.payload,
    required this.resolutions,
    required this.header,
    this.editedSteps,
    List<ReviewGroup>? sections,
  }) : sections = sections ?? initialGroups(payload);

  final ReconciliationPayload payload;
  final List<LineResolution> resolutions;

  /// The ingredient list's SECTIONS as the human holds them: the payload's
  /// own to start with, then whatever they renamed, deleted, added or filed a
  /// line into (`review_groups.dart`).
  ///
  /// It rides here rather than on the payload deliberately. The payload is
  /// the server's word about the page and has to stay that way — `from
  /// source:` is only honest while nothing has rewritten it — so the human's
  /// structure is a second list beside it, keyed by the same flat line
  /// indexes everything else already uses.
  final List<ReviewGroup> sections;

  /// The header draft: title, serves, makes in up to two denominations, times,
  /// shelf life and filing, as the shared header form edits them — seeded by
  /// [headerDraft], every column read off it at commit. The preview recipe is
  /// this same object with the lines on it, earlier.
  ///
  /// None of it gates Save. A yield-less, time-less recipe saves, links and
  /// scales; only the derived numbers wait.
  final Recipe header;

  /// The method as the review's step cards hold it, once anybody has typed
  /// (seam **D4**). Null means "nobody has": the cards then derive their
  /// drafts from the payload through the preview, so the common path stores
  /// nothing and a commit writes `payload.steps` byte-for-byte.
  final List<MethodDraftStep>? editedSteps;

  /// The serving count the preview scales against — the header's, read
  /// through so the preview and the commit cannot disagree.
  double get servings => header.servingsBase;

  /// The [ReconLine] behind [lineIndex] — the payload's own, or the stand-in
  /// for a line the REVIEW minted, whose index is past the payload's last.
  ///
  /// Every widget on this screen is written against "the page's line", and a
  /// line the page does not have still has to render: the stand-in carries
  /// the name the human picked and nothing else, which is exactly what "the
  /// page never printed this" looks like. One rule, so no caller has to
  /// remember that indexing `flatLines` can now run off the end.
  ReconLine lineAt(int lineIndex) {
    final flat = payload.flatLines;
    if (lineIndex < flat.length) return flat[lineIndex];
    return addedLine(resolutions.firstWhere((r) => r.lineIndex == lineIndex));
  }

  /// The method as the step cards hold it **right now**: the stored drafts
  /// once anybody has typed, else derived from this state's own preview.
  ///
  /// One rule, in one place, because two callers need it at different moments:
  /// the step-card host on every build (which already has the preview, and
  /// passes it in rather than paying for a second one), and
  /// [ImportController.updateResolution]'s relabel — which runs before any
  /// card has been built and so has to derive its own. The measures a view's
  /// preview carries change a line's printed AMOUNT, never its name, and a
  /// draft reads only names, so the two derivations agree.
  List<MethodDraftStep> methodDrafts({Recipe? preview}) =>
      editedSteps ??
      draftsFromPreview(
        preview ??
            buildPreviewRecipe(
              payload,
              resolutions,
              servingsBase: servings,
              sections: sections,
            ),
      );

  /// Every kept line resolved, and at least one line kept — the structural half
  /// of the commit gate. Unit validity is the other half and needs the vocab,
  /// so it lives in [importValidation]; [importOutstandingLines] is what the UI
  /// gates on. Dropping every line leaves nothing to save, and [buildCommit]
  /// refuses it at the seam as well.
  bool get canCommit =>
      allResolved(resolutions) && keptLines(resolutions).isNotEmpty;

  /// Count of lines still structurally unresolved — the fallback count while
  /// the ingredient-backed validation is loading for the first time. A dropped
  /// line never counts: it is leaving.
  int get unresolvedCount =>
      resolutions.where((r) => !r.isDropped && !r.isResolved).length;

  /// The fingerprint of everything [importValidation] depends on: per line, its
  /// match, its unit, whether a printed range still needs a number, and whether
  /// it was dropped (a dropped line reports no issues). Notes and the header
  /// change no line's validity, so typing a note must not re-run a vocab
  /// query per line.
  String get validationKey {
    final key = StringBuffer();
    for (final r in resolutions) {
      key
        ..write(r.lineIndex)
        ..write('|')
        ..write(r.chosenIngredientId ?? '')
        ..write('|')
        ..write(r.linkedRecipeId ?? '')
        ..write('|')
        ..write(r.unit ?? '')
        ..write('|')
        // A linked line's validity turns on its amount alone (D6), so the
        // amount has to be part of the fingerprint for it.
        ..write(r.isComponent && r.quantity == null)
        ..write('|')
        ..write(r.isRange && r.quantity == null)
        ..write('|')
        ..write(r.isDropped)
        ..write(';');
    }
    return key.toString();
  }

  ImportReconciling copyWith({
    List<LineResolution>? resolutions,
    Recipe? header,
    List<MethodDraftStep>? editedSteps,
    List<ReviewGroup>? sections,
  }) => ImportReconciling(
    payload: payload,
    resolutions: resolutions ?? this.resolutions,
    header: header ?? this.header,
    editedSteps: editedSteps ?? this.editedSteps,
    sections: sections ?? this.sections,
  );
}

/// Commit is writing to PowerSync.
class ImportCommitting extends ImportState {
  const ImportCommitting();
}

/// Commit succeeded; [recipeId] is the new recipe.
class ImportCommitted extends ImportState {
  const ImportCommitted(this.recipeId);
  final String recipeId;
}

/// Something failed (extraction or commit); [message] is user-facing.
class ImportFailed extends ImportState {
  const ImportFailed(this.message);
  final String message;
}

/// The import session controller.
///
/// It is `autoDispose` (the default), so the user can back out of `/import`
/// while an extraction or a commit is still in flight — and in Riverpod 3
/// writing `state` on a disposed notifier THROWS (in release too). Every
/// post-await assignment here, the `catch` blocks included, is therefore
/// guarded by [Ref.mounted]. Guards rather than `keepAlive`: an abandoned
/// import should be collected, not kept warm for a flow the user left.
@riverpod
class ImportController extends _$ImportController implements RecipeHeaderHost {
  @override
  ImportState build() {
    ref.onDispose(_stopStageLadder);
    return const ImportIdle();
  }

  /// True while [startImport] is running. Extraction is a billed LLM call, so a
  /// double-tapped "Import" must not fire two of them.
  bool _starting = false;

  /// Ticks the running stage's clock while the call is in flight. The rows
  /// themselves come from the server; this only moves the one that is running.
  Timer? _stageTimer;

  /// How often the running row's clock advances. It prints m:ss, so a second.
  static const _stageTick = Duration(seconds: 1);

  /// The plan the server sent, and how far through it the import is.
  List<ImportStage> _plan = const [];
  final Map<ImportStage, Duration> _finished = {};

  /// Time since the call started, ACCUMULATED from the ticks rather than read
  /// off the wall clock, so the screen advances with whatever clock the caller
  /// is pumping — which is what makes it testable.
  Duration _elapsed = Duration.zero;

  /// Opens the reading screen with nothing claimed yet and starts the clock.
  void _startStageClock({required bool fromPhotos}) {
    _stageTimer?.cancel();
    _plan = const [];
    _finished.clear();
    _elapsed = Duration.zero;
    _publishStages(fromPhotos: fromPhotos);
    _stageTimer = Timer.periodic(_stageTick, (timer) {
      // The notifier is autoDispose and the user can leave mid-import; writing
      // `state` — or even reading it — on a disposed notifier throws.
      if (!ref.mounted || state is! ImportLoading) {
        timer.cancel();
        return;
      }
      _elapsed += _stageTick;
      _publishStages(fromPhotos: fromPhotos);
    });
  }

  /// Folds a server event into the checklist. Called from the repository's
  /// `onProgress`, which can fire after the user has left the screen.
  void _onProgress(ImportProgress progress, {required bool fromPhotos}) {
    if (!ref.mounted || state is! ImportLoading) return;
    switch (progress) {
      case ImportPlanned(:final stages):
        _plan = stages;
      case ImportStageDone(:final stage, :final elapsed):
        _finished[stage] = elapsed;
        // The server's clock is the authority on how far in we are; keeping
        // the local one behind it would make the running row start negative.
        if (elapsed > _elapsed) _elapsed = elapsed;
    }
    _publishStages(fromPhotos: fromPhotos);
  }

  void _publishStages({required bool fromPhotos}) {
    state = ImportLoading(
      rows: stageChecklist(plan: _plan, finished: _finished, elapsed: _elapsed),
      fromPhotos: fromPhotos,
    );
  }

  void _stopStageLadder() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  /// Runs the extract→match pipeline for [source] and moves to reconciliation.
  /// A second call while the first is in flight is a no-op.
  Future<void> startImport(
    ImportSource source, {
    String? bookId,
    String? sectionId,
  }) async {
    if (_starting) return;
    _starting = true;
    // A new page is a new sitting: nothing the last one relabelled has a chip
    // left to put its word back on.
    clearRelabels();
    final fromPhotos = source is ImportFromPhotos;
    _startStageClock(fromPhotos: fromPhotos);
    try {
      // Both keepAlive repositories are resolved BEFORE the first await: this
      // notifier can be disposed across the gap, and `ref` goes with it.
      final importRepo = ref.read(importRepositoryProvider);
      final bookRepo = ref.read(bookRepositoryProvider);
      final payload = await importRepo.startImport(
        source,
        onProgress: (p) => _onProgress(p, fromPhotos: fromPhotos),
      );
      // The draft is FILED from the start, so FILE UNDER shows where the
      // recipe will land rather than a blank a human has to fill before
      // anything is honest. The shelf the door knew about when there was one
      // (0028 E3), else the same default book commit has always used.
      final filedBookId = bookId ?? (await bookRepo.ensureDefaultBook()).id;
      if (!ref.mounted) return;
      // The header opens on whatever the page PLAINLY said — servings, a
      // yield in a plain amount + unit, the printed times — and unset
      // otherwise: 0014's attempt-then-flag, over the whole header now.
      state = ImportReconciling(
        payload: payload,
        resolutions: initialResolutions(payload),
        header: headerDraft(payload, bookId: filedBookId, sectionId: sectionId),
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ImportFailed('Could not import this recipe: $e');
    } finally {
      _stopStageLadder();
      _starting = false;
    }
  }

  /// Applies [update] to the resolution at [lineIndex]. A no-op unless the flow
  /// is at reconciliation.
  void updateResolution(
    int lineIndex,
    LineResolution Function(LineResolution) update,
  ) {
    final s = state;
    if (s is! ImportReconciling) return;
    final before = s.resolutions.firstWhere((r) => r.lineIndex == lineIndex);
    final after = update(before);
    // D-D1: an IDENTITY change carries every chip that points at this line —
    // the editor's shipped behaviour, switched on here. It fires on the
    // display name, so a re-match, a recipe LINK and an unlink all count, and
    // a quantity, unit, measure, note, drop or optional edit does not. The
    // drafts are derived from the state BEFORE, so a blank-labelled chip's
    // "old word" is the word it was actually showing.
    final relabelled = after.displayName == before.displayName
        ? null
        : relabelRefs(
            s.methodDrafts(),
            lineId: previewLineId(lineIndex),
            label: after.displayName,
          );
    final moved = relabelled != null && relabelled.relabels.isNotEmpty;
    state = s.copyWith(
      resolutions: [
        for (final r in s.resolutions)
          if (r.lineIndex == lineIndex) after else r,
      ],
      // Only when a chip actually moved: an identity change nothing points at
      // must leave the method exactly as it was, so an untouched method still
      // commits `payload.steps` byte-for-byte (seam D4).
      editedSteps: moved ? relabelled.steps : null,
    );
    if (moved) {
      _relabels
        ..removeWhere(
          (r) => relabelled.relabels.any(
            (n) => n.stepId == r.stepId && n.spanIndex == r.spanIndex,
          ),
        )
        ..addAll(relabelled.relabels);
      _substitution = (
        oldName: before.displayName,
        newName: after.displayName,
        stepIds: {for (final r in relabelled.relabels) r.stepId},
      );
    }
  }

  /// The substitution being read through this sitting, or null — what the
  /// method's *"2 steps mentioned wild garlic"* notice speaks.
  ///
  /// **Session state, not a column**, exactly as on the editor: the swap and
  /// the read-through happen in one sitting, and the commit ends it.
  Substitution? substitution() => _substitution;
  Substitution? _substitution;

  /// Each relabelled chip's previous word, so *keep the old word* is one tap.
  /// Same session lifetime as [substitution].
  List<ChipRelabel> relabels() => List.unmodifiable(_relabels);
  final List<ChipRelabel> _relabels = [];

  /// Forgets one relabel — the other half of `keepOldWord`, whose rename goes
  /// through the ordinary chip door so one place changes what a chip says.
  void forgetRelabel(ChipRelabel relabel) {
    _relabels.remove(relabel);
    if (_relabels.isEmpty) _substitution = null;
  }

  /// Forgets every relabel this sitting collected — a flatten has no chips
  /// left to put a word back on.
  void clearRelabels() {
    _relabels.clear();
    _substitution = null;
  }

  // --- the sections (front A) -------------------------------------------
  //
  // The editor's three group doors, over the review's own section list. The
  // payload is never touched: these edit `ImportReconciling.sections`, which
  // `buildCommit` reads, so the server's word about the page and the human's
  // structure stay separate things.

  void _mapSections(List<ReviewGroup> Function(List<ReviewGroup>) f) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(sections: f(s.sections));
  }

  /// Renames a section. Blank clears the heading rather than storing one.
  void setSectionName(String groupId, String? name) =>
      _mapSections((g) => renameGroup(g, groupId, name));

  /// Deletes a section's heading. **Its lines are never deleted** — they move
  /// into the section above (below, for the first), keeping their order and
  /// every resolution. Dropping food is the line's own bin, and nothing is
  /// lost here, so nothing is confirmed here either.
  void removeSection(String groupId) =>
      _mapSections((g) => removeGroup(g, groupId));

  /// Moves the line row at flat row [from] to row [to] — the editor's gesture,
  /// over the review's own list (`review_groups.dart`).
  ///
  /// A line keeps its **index** and changes only its **position**: the index
  /// is what resolutions are keyed by and what step chips point at, while the
  /// position is what commits as `sort_order`. Nothing renumbers, so no chip
  /// moves.
  void moveLine(int from, int to) =>
      _mapSections((g) => moveReviewLine(g, from: from, to: to));

  /// Appends an empty section. It fills by adding a line to it.
  void addSection() =>
      _mapSections((g) => addGroup(g, id: 'g-new-${_newSectionSeq++}'));

  /// A counter rather than a uuid: the review is one screen with no
  /// persistence of its own, and a stable readable id keeps the widget keys
  /// legible in a test.
  int _newSectionSeq = 0;

  /// Mints a line the page never printed, files it into [groupId], and
  /// returns its flat index (null outside the review).
  ///
  /// The index comes from past the payload's last, so nothing renumbers and
  /// every step chip already written keeps pointing where it did.
  int? addLine(
    String groupId, {
    required String name,
    String? ingredientId,
    String? recipeId,
    double? quantity,
    String? unit,
    bool optional = false,
  }) {
    final s = state;
    if (s is! ImportReconciling) return null;
    final index = nextLineIndex(s.payload, s.sections);
    state = s.copyWith(
      resolutions: [
        ...s.resolutions,
        LineResolution.added(
          lineIndex: index,
          name: name,
          ingredientId: ingredientId,
          recipeId: recipeId,
          quantity: quantity,
          unit: unit,
          optional: optional,
        ),
      ],
      sections: addLineToGroup(s.sections, groupId, index),
    );
    return index;
  }

  /// The reconciliation as it stands **right now**, or null outside the
  /// review. The step-card host is built once per frame but its mutators fire
  /// several times per gesture, so it reads through this rather than the
  /// state it captured — see `ImportMethodEditing.methodDraft`.
  ImportReconciling? reconciling() {
    final s = state;
    return s is ImportReconciling ? s : null;
  }

  /// Re-seats the review's method drafts (seam **D4**) — every step-card edit
  /// lands here through `ImportMethodEditing`.
  void setMethodDraft(List<MethodDraftStep> drafts) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(editedSteps: drafts);
  }

  // --- the header ---------------------------------------------------
  //
  // The review is the header form's second host. Every rule a setter holds
  // is `RecipeHeaderEdits`, shared with the editor's notifier; these only
  // re-seat the draft. A no-op unless the flow is at reconciliation.

  /// The header draft the form renders. Only meaningful at reconciliation —
  /// the form exists on no other screen of the flow.
  @override
  Recipe get header {
    final s = state;
    if (s is! ImportReconciling) {
      throw StateError('the import has no header outside the review');
    }
    return s.header;
  }

  void _mapHeader(Recipe Function(Recipe) f) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(header: f(s.header));
  }

  @override
  void setTitle(String title) => _mapHeader((h) => h.copyWith(title: title));

  @override
  void setServings(double servings) =>
      _mapHeader((h) => h.withServings(servings));

  @override
  void setYield(double? qty, Unit? unit) =>
      _mapHeader((h) => h.withYield(qty, unit));

  @override
  void setSecondYield(double? qty, Unit? unit) =>
      _mapHeader((h) => h.withSecondYield(qty, unit));

  @override
  void setCookTime(int? seconds) => _mapHeader((h) => h.withCookTime(seconds));

  @override
  void setTotalTime(int? seconds) =>
      _mapHeader((h) => h.withTotalTime(seconds));

  @override
  void setKeepsForDays(int? days) =>
      _mapHeader((h) => h.withKeepsForDays(days));

  @override
  void setFreezable(bool freezable) =>
      _mapHeader((h) => h.withFreezable(freezable));

  @override
  void setFreezerDays(int? days) => _mapHeader((h) => h.withFreezerDays(days));

  @override
  void setBook(String bookId) => _mapHeader((h) => h.withBook(bookId));

  @override
  void setSection(String? sectionId) =>
      _mapHeader((h) => h.withSection(sectionId));

  /// Builds the commit payload and writes it. Returns the new recipe id, or
  /// null if the flow wasn't ready / a write failed.
  ///
  /// [issuesByLine] is the review screen's per-line validity (from
  /// [importValidation]) — the SAME map the Save button is derived from, handed
  /// down so [buildCommit] can enforce the gate rather than trust the caller.
  Future<String?> commit({
    required Map<int, List<LineIssue>>? issuesByLine,
  }) async {
    final s = state;
    if (s is! ImportReconciling || !s.canCommit) return null;
    final edited = s.editedSteps;
    final payload = buildCommit(
      s.payload,
      s.resolutions,
      header: s.header,
      issuesByLine: issuesByLine,
      sections: s.sections,
      // Only when somebody actually typed: an untouched method commits the
      // payload's own steps byte-for-byte (seam D4).
      steps: edited == null
          ? null
          : stepsFromDrafts(edited, {
              for (final r in keptLines(s.resolutions)) r.lineIndex,
            }),
    );
    state = const ImportCommitting();
    try {
      final id = await ref.read(importRepositoryProvider).commit(payload);
      // The recipe IS saved. If the user left mid-write we can't route them to
      // it, but we must not throw over a disposed notifier either — return the
      // id so the caller can still act on it.
      if (ref.mounted) state = ImportCommitted(id);
      return id;
    } on Object catch (e) {
      if (ref.mounted) state = ImportFailed('Could not save the recipe: $e');
      return null;
    }
  }

  /// Resets the flow (e.g. after leaving the intake screen).
  void reset() {
    clearRelabels();
    state = const ImportIdle();
  }
}

/// The narrow slice of the controller [importValidation] actually depends on
/// (see [ImportReconciling.validationKey]). Watching THIS rather than the whole
/// state is what keeps a note keystroke or a servings tap from re-running a
/// vocab query per line.
@riverpod
String importValidationKey(Ref ref) {
  final state = ref.watch(importControllerProvider);
  return state is ImportReconciling ? state.validationKey : '';
}

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// resolves each matched line's ingredient + measures and checks its unit
/// against the ingredient's allowed set (ADR-0008), offering that ingredient's
/// valid units as inline suggestion chips. The review screen reads it for the
/// per-line needs-attention flag, the unit chips, AND the Save gate. Empty
/// until reconciling.
///
/// It is also the one place a match meets THIS DEVICE's vocabulary, so it is
/// where [againstLiveVocabulary] rules: a line matched to a row that has been
/// retired since the server answered reads as UNMATCHED — needs a pick, and
/// holds Save exactly as an unmatched line does. Before that it read as done
/// (no ingredient, so no unit to fault) and committed the dead id.
///
/// It is deliberately NOT recomputed on every controller change: it depends on
/// [importValidationKey], so editing a note or the servings leaves the cached
/// map alone. Views must read it with `AsyncValue.value` (which keeps the last
/// data across a refresh), never a data-only view that goes null mid-recompute.
///
/// The whole import's vocab and the whole import's measures are each fetched in
/// ONE repository query — never N round-trips down the line list, and never
/// through the per-ingredient measure STREAM providers. Those are autoDispose,
/// PowerSync's `watch` does not emit synchronously, and an element disposed
/// before its first emission completes `.future` with a [StateError] — which
/// this loader caught and turned into "no measures", so "1 clove" of a garlic
/// row that carries a `clove` measure validated against an empty list and was
/// flagged "Pick a supported unit". A plain read has no element to lose.
/// Nothing is swallowed now either: a query that genuinely fails surfaces as
/// the provider's error rather than as a screen full of wrongly-flagged lines.
@riverpod
Future<Map<int, LineValidation>> importValidation(Ref ref) async {
  ref.watch(importValidationKeyProvider);
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return const {};

  final matchedIds = {
    for (final r in state.resolutions)
      if (r.chosenIngredientId != null) r.chosenIngredientId!,
  };
  // BOTH repositories are resolved before the first await. They are keepAlive,
  // but `Ref` is not: this provider is autoDispose and can be disposed while
  // its own build is still in flight (the user backs out of the review, or a
  // recompute lands), after which `ref.read` THROWS.
  final vocabRepo = ref.read(ingredientRepositoryProvider);
  final measureRepo = ref.read(measureRepositoryProvider);
  final vocab = await vocabRepo.byIds(matchedIds);
  final measuresById = await measureRepo.measuresByIngredients(matchedIds);

  final result = <int, LineValidation>{};
  // THE seam: this is where the server's match meets this device's vocabulary,
  // so this is where a match at a row that is no longer live becomes what it
  // is — unmatched. `byIds` hands back live rows only, so its keys ARE the
  // liveness answer, at no extra read. Downstream nothing has to know: the
  // card's flag, the "N need you" count, the Save gate and `buildCommit`'s
  // re-check all read the issues this loop writes.
  final resolutions = againstLiveVocabulary(
    state.resolutions,
    liveIngredientIds: vocab.keys.toSet(),
  );
  for (final r in resolutions) {
    Ingredient? ingredient;
    var measures = const <Measure>[];
    if (r.chosenIngredientId != null) {
      ingredient = vocab[r.chosenIngredientId];
      if (ingredient != null) {
        measures = measuresById[ingredient.id] ?? const [];
      }
    }
    result[r.lineIndex] = LineValidation(
      issues: lineIssues(r, ingredient: ingredient, measures: measures),
      unitChoices: ingredient == null
          ? const []
          // The line's own printed unit rides along: a source-printed
          // imprecise word is admissible whatever the category (J3b).
          : acceptableUnitChips(ingredient, measures, parsedUnit: r.unit),
      unitMeasure: _measureNamed(r.unit, measures),
      pieceWeightMissing: countNeedsPieceWeight(r, ingredient),
      // No extra read: the row is already in hand from the one vocab query
      // above.
      sourceLine: ingredient == null ? null : sourceProvenanceLine(ingredient),
    );
  }
  return result;
}

/// The measure [unit] names among [measures], or null when it names a catalog
/// unit (or nothing). A measure rides its LABEL on a resolution, so this is
/// the whole of the lookup.
Measure? _measureNamed(String? unit, List<Measure> measures) {
  if (unit == null || unit.isEmpty) return null;
  for (final m in measures) {
    if (m.label == unit) return m;
  }
  return null;
}

/// The ONE "how many lines still want you" count — the header's "N to review"
/// and the Save button's "N line(s) need you" are the same number, read from
/// the same place — two rules would let the header stop decrementing while the
/// button kept counting. Until the first validation lands it falls back to the
/// structural unresolved count, so the header is never blank or wrong-by-zero.
@riverpod
int importOutstandingLines(Ref ref) {
  final state = ref.watch(importControllerProvider);
  if (state is! ImportReconciling) return 0;
  // `AsyncValue.value` keeps the previous map through a refresh; a data-only
  // read would drop to null on every edit and make the count jump.
  final byLine = ref.watch(importValidationProvider).value;
  if (byLine == null) return state.unresolvedCount;
  return byLine.values.where((v) => !v.isClean).length;
}
