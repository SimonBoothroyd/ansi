/// Ingredient vocabulary lookup and editing. Pure Dart (invariant 2).
///
/// Search runs offline over the synced vocab through `searchRank`'s three
/// tiers: exact, word prefix, and a guarded typo tier that only offers rows
/// under "did you mean" (ADR-0004: nothing resolves without a person looking).
/// A rename moves the stored name and its `match_text` in one write.
library;

import 'package:meta/meta.dart';
import '../../../core/result/result.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';
import 'name_namespace.dart';

/// What a [IngredientRepository.softDelete] attempt did. Deletion is refused
/// while a live line points at the row, and the refusal carries the counts the
/// screen shows. The counted set must match migration 0041's trigger: live
/// recipe lines in live groups of live recipes, plus the week's lines.
sealed class DeleteOutcome {
  const DeleteOutcome();
}

/// The row was tombstoned.
final class Deleted extends DeleteOutcome {
  const Deleted();
}

/// Refused: [lineCount] live recipe lines across [recipeCount] recipes, and/or
/// [plannedCount] lines in the plan, still name this ingredient.
final class DeleteRefused extends DeleteOutcome {
  const DeleteRefused({
    required this.recipeCount,
    required this.lineCount,
    this.plannedCount = 0,
  });

  final int recipeCount;
  final int lineCount;

  /// Live week lines naming the row: a bare-ingredient `plan_entry` or a
  /// `week_recipe_line_override`. Counted because migration 0041 counts them,
  /// and a delete the server refused would block the sync queue.
  final int plannedCount;
}

/// Refused: the id resolves to nothing live (already deleted, never synced).
final class DeleteMissing extends DeleteOutcome {
  const DeleteMissing();
}

/// What the flesh-out form saves, as one intent applied in one transaction
/// (ADR-0011): the row's fields, density, piece weight, measures, aliases and
/// the status flip. Measure and alias ids are minted by the caller, so a draft
/// can name a row before it exists.
@immutable
class IngredientFormEdit {
  const IngredientFormEdit({
    required this.row,
    this.density = const DensityUnchanged(),
    this.serving,
    this.measuresAdded = const [],
    this.measuresRemoved = const {},
    this.aliasesAdded = const [],
    this.aliasesRemoved = const {},
    this.pieceWeight = const PieceWeightUnchanged(),
    this.markComplete = false,
  });

  /// The row's own scalar fields — the half that already went through Save.
  final IngredientEdit row;

  /// The form's draft has already applied the density's unlock or strip to
  /// `row.allowedUnits`, so this is written beside that list, not derived from
  /// it.
  final DensityChange density;

  /// The serving the label prints, kept as the row's one `serving · 2 tbsp`
  /// measure; writing one replaces the old. Null leaves the serving alone.
  final PendingMeasure? serving;

  final List<PendingMeasure> measuresAdded;
  final Set<String> measuresRemoved;
  final List<PendingAlias> aliasesAdded;
  final Set<String> aliasesRemoved;

  /// The piece weight (ADR-0015), three-valued like [density] and likewise
  /// already applied to `row.allowedUnits`.
  final PieceWeightChange pieceWeight;

  /// Save and mark in the same transaction, so a failure cannot leave the row
  /// saved but unmarked.
  final bool markComplete;
}

/// A measure the form intends to add, already carrying the id it will keep.
@immutable
class PendingMeasure {
  const PendingMeasure({
    required this.id,
    required this.label,
    required this.amount,
    this.sortOrder,
  });

  final String id;
  final String label;

  /// In the ingredient's basis unit. Refused if not positive, exactly as
  /// `addMeasure` refuses it — the contract does not soften for being batched.
  final double amount;

  /// Where the row lands in the ingredient's list; null appends it.
  final int? sortOrder;
}

/// An alias the form intends to add, already carrying its id.
@immutable
class PendingAlias {
  const PendingAlias({required this.id, required this.text});

  final String id;
  final String text;
}

/// The density, three-valued: untouched, set, or deliberately removed. The
/// removal is D4b's strip leg and the one place the allowed list shrinks.
sealed class DensityChange {
  const DensityChange();
}

