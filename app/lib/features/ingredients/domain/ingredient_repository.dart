/// Ingredient vocabulary lookup and editing — PURE DART (invariant 2).
///
/// The picker searches the local synced vocab offline through `searchRank`'s
/// three tiers — exact, word prefix, and a guarded typo tier that only ever
/// *offers* rows to a human under a "did you mean" header. ADR-0004 still
/// holds: no index, no model, no reference set on the device, and nothing
/// resolved without someone looking. Step 7.7 added the recents feed
/// and the add-new stub path; step 8.5 adds the write half the manager needs
/// — rename (which rewrites `match_text`), the fact edits, the explicit
/// `allowed_units` list, aliases, the D5 confirm/unconfirm pair, and the
/// guarded soft-delete.
library;

import 'package:meta/meta.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'ingredient.dart';

/// What a [IngredientRepository.softDelete] attempt did.
///
/// Deletion is guarded, not merely audited: a `recipe_line_item`'s
/// `ingredient_id` is NOT NULL by design (0014's commit contract), so a row a
/// live line points at can never go. The refusal carries the counts the
/// screen shows ("used by 3 recipes") — a refusal a user can act on beats an
/// error they can't.
sealed class DeleteOutcome {
  const DeleteOutcome();
}

/// The row was tombstoned.
final class Deleted extends DeleteOutcome {
  const Deleted();
}

/// Refused: [lineCount] live recipe lines across [recipeCount] recipes still
/// name this ingredient.
final class DeleteRefused extends DeleteOutcome {
  const DeleteRefused({required this.recipeCount, required this.lineCount});

  final int recipeCount;
  final int lineCount;
}

/// Refused: the id resolves to nothing live (already deleted, never synced).
final class DeleteMissing extends DeleteOutcome {
  const DeleteMissing();
}

/// What the flesh-out form asks for, as ONE intent (plan 0029 **W3**,
/// `docs/decisions/0011-one-save-one-write.md`).
///
/// The form writes once, on Save, so everything it changed has to travel
/// together: the row's own fields, the density, the measures added and
/// removed, the aliases, and what a bare count means. `saveForm` applies the
/// lot in a single transaction, which is what makes partial success stop
/// being representable — the old sheet's `create()` ran four repository calls
/// under one error guard and could leave a row without its pack measure.
///
/// **Ids are minted by the caller.** Measures and aliases already carry
/// client-generated uuids, so a draft can name a row before it exists and the
/// save inserts it under that id. That is also what lets the form work with
/// no ingredient id at all (lane C).
@immutable
class IngredientFormEdit {
  const IngredientFormEdit({
    required this.row,
    this.density = const DensityUnchanged(),
    this.measuresAdded = const [],
    this.measuresRemoved = const {},
    this.aliasesAdded = const [],
    this.aliasesRemoved = const {},
    this.defaultMeasure = const DefaultMeasureUnchanged(),
    this.markComplete = false,
  });

  /// The row's own scalar fields — the half that already went through Save.
  final IngredientEdit row;

  /// **The form owns the admission set, and it owns the density with it.**
  /// The old `setDensity` unioned `allowed_units` itself and the form's chips
  /// followed the row afterwards; under one write the draft has already
  /// applied that unlock (or strip), so `row.allowedUnits` is authoritative
  /// and this is written beside it rather than deriving it.
  final DensityChange density;

  final List<PendingMeasure> measuresAdded;
  final Set<String> measuresRemoved;
  final List<PendingAlias> aliasesAdded;
  final Set<String> aliasesRemoved;

  /// Seam D1's "Counts as" — three-valued, because *unset* ("Ask me each
  /// time") is a real answer and distinct from "not touched".
  final DefaultMeasureChange defaultMeasure;

  /// `Mark complete` is a save-and-mark combination (owner, 2026-09-03), and
  /// it used to be two writes — a failure between them left the row saved and
  /// not marked, under an error implying neither. One transaction now.
  final bool markComplete;
}

