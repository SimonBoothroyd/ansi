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
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
import '../domain/method_draft_bridge.dart';
import '../domain/reconciliation_payload.dart';

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
class ImportLoading extends ImportState {
  const ImportLoading();
}

/// The payload is back; the user is resolving lines. Immutable — every edit
/// produces a new instance so the reconciliation view rebuilds.
class ImportReconciling extends ImportState {
  const ImportReconciling({
    required this.payload,
    required this.resolutions,
    required this.header,
    this.editedSteps,
  });

  final ReconciliationPayload payload;
  final List<LineResolution> resolutions;

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
  }) => ImportReconciling(
    payload: payload,
    resolutions: resolutions ?? this.resolutions,
    header: header ?? this.header,
    editedSteps: editedSteps ?? this.editedSteps,
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
  ImportState build() => const ImportIdle();

  /// True while [startImport] is running. Extraction is a billed LLM call, so a
  /// double-tapped "Import" must not fire two of them.
  bool _starting = false;

  /// Runs the extract→match pipeline for [source] and moves to reconciliation.
  /// A second call while the first is in flight is a no-op.
  Future<void> startImport(
    ImportSource source, {
    String? bookId,
    String? sectionId,
  }) async {
    if (_starting) return;
    _starting = true;
    state = const ImportLoading();
    try {
      // Both keepAlive repositories are resolved BEFORE the first await: this
      // notifier can be disposed across the gap, and `ref` goes with it.
      final importRepo = ref.read(importRepositoryProvider);
      final bookRepo = ref.read(bookRepositoryProvider);
      final payload = await importRepo.startImport(source);
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
      _starting = false;
    }
    // OUTSIDE the try: spending the curated defaults is a courtesy on top of a
    // successful import (seam D2), and a vocab read that cannot answer must
    // never turn a recipe that arrived into "could not import this recipe".
    // It no-ops unless the state above is a reconciliation.
    await spendDefaultMeasures();
  }

  /// Writes each matched line's curated default measure onto its resolution —
  /// seam **D2**, the one moment the fact is spent.
  ///
  /// It runs where the resolutions are BUILT (on arrival, and again after a
  /// re-match), never inside `importValidation`: a validation pass has to stay
  /// a pure read, or the map that gates Save starts mutating the state it is
  /// validating. What it writes is the measure's LABEL — the same token a
  /// tapped chip writes — so nothing downstream learns a new word.
  ///
  /// Idempotent by construction: once the label is on the line,
  /// [arrivalMeasure] sees an acceptable unit and answers null, and so it does
  /// for any unit the user picked themselves.
  Future<void> spendDefaultMeasures() async {
    final before = state;
    if (before is! ImportReconciling) return;
    final matchedIds = {
      for (final r in before.resolutions)
        if (!r.isDropped && r.chosenIngredientId != null) r.chosenIngredientId!,
    };
    if (matchedIds.isEmpty) return;
    final Map<String, Ingredient> vocab;
    final Map<String, List<Measure>> measuresById;
    try {
      // Both repositories are resolved BEFORE the first await and read straight
      // off their keepAlive providers — never a stream provider, and never
      // through a `ref` the async gap may have disposed.
      final vocabRepo = ref.read(ingredientRepositoryProvider);
      final measureRepo = ref.read(measureRepositoryProvider);
      vocab = await vocabRepo.byIds(matchedIds);
      measuresById = await measureRepo.measuresByIngredients(matchedIds);
    } on Object {
      // A vocab read that cannot answer simply spends no default: the lines
      // keep their printed units and their honest flags. Never a guess.
      return;
    }
    if (!ref.mounted) return;
    // Re-read: the user may have edited (or left) while the vocab loaded.
    final s = state;
    if (s is! ImportReconciling) return;
    var changed = false;
    final next = <LineResolution>[];
    for (final r in s.resolutions) {
      final ingredient = r.isDropped ? null : vocab[r.chosenIngredientId];
      if (ingredient == null) {
        next.add(r);
        continue;
      }
      final measure = arrivalMeasure(
        ingredient,
        measuresById[ingredient.id] ?? const [],
        unit: r.unit,
      );
      if (measure == null) {
        next.add(r);
        continue;
      }
      changed = true;
      next.add(r.applyDefaultUnit(measure.label));
    }
    if (changed) state = s.copyWith(resolutions: next);
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
    var after = update(before);
    final rematched = after.chosenIngredientId != before.chosenIngredientId;
    if (rematched && before.unitFromDefault) {
      // The word on the line was OURS, not the source's, so a new identity
      // gets the printed one back before its own default is spent (D2). Left
      // alone, a pepper's `pepper, medium` would follow the line onto broccoli
      // and be flagged there as if the recipe had said it.
      after = after.restorePrintedUnit(s.payload.flatLines[lineIndex].raw.unit);
    }
    state = s.copyWith(
      resolutions: [
        for (final r in s.resolutions)
          if (r.lineIndex == lineIndex) after else r,
      ],
    );
    if (rematched) unawaited(spendDefaultMeasures());
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
  void reset() => state = const ImportIdle();
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
/// It is deliberately NOT recomputed on every controller change: it depends on
/// [importValidationKey], so editing a note or the servings leaves the cached
/// map alone. Views must read it with `AsyncValue.value` (which keeps the last
/// data across a refresh), never a data-only view that goes null mid-recompute.
///
/// The whole import's vocab and the whole import's measures are each fetched in
/// ONE repository query — never N round-trips down the line list, and never
/// through the per-ingredient measure STREAM providers. Those are autoDispose,
/// PowerSync's `watch` does not emit synchronously, and an element disposed
/// before its first emission completes `.future` with a `StateError` — which
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
  for (final r in state.resolutions) {
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
