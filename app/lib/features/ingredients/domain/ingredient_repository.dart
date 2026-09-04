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
  });

  final String canonicalName;
  final Unit defaultUnit;
  final MacrosBasis macrosBasis;

  /// The explicit ADR-0008 admission list. Never silently recomputed — the
  /// form is the one surface that owns it.
  final Set<Unit> allowedUnits;

  final String? category;
  final Macros? macros;

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

  /// Creates a stub vocab row named [name] and returns it. The picker's
  /// "can't find it? add new" affordance, and the add sheet's create.
  ///
  /// Defaults to a bare manual stub — no density, no macros, which is what
  /// keeps it out of conversions until it is fleshed out (invariant 3). A
  /// prefilling source overrides them:
  /// - [source] is the row's provenance for the `source` column: `manual`,
  ///   or `off:<barcode>` from a barcode draft's `sourceValue` (D1).
  /// - [macros]/[macrosBasis] are what that source supplied, stored in the
  ///   basis the label read them in rather than converted (7.7). Null macros
  ///   stay null — a source with no panel writes no numbers, never zeros.
  ///
  /// Never a density: a barcode carries none, and one is not derivable from
  /// a pack size. The row is a `stub` whatever arrives with it — machine
  /// numbers do not complete an ingredient (D5: confirming is a human act).
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  });

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

  /// Writes a USDA probe result into the row's NULL fields — plan 0020
  /// **D7b**, the local half of "enrichment should not wait for sync".
  ///
  /// Two guards, both load-bearing, both mirroring the server trigger's WHEN
  /// clause (migrations 0014/0015) so the two writes can race harmlessly:
  /// - the row must still be a **`stub`**, and
  /// - it must be **bare** — no density and no macros. A row someone has
  ///   filled in is never overwritten by a trigram guess.
  ///
  /// Both re-checked inside the write, not just by the caller: the row may
  /// have changed between the probe and the apply (another device, or the
  /// server trigger landing first). Returns null when either guard fails, or
  /// when the id doesn't resolve.
  ///
  /// A landing density also extends `allowed_units` with what it unlocks, in
  /// the same write — the same rule [setDensity] follows, because it is the
  /// same event (ADR-0009).
  ///
  /// [sourceLabel] and [sourceScore] — the food's name and the score that
  /// earned it (plan 0027 U-D1) — are written in the same statement as
  /// [source], exactly as the trigger writes them, so a row never carries a
  /// stamp without the name behind it.
  ///
  /// **The declined guard** (U-D2/U-D3): a row whose `source` is
  /// [usdaDeclinedSource] is refused too — a person said "not this food",
  /// and no automatic path re-fills it. [explicitPick] — a candidate a
  /// person chose from the *Choose another* sheet — lifts exactly two
  /// things: that guard, and the bare-row guard **where the numbers are the
  /// prefill's own** (`source` still `usda_fdc:`; both prefill writers are
  /// fill-null-only, so on such a row they authored both numbers). Then the
  /// old fill is replaced whole — density (its D4b strip applied, the new
  /// density's unlock unioned), macros, stamp, label, score — and the row
  /// reads `stub` whatever it was. A row with numbers a person supplied is
  /// still never overwritten, pick or no pick.
  ///
  /// The row stays `stub`: a machine's numbers never complete an ingredient
  /// (D5, and the trigger's own contract).
  Future<Ingredient?> applyUsdaProbe(
    String ingredientId, {
    required String source,
    String? sourceLabel,
    double? sourceScore,
    double? densityGPerMl,
    Macros? macros,
    bool explicitPick = false,
  });

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
  /// trigger's WHEN clause (0015) lists the sources it may refill — `manual`
  /// is one — and `usda_declined` is deliberately not. Declining once means
  /// the next rename leaves the row alone; only an explicit pick
  /// ([applyUsdaProbe] with `explicitPick`) writes over it.
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
  /// form's category dropdown (plan 0020 **F3**).
  ///
  /// The vocabulary *is* the category list: there is no separate table, and
  /// inventing one would leave two places to disagree about whether "produce"
  /// exists. Watched, so a category typed on one row is offered on the next
  /// without a refresh. Blank and whitespace-only values are excluded — they
  /// are what free text left behind, and they are not a category.
  Stream<List<String>> watchCategories();

  /// Applies [edit] to [ingredientId] in one write and returns the updated
  /// row (null when the id doesn't resolve).
  ///
  /// Two things happen here that nowhere else does:
  /// - **A rename rewrites `match_text`** through `normalizeMatchText`, the
  ///   server's own phrase rules (plan 0020 D6). Leaving the old value would
  ///   be a silent matching regression — the next import searches for a name
  ///   nothing carries.
  /// - **Clearing the macros of a `complete` row returns it to `stub`** (D5):
  ///   a row is never left asserting a number it no longer has. Filling them
  ///   in does NOT promote — that takes [confirmStub], a human act.
  Future<Ingredient?> saveEdit(String ingredientId, IngredientEdit edit);

  /// Flips a `stub` to `complete` — the human confirm of D5.
  ///
  /// Gated on macros being present (with their basis); density is NOT
  /// required, because an ingredient whose lines only ever speak its own
  /// basis family never needs one. Returns null when the id doesn't resolve;
  /// throws [StateError] when the row has no macros — the CTA is disabled
  /// there, and the rule holds at the repository too.
  Future<Ingredient?> confirmStub(String ingredientId);

  /// Returns a `complete` row to `stub` — confirm is reversible (D5). The
  /// macros stay stored; the row simply stops counting until re-confirmed.
  Future<Ingredient?> unconfirm(String ingredientId);

  /// Live recipe lines naming [ingredientId], as (recipes, lines). The
  /// delete guard's evidence, readable on its own so a screen can warn before
  /// the user commits to the action.
  Future<({int recipeCount, int lineCount})> recipeReferences(
    String ingredientId,
  );

  /// Soft-deletes the vocab row — but only when no live recipe line points at
  /// it (the signed rule, plan 0020's open question). See [DeleteOutcome].
  Future<DeleteOutcome> softDelete(String ingredientId);

  /// The ingredient's live aliases, oldest first.
  Future<List<IngredientAlias>> aliases(String ingredientId);

  /// Adds a `manual` alias, its `match_text` written with the server's phrase
  /// rules so the cascade can find it. A duplicate (same normalized text on
  /// the same ingredient) is a no-op returning the existing row — local
  /// tables are VIEWS, so this is an existence check plus a plain INSERT,
  /// never an UPSERT.
  ///
  /// Throws [ArgumentError] for an alias that normalizes to nothing.
  Future<IngredientAlias> addAlias(String ingredientId, String text);

  /// Soft-deletes one alias.
  Future<void> removeAlias(String aliasId);
}
