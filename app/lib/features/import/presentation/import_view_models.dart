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

/// Extraction + matching is running (the fake edge function, for now).
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
    this.previewing = false,
  });

  final ReconciliationPayload payload;
  final List<LineResolution> resolutions;

  /// The serving count the recipe commits with — seeded from the payload
  /// (defaulting to 1 when the source was unclear, which the UI flags).
  final double servings;

  /// True once the user has moved from triage to the pre-commit preview (the
  /// resolutions stay live and editable behind it).
  final bool previewing;

  /// Every line resolved — the commit gate.
  bool get canCommit => allResolved(resolutions);

  /// Count of lines still needing the user (the intake→commit progress hint).
  int get unresolvedCount => resolutions.where((r) => !r.isResolved).length;

  /// The number of triage rows still asking for the user ("N to review"): a
  /// use-group counts once, regardless of how many uses it folds.
  int get reviewCount {
    final byIndex = {for (final r in resolutions) r.lineIndex: r};
    final flat = payload.flatLines;
    return groupReconUses(payload)
        .where(
          (g) => g.lineIndexes.any(
            (i) => needsReview(flat[i], byIndex[i]!),
          ),
        )
        .length;
  }

  ImportReconciling copyWith({
    List<LineResolution>? resolutions,
    double? servings,
    bool? previewing,
  }) => ImportReconciling(
    payload: payload,
    resolutions: resolutions ?? this.resolutions,
    servings: servings ?? this.servings,
    previewing: previewing ?? this.previewing,
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

@riverpod
class ImportController extends _$ImportController {
  @override
  ImportState build() => const ImportIdle();

  /// Runs the (faked) edge function for [source] and moves to reconciliation.
  Future<void> startImport(ImportSource source) async {
    state = const ImportLoading();
    try {
      // The keepAlive repo provider, read directly after the await — never a
      // throwaway notifier ([mise-riverpod-notifier-ref-after-async]).
      final payload = await ref
          .read(importRepositoryProvider)
          .startImport(source);
      state = ImportReconciling(
        payload: payload,
        resolutions: initialResolutions(payload),
        servings: (payload.servingsBase ?? 1).toDouble(),
      );
    } on Object catch (e) {
      state = ImportFailed('Could not import this recipe: $e');
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

  /// Moves from triage to the pre-commit preview. A no-op unless every line is
  /// resolved — the preview shows the recipe that would be saved.
  void showPreview() {
    final s = state;
    if (s is! ImportReconciling || !s.canCommit) return;
    state = s.copyWith(previewing: true);
  }

  /// Returns from the preview to triage (the resolutions are untouched).
  void backToTriage() {
    final s = state;
    if (s is! ImportReconciling) return;
    state = s.copyWith(previewing: false);
  }

  /// Builds the commit payload and writes it. Returns the new recipe id, or
  /// null if the flow wasn't ready / a write failed.
  Future<String?> commit() async {
    final s = state;
    if (s is! ImportReconciling || !s.canCommit) return null;
    final payload = buildCommit(
      s.payload,
      s.resolutions,
      servingsBase: s.servings,
    );
    state = const ImportCommitting();
    try {
      final id = await ref.read(importRepositoryProvider).commit(payload);
      state = ImportCommitted(id);
      return id;
    } on Object catch (e) {
      state = ImportFailed('Could not save the recipe: $e');
      return null;
    }
  }

  /// Resets the flow (e.g. after leaving the intake screen).
  void reset() => state = const ImportIdle();
}

/// Per-line validity for the current reconciliation, keyed by flat line index —
/// loads each matched line's ingredient + measures and checks its unit against
/// the ingredient's allowed set (ADR-0008), and offers that ingredient's valid
/// units as inline suggestion chips. Recomputed on every edit; the review
/// screen reads it for the per-line needs-attention flag, the unit chips, AND
/// the Save gate. Empty until reconciling.
@riverpod
Future<Map<int, LineValidation>> importValidation(Ref ref) async {
  final state = ref.watch(importControllerProvider);
  if (state is! ImportReconciling) return const {};
  final repo = ref.read(ingredientRepositoryProvider);
  final result = <int, LineValidation>{};
  for (final r in state.resolutions) {
    Ingredient? ingredient;
    var measures = const <Measure>[];
    if (r.chosenIngredientId != null) {
      ingredient = await repo.byId(r.chosenIngredientId!);
      if (ingredient != null) {
        try {
          measures = await ref.watch(
            ingredientMeasuresProvider(ingredient.id).future,
          );
        } on Object {
          // Measures unavailable → check against the catalog set only.
          measures = const [];
        }
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
          : acceptableUnitChips(ingredient, measures),
    );
  }
  return result;
}
