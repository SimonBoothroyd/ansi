/// Riverpod ViewModels for the import flow: intake, reconcile, commit, held in
/// one [ImportController] the intake and reconciliation views share.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/units.dart';
import '../../books/data/book_providers.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/ingredient_repository.dart';
import '../../ingredients/domain/measure_repository.dart';
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

/// Extraction and matching is running server-side (`import-recipe`). [rows] is
/// the stage checklist the server announced, with server-reported times; empty
/// until the plan's first event.
class ImportLoading extends ImportState {
  const ImportLoading({required this.rows, required this.request});

  /// The checklist, in the server's order. Empty until the plan arrives.
  final List<StageProgress> rows;

  /// What the cook handed intake, so the wide review's source column can draw
  /// while the server is still reading.
  final ImportSource request;

  /// Which door this import came through — the only thing the checklist's
  /// wording needs beyond the stage ids.
  bool get fromPhotos => request is ImportFromPhotos;
}

/// The payload is back; the user is resolving lines. Immutable — every edit
/// produces a new instance so the reconciliation view rebuilds.
class ImportReconciling extends ImportState {
  ImportReconciling({
    required this.payload,
    required this.request,
    required this.resolutions,
    required this.header,
    this.editedSteps,
    List<ReviewGroup>? sections,
  }) : sections = sections ?? initialGroups(payload);

  final ReconciliationPayload payload;

  /// What the cook handed intake: the URL, or the photo pages' local paths.
  /// Only the wide review's source column reads it.
  final ImportSource request;

  final List<LineResolution> resolutions;

  /// The ingredient list's sections as the human holds them
  /// (`review_groups.dart`). Kept beside the payload, which stays the server's
  /// word about the page, and keyed by the same flat line indexes.
  final List<ReviewGroup> sections;

  /// The header draft (title, serves, makes, times, shelf life, filing), seeded
  /// by [headerDraft] and read at commit. None of it gates Save.
  final Recipe header;

  /// The method as the step cards hold it once anybody has typed. Null means
  /// untouched: the cards derive from the payload and a commit writes
  /// `payload.steps` byte-for-byte.
  final List<MethodDraftStep>? editedSteps;

  /// The serving count the preview scales against — the header's, read
  /// through so the preview and the commit cannot disagree.
  double get servings => header.servingsBase;

  /// The [ReconLine] behind [lineIndex]: the payload's own, or a stand-in
  /// carrying only the picked name for a line the review minted (its index is
  /// past the payload's last).
  ReconLine lineAt(int lineIndex) {
    final flat = payload.flatLines;
    if (lineIndex < flat.length) return flat[lineIndex];
    return addedLine(resolutions.firstWhere((r) => r.lineIndex == lineIndex));
  }

  /// The method drafts right now: the stored ones once anybody has typed, else
  /// derived from [preview] or this state's own preview. A draft reads only
  /// names, so either preview gives the same result.
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

  /// The structural half of the commit gate: at least one kept line, all
  /// resolved. Unit validity needs the vocab and lives in [importValidation];
  /// the UI gates on [importOutstandingLines]. [buildCommit] re-checks.
  bool get canCommit =>
      allResolved(resolutions) && keptLines(resolutions).isNotEmpty;

  /// Lines still structurally unresolved, dropped ones excluded. The fallback
  /// count while the first validation loads.
  int get unresolvedCount =>
      resolutions.where((r) => !r.isDropped && !r.isResolved).length;

  /// The fingerprint of everything [importValidation] depends on, per line:
  /// match, unit, open range, dropped. Notes and the header are left out so
  /// typing one does not re-run a vocab query.
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
        // A linked line's validity turns on its amount alone, so the amount has
        // to be part of the fingerprint for it.
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
    request: request,
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

/// The import session controller. It is `autoDispose`, so the user can leave
/// mid-flight, and Riverpod 3 throws on writing `state` to a disposed notifier:
/// every post-await assignment, `catch` blocks included, is guarded by
/// [Ref.mounted].
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

