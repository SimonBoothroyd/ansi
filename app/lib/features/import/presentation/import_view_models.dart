/// Riverpod ViewModels for the import flow (step 8): intake → reconcile →
/// commit, held in one [ImportController] the intake and reconciliation views
/// share.
library;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/ingredient.dart';
import '../data/import_providers.dart';
import '../domain/import_repository.dart';
import '../domain/line_resolution.dart';
import '../domain/line_validation.dart';
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
    required this.servings,
  });

  final ReconciliationPayload payload;
  final List<LineResolution> resolutions;

  /// The serving count the recipe commits with — seeded from the payload
  /// (defaulting to 1 when the source was unclear, which the UI flags).
  final double servings;

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
  /// it was dropped (a dropped line reports no issues). Notes and the serving
  /// count change no line's validity, so typing a note must not re-run a vocab
  /// query per line.
  String get validationKey {
    final key = StringBuffer();
    for (final r in resolutions) {
      key
        ..write(r.lineIndex)
        ..write('|')
        ..write(r.chosenIngredientId ?? '')
        ..write('|')
        ..write(r.createStubName ?? '')
        ..write('|')
        ..write(r.unit ?? '')
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
    double? servings,
  }) => ImportReconciling(
    payload: payload,
    resolutions: resolutions ?? this.resolutions,
    servings: servings ?? this.servings,
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
class ImportController extends _$ImportController {
  @override
  ImportState build() => const ImportIdle();

  /// True while [startImport] is running. Extraction is a billed LLM call, so a
  /// double-tapped "Import" must not fire two of them.
  bool _starting = false;

  /// Runs the extract→match pipeline for [source] and moves to reconciliation.
  /// A second call while the first is in flight is a no-op.
  Future<void> startImport(ImportSource source) async {
    if (_starting) return;
    _starting = true;
    state = const ImportLoading();
    try {
      // The keepAlive repo provider, read directly after the await — never a
      // throwaway notifier ([mise-riverpod-notifier-ref-after-async]).
      final payload = await ref
          .read(importRepositoryProvider)
          .startImport(source);
      if (!ref.mounted) return;
      state = ImportReconciling(
        payload: payload,
        resolutions: initialResolutions(payload),
        servings: (payload.servingsBase ?? 1).toDouble(),
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ImportFailed('Could not import this recipe: $e');
    } finally {
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
    state = s.copyWith(
      resolutions: [
        for (final r in s.resolutions)
          if (r.lineIndex == lineIndex) update(r) else r,
      ],
    );
  }

  /// Sets the serving count the recipe commits with (min 1).
  void setServings(double servings) {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(servings: servings < 1 ? 1 : servings);
  }

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
    final payload = buildCommit(
      s.payload,
      s.resolutions,
      servingsBase: s.servings,
      issuesByLine: issuesByLine,
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
/// ONE repository query — never N round-trips down the line list, and (plan
/// 0020 **J2**) never through the per-ingredient measure STREAM providers.
/// Those are autoDispose, PowerSync's `watch` does not emit synchronously, and
/// an element disposed before its first emission completes `.future` with a
/// `StateError` — which this loader caught and turned into "no measures", so
/// "1 clove" of a garlic row that carries a `clove` measure validated against
/// an empty list and was flagged "Pick a supported unit". A plain read has no
/// element to lose. Nothing is swallowed now either: a query that genuinely
/// fails surfaces as the provider's error rather than as a screen full of
/// wrongly-flagged lines.
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
  // recompute lands), after which `ref.read` THROWS
  // ([mise-riverpod-notifier-ref-after-async]).
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
    } else if (r.createStubName != null) {
      // A create-new stub commits as a plain 'g' vocab row — validate the unit
      // against that shape (plus the always-admitted imprecise units).
      ingredient = Ingredient(
        id: 'stub:${r.lineIndex}',
        canonicalName: r.createStubName!,
        defaultUnit: g,
        status: IngredientStatus.stub,
      );
    }
    result[r.lineIndex] = LineValidation(
      issues: lineIssues(r, ingredient: ingredient, measures: measures),
      unitChoices: ingredient == null
          ? const []
          // The line's own printed unit rides along: a source-printed
          // imprecise word is admissible whatever the category (J3b).
          : acceptableUnitChips(ingredient, measures, parsedUnit: r.unit),
    );
  }
  return result;
}

/// The ONE "how many lines still want you" count — the header's "N to review"
/// and the Save button's "N line(s) need you" are the same number, read from
/// the same place (they used to be two different rules, and the header's never
/// decremented). Until the first validation lands it falls back to the
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