/// A measure the form intends to add, already carrying the id it will keep.
@immutable
class PendingMeasure {
  const PendingMeasure({
    required this.id,
    required this.label,
    required this.amount,
  });

  final String id;
  final String label;

  /// In the ingredient's basis unit. Refused if not positive, exactly as
  /// `addMeasure` refuses it — the contract does not soften for being batched.
  final double amount;
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

/// "Counts as", three-valued for the same reason: `DefaultMeasureSet(null)`
/// is the household choosing *Ask me each time*, which is not the same as
/// never having been asked.
sealed class DefaultMeasureChange {
  const DefaultMeasureChange();
}

class DefaultMeasureUnchanged extends DefaultMeasureChange {
  const DefaultMeasureUnchanged();
}

class DefaultMeasureSet extends DefaultMeasureChange {
  const DefaultMeasureSet(this.measureId);

  final String? measureId;
}

/// The editable facts of one vocab row — everything the flesh-out form saves
/// in a single write. Every field is a replacement, not a patch: the form
/// always holds the whole row, and a null [macros] is a deliberate clear
/// (which sends a `complete` row back to `stub` — D5's reversibility).
/// [source] is the one exception, and says why.
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

  /// What the provenance is called and how sure the match was — written beside
  /// [source] and patch-shaped for the same reason. A USDA pick fills these
  /// into the draft rather than writing them itself, so the food that filled a
  /// row and the numbers it filled land together.
  final String? sourceLabel;
  final double? sourceScore;

  /// A provenance to stamp (`off:<barcode>`), or null to keep the stored one.
  ///
  /// Patch-shaped where every other field replaces, because provenance is
  /// never *cleared* by a form: it records where numbers came from, and the
  /// only writer is a barcode scan on the form landing on a row that had no
  /// source yet (plan 0025 #8, `applyDraft`). Written in the same statement as
  /// the macros it explains, so a row never carries one without the other.
  final String? source;
}

/// What a vocab search found — and whether the phone had to **guess** to find
/// it.
///
/// `guessed` is true only when nothing was spelled right: the exact and prefix
/// tiers came back empty and the typo tier answered instead. The picker renders
/// those rows under a `DID YOU MEAN` header, because tier 2 is retrieval for a
/// human to pick, never a resolution. It is never true for a browse (empty
/// query) and never true when a single spelled hit exists — a guess is the
/// whole list or it is absent.
typedef IngredientMatches = ({List<Ingredient> rows, bool guessed});

abstract interface class IngredientRepository {
  /// Ingredients whose name/aliases match [query], best first, capped at
  /// [limit]. Empty [query] → the first [limit] ingredients (so the picker has
  /// something to show unfiltered).
  ///
  /// Ordering is `searchRank`'s and nothing else's: the tier decides first (an
  /// exact hit outranks a prefix hit outranks a guess, whatever the scores
  /// say), then the score, then the shorter name. The typo tier runs only when
  /// the other two find nothing at all, and says so through
  /// [IngredientMatches]`.guessed`.
  Future<IngredientMatches> search(String query, {int limit = 30});

  /// The ingredients most recently used in a recipe line or manual shopping
  /// top-up, newest first — the picker's "Recent" section (7.7). Empty when
  /// nothing has been used yet (the picker then falls back to [search]).
  Future<List<Ingredient>> recentlyUsed({int limit = 8});

  /// The live vocab row with [id], or null when it doesn't exist (or is
  /// tombstoned). Resolves an ingredient a caller only knows by reference —
  /// e.g. the edit-top-up sheet filtering its unit picker.
  Future<Ingredient?> byId(String id);

  /// The live vocab rows for [ids], keyed by id — missing/tombstoned ids are
  /// simply absent. One query for a whole set: the import review validates
  /// every line's unit against its ingredient, and doing that a row at a time
  /// is a DB round-trip per line on every edit.
  Future<Map<String, Ingredient>> byIds(Set<String> ids);