  /// Accumulated from ticks rather than the wall clock, so tests can pump it.
  Duration _elapsed = Duration.zero;

  /// Opens the reading screen with nothing claimed yet and starts the clock.
  void _startStageClock({required ImportSource request}) {
    _stageTimer?.cancel();
    _plan = const [];
    _finished.clear();
    _elapsed = Duration.zero;
    _publishStages(request: request);
    _stageTimer = Timer.periodic(_stageTick, (timer) {
      // The notifier is autoDispose and the user can leave mid-import; writing
      // `state` — or even reading it — on a disposed notifier throws.
      if (!ref.mounted || state is! ImportLoading) {
        timer.cancel();
        return;
      }
      _elapsed += _stageTick;
      _publishStages(request: request);
    });
  }

  /// Folds a server event into the checklist. Called from the repository's
  /// `onProgress`, which can fire after the user has left the screen.
  void _onProgress(ImportProgress progress, {required ImportSource request}) {
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
    _publishStages(request: request);
  }

  void _publishStages({required ImportSource request}) {
    state = ImportLoading(
      rows: stageChecklist(plan: _plan, finished: _finished, elapsed: _elapsed),
      request: request,
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
    _startStageClock(request: source);
    try {
      // Both keepAlive repositories are resolved BEFORE the first await: this
      // notifier can be disposed across the gap, and `ref` goes with it.
      final importRepo = ref.read(importRepositoryProvider);
      final bookRepo = ref.read(bookRepositoryProvider);
      final vocabRepo = ref.read(ingredientRepositoryProvider);
      final measureRepo = ref.read(measureRepositoryProvider);
      final payload = await importRepo.startImport(
        source,
        onProgress: (p) => _onProgress(p, request: source),
      );
      // The draft is filed from the start: the door's shelf, else the default
      // book.
      final filedBookId = bookId ?? (await bookRepo.ensureDefaultBook()).id;
      // A counted line lands on its row's whole measure (`landOnWholeMeasure`);
      // rows and measures are one read each.
      final resolutions = await _landedOnWholeMeasures(
        initialResolutions(payload),
        vocabRepo: vocabRepo,
        measureRepo: measureRepo,
      );
      if (!ref.mounted) return;
      // The header opens on what the page plainly said, and unset otherwise.
      state = ImportReconciling(
        payload: payload,
        request: source,
        resolutions: resolutions,
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

  /// Resolves the line at [lineIndex] to an existing ingredient, then lands a
  /// counted line on that row's whole measure ([landOnWholeMeasure]). The match
  /// is applied before the reads, so a failed lookup cannot lose it.
  Future<void> resolveLine(
    int lineIndex,
    String ingredientId,
    String name, {
    required bool correction,
    bool created = false,
  }) async {
    final s = state;
    if (s is! ImportReconciling) return;
    final before = s.resolutions.firstWhere((r) => r.lineIndex == lineIndex);
    updateResolution(
      lineIndex,
      (r) => r.resolveToIngredient(
        ingredientId,
        name,
        correction: correction,
        created: created,
      ),
    );
    // Both keepAlive repositories are read before the first await (the
    // file's rule: `ref` does not survive this notifier's disposal).
    final vocabRepo = ref.read(ingredientRepositoryProvider);
    final measureRepo = ref.read(measureRepositoryProvider);
    final leavingId = before.chosenIngredientId;
    final read = await _rowsAndMeasures(
      {ingredientId, if (leavingId != null) leavingId},
      vocabRepo: vocabRepo,
      measureRepo: measureRepo,
    );
    if (read == null || !ref.mounted) return;
    final leavingRow = leavingId == null ? null : read.vocab[leavingId];
    final leaving = leavingRow == null
        ? null
        : wholeMeasureOf(leavingRow, read.measuresById[leavingId] ?? const []);
    updateResolution(
      lineIndex,
      (r) => landOnWholeMeasure(
        r,
        ingredient: read.vocab[ingredientId],
        measures: read.measuresById[ingredientId] ?? const [],
        leaving: leaving,
      ),
    );
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
    // An identity change (re-match, recipe link, unlink) relabels every step
    // chip pointing at this line; amount, note, drop and optional edits do not.
    // Drafts derive from the state before the change.
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
      // Only when a chip moved, so an untouched method still commits
      // byte-for-byte.
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

  /// The substitution being read through this sitting, or null. Session state,
  /// not a column.
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

  // --- the sections -------------------------------------------------------
  //
  // These edit `ImportReconciling.sections`, which `buildCommit` reads; the
  // payload is never touched.

  void _mapSections(List<ReviewGroup> Function(List<ReviewGroup>) f) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(sections: f(s.sections));
  }

  /// Renames a section. Blank clears the heading rather than storing one.
  void setSectionName(String groupId, String? name) =>
      _mapSections((g) => renameGroup(g, groupId, name));

  /// Deletes a section's heading. Its lines move into the section above (below,
  /// for the first), keeping their order and resolutions.
  void removeSection(String groupId) =>
      _mapSections((g) => removeGroup(g, groupId));

  /// Moves the line row at flat row [from] to [to] (`review_groups.dart`). A
  /// line keeps its index, which keys resolutions and step chips; only its
  /// position, committed as `sort_order`, changes.
  void moveLine(int from, int to) =>
      _mapSections((g) => moveReviewLine(g, from: from, to: to));

  /// Appends an empty section. It fills by adding a line to it.
  void addSection() =>
      _mapSections((g) => addGroup(g, id: 'g-new-${_newSectionSeq++}'));

  /// A counter, not a uuid, so widget keys stay readable in tests.
  int _newSectionSeq = 0;

  /// Mints a line the page never printed, files it into [groupId] and returns
  /// its flat index (null outside the review). The index is past the payload's
  /// last, so nothing renumbers.
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

  /// The reconciliation as it stands now, or null outside the review. The
  /// step-card host's mutators fire several times per frame, so they read
  /// through this; see `ImportMethodEditing.methodDraft`.
  ImportReconciling? reconciling() {
    final s = state;
    return s is ImportReconciling ? s : null;
  }

  /// Re-seats the review's method drafts; every step-card edit lands here
  /// through `ImportMethodEditing`.
  void setMethodDraft(List<MethodDraftStep> drafts) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(editedSteps: drafts);
  }

  // --- the header ---------------------------------------------------
  //
  // The setters' rules are the shared `RecipeHeaderEdits`; these only re-seat
  // the draft, and are no-ops outside reconciliation.

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

  /// The review's measures list, which prefills nothing (ADR-0018). A word
  /// typed here rides the draft and lands with the commit.
  @override
  void setMeasures(List<RecipeMeasure> measures) =>
      _mapHeader((h) => h.withMeasures(measures));

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
  /// null if the flow was not ready or a write failed. [issuesByLine] is the
  /// map from [importValidation] the Save button reads, so [buildCommit]
  /// enforces the same gate.
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
      // payload's own steps byte for byte.
      steps: edited == null
          ? null
          : stepsFromDrafts(edited, {
              for (final r in keptLines(s.resolutions)) r.lineIndex,
            }),
    );
    state = const ImportCommitting();
    try {
      final id = await ref.read(importRepositoryProvider).commit(payload);
      // The recipe is saved even if the user left mid-write: return the id, but
      // do not write to a disposed notifier.
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

/// The rows [ids] name and their live measures, one query each, for
/// [landOnWholeMeasure]; null when the vocabulary could not be read.
/// Best-effort: a failed read leaves lines as they arrived, and
/// `importValidation` reports the same failure with its retry.
Future<
  ({Map<String, Ingredient> vocab, Map<String, List<Measure>> measuresById})?
>
_rowsAndMeasures(
  Set<String> ids, {
  required IngredientRepository vocabRepo,
  required MeasureRepository measureRepo,
}) async {
  try {
    return (
      vocab: await vocabRepo.byIds(ids),
      measuresById: await measureRepo.measuresByIngredients(ids),
    );
  } on Object {
    return null;
  }
}

/// [landedOnWholeMeasures] over a payload's arriving [resolutions], with rows
/// and measures fetched once for the whole import.
Future<List<LineResolution>> _landedOnWholeMeasures(
  List<LineResolution> resolutions, {
  required IngredientRepository vocabRepo,
  required MeasureRepository measureRepo,
}) async {
  final ids = {
    for (final r in resolutions)
      if (r.chosenIngredientId != null) r.chosenIngredientId!,
  };
  if (ids.isEmpty) return resolutions;
  final read = await _rowsAndMeasures(
    ids,
    vocabRepo: vocabRepo,
    measureRepo: measureRepo,
  );
  if (read == null) return resolutions;
  return landedOnWholeMeasures(
    resolutions,
    vocab: read.vocab,
    measuresById: read.measuresById,
  );
}

/// The slice of the controller [importValidation] depends on (see
/// [ImportReconciling.validationKey]), so a note keystroke does not re-run it.
@riverpod
String importValidationKey(Ref ref) {
  final state = ref.watch(importControllerProvider);
  return state is ImportReconciling ? state.validationKey : '';
}

/// Per-line validity for the current reconciliation, keyed by flat line index:
/// checks each matched line's unit against its ingredient's allowed set
/// (ADR-0008) and offers valid units as chips. Drives the per-line flag, the
/// unit chips and the Save gate.
///
/// [againstLiveVocabulary] runs here, so a line matched to a since-retired row
/// reads as unmatched. Depends only on [importValidationKey]; read it with
/// `AsyncValue.value`, which keeps the last data across a refresh.
///
/// Vocab and measures are each one plain repository query. Never use the
/// per-ingredient autoDispose stream providers' `.future` here: an element
/// disposed before its first emission completes with a [StateError].
@riverpod
Future<Map<int, LineValidation>> importValidation(Ref ref) async {
  ref.watch(importValidationKeyProvider);
  final state = ref.read(importControllerProvider);
  if (state is! ImportReconciling) return const {};

  final matchedIds = {
    for (final r in state.resolutions)
      if (r.chosenIngredientId != null) r.chosenIngredientId!,
  };
  // Resolve both repositories before the first await: this autoDispose provider
  // can be disposed mid-build, after which `ref.read` throws.
  final vocabRepo = ref.read(ingredientRepositoryProvider);
  final measureRepo = ref.read(measureRepositoryProvider);
  final vocab = await vocabRepo.byIds(matchedIds);
  final measuresById = await measureRepo.measuresByIngredients(matchedIds);

  final result = <int, LineValidation>{};
  // `byIds` returns live rows only, so its keys are the liveness answer: a
  // match at a retired row becomes unmatched here, and everything downstream
  // reads the issues this loop writes.
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
          // The line's own printed unit rides along: a source-printed imprecise
          // word is admissible whatever the category.
          : acceptableUnitChips(ingredient, measures, parsedUnit: r.unit),
      unitMeasure: measureNamed(r.unit, measures),
      pieceWeightMissing: countNeedsPieceWeight(r, ingredient),
      rowIsStub: ingredient?.status == IngredientStatus.stub,
      // No extra read: the row is already in hand from the one vocab query
      // above.
      sourceLine: ingredient == null ? null : sourceProvenanceLine(ingredient),
    );
  }
  return result;
}

/// The one count of lines still needing attention, shared by the header and the
/// Save button. Falls back to the structural unresolved count until the first
/// validation lands.
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