class DensityUnchanged extends DensityChange {
  const DensityUnchanged();
}

class DensitySet extends DensityChange {
  const DensitySet(this.gPerMl);

  final double gPerMl;
}

class DensityCleared extends DensityChange {
  const DensityCleared();
}

/// The piece weight change (ADR-0015): untouched, set, or removed. Removal
/// strips `piece` from the admission list in the same write.
sealed class PieceWeightChange {
  const PieceWeightChange();
}

class PieceWeightUnchanged extends PieceWeightChange {
  const PieceWeightUnchanged();
}

class PieceWeightSet extends PieceWeightChange {
  const PieceWeightSet(this.amount);

  /// In the ingredient's basis unit. Must be positive, exactly as a density
  /// must.
  final double amount;
}

class PieceWeightCleared extends PieceWeightChange {
  const PieceWeightCleared();
}

/// The editable facts of one vocab row. Every field replaces, not patches: a
/// null [macros] is a deliberate clear, which sends a `complete` row back to
/// `stub`. [source] is the one exception.
class IngredientEdit {
  const IngredientEdit({
    required this.canonicalName,
    required this.defaultUnit,
    required this.macrosBasis,
    required this.allowedUnits,
    this.category,
    this.macros,
    this.source,
    this.sourceLabel,
    this.sourceScore,
  });

  final String canonicalName;
  final Unit defaultUnit;
  final MacrosBasis macrosBasis;

  /// The explicit ADR-0008 admission list. Never silently recomputed — the
  /// form is the one surface that owns it.
  final Set<Unit> allowedUnits;

  final String? category;
  final Macros? macros;

  /// The provenance's name and match score, written beside [source] and
  /// patch-shaped like it.
  final String? sourceLabel;
  final double? sourceScore;

  /// A provenance to stamp (`off:<barcode>`), or null to keep the stored one.
  /// Patch-shaped because a form never clears provenance; written in the same
  /// statement as the macros it explains (`applyDraft`).
  final String? source;
}

/// What a vocab search found. `guessed` is true only when the exact and prefix
/// tiers were empty and the typo tier answered; the picker then shows the rows
/// under `DID YOU MEAN`. Never true for an empty query.
typedef IngredientMatches = ({List<Ingredient> rows, bool guessed});

/// The refusal [IngredientRepository.saveForm] returns when the name or an
/// alias is already a live name in this household. No unique index backs this,
/// by design: two offline devices can mint the same row and must converge, so
/// the app refuses the duplicate instead (see `0019_shopping_week.sql`).
Failure nameTakenFailure(String existingName) =>
    Failure('ingredient/name_taken', nameTakenMessage(existingName));

abstract interface class IngredientRepository {
  /// Ingredients whose name or aliases match [query], best first, capped at
  /// [limit]; an empty [query] returns the first [limit] rows. Ordering is
  /// `searchRank`'s: tier, then score, then shorter name. The typo tier runs
  /// only when the others find nothing ([IngredientMatches]`.guessed`).
  Future<IngredientMatches> search(String query, {int limit = 30});

  /// The ingredients most recently used in a recipe line or manual top-up,
  /// newest first. Empty when nothing has been used.
  Future<List<Ingredient>> recentlyUsed({int limit = 8});

  /// The live vocab row with [id], or null when missing or tombstoned.
  Future<Ingredient?> byId(String id);

  /// [byId] as a watched query, for a screen that stays open on one row.
  Stream<Ingredient?> watchIngredient(String id);

  /// The live vocab rows for [ids], keyed by id, in one query. Missing or
  /// tombstoned ids are absent.
  Future<Map<String, Ingredient>> byIds(Set<String> ids);