  /// Stores [gPerMl] as the ingredient's density — the single volume⇄mass
  /// fact (ADR-0008; both entry styles resolve to this one number) — and
  /// extends its explicit `allowed_units` with the units the density
  /// unlocks, in the same write (the stored list is never silently
  /// recomputed; a density's arrival is the one explicit extension).
  /// Returns the updated row, or null when [ingredientId] doesn't resolve.
  ///
  /// Throws [ArgumentError] for a non-positive/NaN [gPerMl] — a zero density
  /// would fabricate Infinity conversions (invariant 3).
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl);

  /// Deletes the ingredient's density and, **in the same write**, removes the
  /// units that density was the only reason to admit
  /// (`densityStrippedUnits`) — plan 0020 **D4b**.
  ///
  /// This is the one place the admission list ever shrinks. ADR-0009's
  /// union-never-remove rule governs backfills and reseeds, where the arriving
  /// set is a *default* and the stored list is the user's; here the removed
  /// units were **derived from the number being deleted**, so leaving them
  /// would let a line say `cup` with nothing left to convert it. The basis
  /// family and the default unit's own family survive — they never needed a
  /// density.
  ///
  /// **Existing lines are never rewritten.** A recipe line already saying a
  /// stripped unit keeps saying it and degrades to the ordinary
  /// `unitNotAllowed` flag on the import review — the same honest refusal any
  /// other out-of-set unit gets. Silently rewriting someone's line to a unit
  /// they did not choose would be the invented number this app refuses.
  ///
  /// Returns the updated row, or null when [ingredientId] doesn't resolve. A
  /// no-op (returning the row unchanged) when there is no density to delete.
  Future<Ingredient?> clearDensity(String ingredientId);

  /// Removes `piece` from the row's explicit admission list — the answer to
  /// the measures editor's "you added a measure, still offer piece?" question
  /// (plan 0022 / ADR-0010).
  ///
  /// `piece` means "a whole one of these, and we have nothing better to call
  /// it". Once a measure names the thing, offering both makes a saved line
  /// ambiguous — was `1 piece` a clove or a bulb? — and nothing downstream can
  /// honestly resolve it. So the admission comes out, which is a **removal**
  /// from a list the household owns and therefore only ever happens because
  /// they were asked (the second removal leg in the model, beside
  /// [clearDensity]; ADR-0009 rule 3 still forbids a *backfill* from removing).
  ///
  /// A row still on the derived fallback is materialized first, so there is an
  /// explicit list to remove from. Idempotent: a row that does not admit
  /// `piece` comes back unchanged. Returns null when [ingredientId] doesn't
  /// resolve.
  ///
  /// Never automatic in reverse: deleting the last measure does **not** put
  /// `piece` back. It becomes an unselected chip in the flesh-out form's
  /// admission section again, one tap from returning.
  Future<Ingredient?> stopOfferingPiece(String ingredientId);

  /// Sets what a bare COUNT of this ingredient means — "2 onions" is two
  /// `onion, medium` ([Ingredient.defaultMeasureId], 0023 / seam D1). A null
  /// [measureId] clears it back to "ask me each time".
  ///
  /// It is a **stated fact**, so it saves the moment it is picked, like the
  /// measures editor's own writes — not on a form's Save. Clearing it never
  /// touches the measure itself: the row keeps every label it had, and only
  /// stops having a preferred one.
  ///
  /// [measureId] must name a LIVE measure of this same ingredient; the
  /// server refuses anything else outright (a "1 onion" silently counted as
  /// a clove is the one lie this column could tell), and so does this. Throws
  /// [ArgumentError] when it doesn't resolve. Returns the updated row, or
  /// null when [ingredientId] doesn't resolve.
  Future<Ingredient?> setDefaultMeasure(String ingredientId, String? measureId);

  /// *Not this food* — undoes a USDA prefill in ONE write (plan 0027
  /// **U-D2**): the density goes through the same strip [clearDensity] runs
  /// (D4b — the units it alone unlocked come out), the macros go, and
  /// `source` becomes [usdaDeclinedSource]. The row is a `stub` afterwards
  /// (a row with no macros never asserts `complete`, D5), and
  /// [Ingredient.sourceLabel] SURVIVES so the form can name the food that
  /// was refused; the score is cleared with the match it described.
  ///
  /// Exactly what the prefill wrote comes out, because on a `usda_fdc:` row
  /// both prefill writers are fill-null-only on a bare stub — so the prefill
  /// is the author of both numbers. Offered only while `source` still starts
  /// with `usda_fdc:`: a row a human has since re-sourced is the human's.
  /// Returns null when [ingredientId] doesn't resolve or the row is not a
  /// USDA-filled one (nothing written).
  ///
  /// Why a new source value rather than a reset to `manual`: the rename
  /// trigger's WHEN clause (0015) listed the sources it could refill —
  /// `manual` among them — and `usda_declined` was deliberately not, so
  /// declining once meant the next rename left the row alone. 0029 dropped
  /// that trigger; no rename refills anything now. The value stays because it
  /// is still how a row says "not from USDA", and only a food a person picks
  /// themselves — saved with the form, which stamps [IngredientEdit.source]
  /// in the same write as the numbers it explains — writes over it.
  Future<Ingredient?> declineUsdaPrefill(String ingredientId);

  // --- The manager's write half (step 8.5) -----------------------------------

  /// The whole live vocabulary, canonical-name ordered, as a watched query —
  /// the manager list, which must re-render when a sync (or this device's own
  /// edit) changes a row. Carries the same `measureCount` the picker rows do.
  Stream<List<Ingredient>> watchVocabulary();

  /// How many live rows still read `stub` — the Library menu's badge. Watched
  /// so confirming one decrements it without a refresh.
  Stream<int> watchStubCount();

  /// How many live rows the vocabulary holds — the Library's Ingredients card
  /// says what is on that shelf, the way a book says "42 recipes" (0028 E5).
  /// A count, not the list: the Library must not carry 300 rows to print one
  /// number.
  Stream<int> watchVocabularyCount();

  /// The household's distinct live categories, alphabetical — the flesh-out
  /// form's category dropdown.
  ///
  /// The vocabulary *is* the category list: there is no separate table, and
  /// inventing one would leave two places to disagree about whether "produce"
  /// exists. Watched, so a category typed on one row is offered on the next
  /// without a refresh. Blank and whitespace-only values are excluded — they
  /// are what free text left behind, and they are not a category.
  Stream<List<String>> watchCategories();

  /// Applies a whole form in ONE transaction: the row's fields, the density,
  /// measures added and removed, aliases, "Counts as", and — when
  /// [IngredientFormEdit.markComplete] — the status flip.
  ///
  /// **A null [ingredientId] creates the row** (plan 0029 **C1**). That is
  /// the whole reason the form defers: with nothing written until Save, a
  /// form with no row yet is coherent, and its children — measures, aliases —
  /// are inserted in the same transaction as the row they belong to. It is
  /// also what lets the New-ingredient sheet stop existing, since its only
  /// remaining job was to be the stage where nothing has been written.
  ///
  /// Returns the row as the write left it, or null if an existing row is
  /// gone. Throws [ArgumentError] on the same contracts the individual writes
  /// throw on: a blank name, a non-positive measure amount, an alias with no
  /// identity word. Nothing is written when it throws.
  Future<Ingredient?> saveForm(String? ingredientId, IngredientFormEdit edit);

  /// Returns a `complete` row to `stub` — confirm is reversible (D5). The
  /// macros stay stored; the row simply stops counting until re-confirmed.
  Future<Ingredient?> unconfirm(String ingredientId);

  /// Soft-deletes the vocab row — but only when no live recipe line points at
  /// it (the signed rule, plan 0020's open question). See [DeleteOutcome].
  Future<DeleteOutcome> softDelete(String ingredientId);

  /// The ingredient's live aliases, oldest first.
  Future<List<IngredientAlias>> aliases(String ingredientId);
}
