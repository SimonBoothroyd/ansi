/// Probe-and-apply: the D7b enrichment that does not wait for sync.
///
/// One function, three callers — the manager's add sheet, the picker's
/// add-new, and the flesh-out form's "Look up in USDA" button — so there is
/// one answer to "what does enriching an ingredient mean" rather than three
/// that drift.
///
/// **Bare stubs only, NULL fields only.** The apply refuses any row that is
/// not a `stub`, and any row that already carries a density or a macro panel.
/// That is not caution for its own sake: it is exactly the guard the server
/// trigger's WHEN clause enforces (`density_g_per_ml is null and macros is
/// null`, migrations 0014/0015), and matching it is what makes the two safe
/// to race. See 0016's header for the full argument; the short version is
/// that both sides fill only nulls, both read the same `usda_probe()` with
/// the same total ordering, so whichever lands first the row converges on the
/// same values — and neither promotes it to `complete`, which stays a human
/// act (D5).
///
/// **Nothing here throws.** A probe that cannot reach the server returns
/// null, and this returns null in turn: the trigger will still catch the row
/// when it uploads, so there is nothing to raise an error about.
library;

import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/normalize.dart';
import '../domain/usda_probe.dart';

/// What a probe-and-apply did — the states the copy has to explain.
enum UsdaEnrichment {
  /// The row was enriched here and now: fields written, source stamped.
  applied,

  /// The probe answered, but with nothing worth copying (a name match
  /// carrying neither a density nor a panel).
  nothingToCopy,

  /// No confident candidate — or no way to ask (offline, no backend). The
  /// caller cannot distinguish these, and must not: the trigger is still
  /// running either way.
  noAnswer,

  /// The row is not a bare stub, so there was nothing to fill in. A fleshed
  /// out or confirmed row is never re-probed — that is the rule that stops a
  /// trigram guess from overwriting numbers a human stood behind.
  notBare,

  /// A person said "not this food" (plan 0027 U-D2), and an automatic probe
  /// does not argue: the row is bare, and stays bare until they choose one
  /// themselves. Not even asked — the round trip would be spent on an answer
  /// nothing may write.
  declined,
}

/// Probes USDA for [ingredient] and applies the answer into its NULL fields.
///
/// [ingredient] must be the row as currently stored: a form holding unsaved
/// edits saves them first (plan 0020 **F1**), because the probe reads the
/// row's match text and a pending rename would otherwise ask USDA about the
/// old name — which is the exact flow that failed on the owner's device.
Future<({UsdaEnrichment outcome, Ingredient? row})> enrichFromUsda(
  Ingredient ingredient, {
  required UsdaProbe probe,
  required IngredientRepository repository,
}) async {
  if (!isBareStub(ingredient)) {
    return (outcome: UsdaEnrichment.notBare, row: null);
  }
  if (isUsdaDeclined(ingredient.source)) {
    return (outcome: UsdaEnrichment.declined, row: null);
  }
  // The row's `match_text`, recomputed rather than read: `Ingredient` does
  // not carry the column, and it does not need to. D6 closed the rename
  // hazard by making every writer store `normalizeMatchText(canonicalName)`
  // alongside the name in one statement, so this IS the stored value — and
  // if it ever stopped being, the writer would already be broken for
  // matching, which is the bug D6 fixed.
  final candidate = await probe.probe(
    normalizeMatchText(ingredient.canonicalName),
  );
  if (candidate == null) {
    return (outcome: UsdaEnrichment.noAnswer, row: null);
  }
  if (!candidate.hasSomethingToCopy) {
    return (outcome: UsdaEnrichment.nothingToCopy, row: null);
  }
  final applied = await repository.applyUsdaProbe(
    ingredient.id,
    densityGPerMl: candidate.densityGPerMl,
    macros: candidate.macros,
    source: candidate.source,
    sourceLabel: candidate.description,
    sourceScore: candidate.score,
  );
  return applied == null
      // The row went away, or stopped being a bare stub between the read and
      // the write (the other device won the race). Either way nothing here
      // wrote, and the honest report is that nothing came back.
      ? (outcome: UsdaEnrichment.notBare, row: null)
      : (outcome: UsdaEnrichment.applied, row: applied);
}

/// Whether [ingredient] is a row an automatic prefill may write to: a `stub`
/// with nothing to lose.
///
/// The Dart mirror of the 0014/0015 trigger's WHEN clause. It deliberately
/// does NOT mirror that clause's `source in ('manual','import_stub')` leg,
/// because this path has already made a *deliberate* choice to enrich; the
/// server's leg exists to keep an unattended trigger off the seed's audited
/// tail and off a barcode row's Open Food Facts provenance. Callers that must
/// not clobber `off:` provenance check it themselves — see the add sheet,
/// which only probes a manual draft.
bool isBareStub(Ingredient ingredient) =>
    ingredient.status == IngredientStatus.stub &&
    ingredient.densityGPerMl == null &&
    ingredient.macros == null;