  /// Stores [gPerMl] as the density (ADR-0008) and unions the units it unlocks
  /// into the explicit `allowed_units` in the same write. Returns the updated
  /// row, or null when [ingredientId] does not resolve. Throws [ArgumentError]
  /// for a non-positive or NaN [gPerMl] (invariant 3).
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl);

  /// Deletes the density and, in the same write, removes the units only it
  /// admitted (`densityStrippedUnits`). The one place the admission list
  /// shrinks; ADR-0009's union-never-remove rule governs backfills, not this.
  /// Existing lines are never rewritten: one still saying a stripped unit
  /// degrades to the `unitNotAllowed` flag.
  ///
  /// Returns the updated row (unchanged when there was no density), or null
  /// when [ingredientId] does not resolve.
  Future<Ingredient?> clearDensity(String ingredientId);

  /// Stores [amount] as what one piece weighs in the basis unit (ADR-0015),
  /// unions `piece` into `allowed_units` on a count-default row in the same
  /// write, and sets `piece_source` to `manual`. Returns the updated row, or
  /// null when [ingredientId] does not resolve. Throws [ArgumentError] for a
  /// non-positive or NaN [amount] (invariant 3).
  ///
  /// The quantity sheet calls this on tap; the form lands the same change
  /// through [saveForm].
  Future<Ingredient?> setPieceWeight(String ingredientId, double amount);

  /// Deletes the piece weight and, in the same write, removes `piece` from the
  /// admission list (`pieceStrippedUnits`); the mirror of [clearDensity]. Lines
  /// are never rewritten, and a piece-default row becomes a stranded default
  /// the form refuses to save. Returns the updated row (unchanged when nothing
  /// to delete), or null when [ingredientId] does not resolve.
  Future<Ingredient?> clearPieceWeight(String ingredientId);

  /// `Not this food`: undoes a USDA prefill in one write. The density goes
  /// through [clearDensity]'s strip, the macros go, `source` becomes
  /// [usdaDeclinedSource] and the row is a `stub`. [Ingredient.sourceLabel]
  /// survives so the form can name the refused food; the score is cleared.
  ///
  /// Only for a row whose `source` still starts with `usda_fdc:`. Returns null,
  /// writing nothing, when [ingredientId] does not resolve or the row is not
  /// USDA-filled. A later pick saved with the form overwrites the declined
  /// stamp ([IngredientEdit.source]).
  Future<Ingredient?> declineUsdaPrefill(String ingredientId);

  // --- The manager's write half (step 8.5) -----------------------------------

  /// The whole live vocabulary, ordered by canonical name, as a watched query.
  /// Carries the same `measureCount` the picker rows do.
  Stream<List<Ingredient>> watchVocabulary();

  /// How many live rows still read `stub` — the Library menu's badge. Watched
  /// so confirming one decrements it without a refresh.
  Stream<int> watchStubCount();

  /// How many live rows the vocabulary holds, for the Library card.
  Stream<int> watchVocabularyCount();

  /// The household's distinct live categories, alphabetical, watched. There is
  /// no category table; blank values are excluded.
  Stream<List<String>> watchCategories();

  /// Applies a whole form in one transaction. A null [ingredientId] creates the
  /// row, with its measures and aliases, in that transaction.
  ///
  /// Returns [Ok] with the row as written (`Ok(null)` if an existing row is
  /// gone), or [Err] with [nameTakenFailure] when the name or an alias is
  /// already taken. That check runs inside the write transaction, so a sync
  /// cannot race past the form's pre-check. Programming errors (blank name,
  /// non-positive measure amount, alias with no identity word) throw
  /// [ArgumentError]. Nothing is written in either case.
  Future<Result<Ingredient?>> saveForm(
    String? ingredientId,
    IngredientFormEdit edit,
  );

  /// Every live name in the household, canonical names and aliases, as one
  /// namespace, in one read.
  Future<List<NameEntry>> nameIndex();

  /// Returns a `complete` row to `stub` — confirm is reversible. The
  /// macros stay stored; the row simply stops counting until re-confirmed.
  Future<Ingredient?> unconfirm(String ingredientId);

  /// Soft-deletes the vocab row — but only when no live recipe line points at
  /// it. See [DeleteOutcome].
  Future<DeleteOutcome> softDelete(String ingredientId);

  /// The ingredient's live aliases, oldest first, watched.
  Stream<List<IngredientAlias>> watchAliases(String ingredientId);
}
