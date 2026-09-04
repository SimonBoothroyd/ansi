/// The USDA enrichment probe — PURE DART (invariant 2).
///
/// Plan 0020 **D7b**, widened by plan 0027 **U-D1/U-D3**. `usda_food` never
/// syncs to a device (ADR-0005), so the app cannot search it. What it *can*
/// do, since migration 0016, is ask the server for candidates by name
/// through a security-definer RPC that writes nothing (`probe_usda`). Since
/// 0027 the answer names each candidate (its `description`) and can be a
/// short-list rather than a single row — "the next five", in the same total
/// order the prefill trigger uses, so the form can offer *Choose another*.
/// The reference set is still not browsable: the server caps the list.
///
/// Why it exists at all, when the 0014/0015 trigger already enriches stubs on
/// upload: the trigger is a *reaction to a round trip*. A stub written on a
/// phone is enriched only after write → upload → trigger → sync down. D7b
/// lets a creation flow ask the question at birth and lets a lookup be a real
/// query rather than a re-read of a row nothing has changed yet.
///
/// **The offline contract is part of the type.** [UsdaProbe.search] returns
/// an empty list for "no confident candidate" *and* for "could not ask" — a
/// network miss is not an error here, because the trigger path is still
/// running and will catch the row when it syncs. Callers degrade with honest
/// copy; they never raise a dialog for a missing connection.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';

/// How sure the match was, in the two words the form and the pick sheets
/// print (plan 0027 U-D1: "≥ 0.85 close, 0.5–0.85 a guess" — the import's own
/// bands). The 0.5 floor is the server's; nothing below it ever arrives.
enum UsdaBand {
  close,
  guess;

  static UsdaBand of(double score) => score >= 0.85 ? close : guess;

  /// The band as the screens say it.
  String get word => switch (this) {
    close => 'close match',
    guess => 'a guess',
  };
}

/// One USDA candidate, as `probe_usda` returns it.
///
/// Deliberately only what the server prefill itself copies — a density, a
/// macro panel, the provenance stamp — plus what a person needs to recognise
/// it: the [description], its [category], and the trigram [score] that
/// earned it. Nothing here describes the reference set beyond the rows
/// offered; this is an answer about one ingredient, not a window onto
/// `usda_food`.
@immutable
class UsdaCandidate {
  const UsdaCandidate({
    required this.fdcId,
    required this.description,
    required this.source,
    required this.score,
    this.category,
    this.densityGPerMl,
    this.macros,
  });

  /// Parses one RPC row, or null when the shape is not what 0027 promises —
  /// a malformed answer must degrade to "nothing came back", never to a
  /// half-populated candidate that then writes half a panel. A row without a
  /// description is such a row: the whole point of 0027 is that a match can
  /// be named, and a server that cannot name it is a server this build does
  /// not yet understand.
  static UsdaCandidate? tryParse(Map<String, Object?> row) {
    final fdcId = row['fdc_id'];
    final description = row['description'];
    final source = row['source'];
    final score = row['score'];
    if (fdcId is! num ||
        description is! String ||
        source is! String ||
        score is! num) {
      return null;
    }
    final category = row['category'];
    final density = row['density_g_per_ml'];
    return UsdaCandidate(
      fdcId: fdcId.toInt(),
      description: description,
      category: category is String ? category : null,
      source: source,
      score: score.toDouble(),
      densityGPerMl: density is num ? density.toDouble() : null,
      // The same all-four-or-nothing rule a vocab row's panel obeys: a
      // partial panel is no panel (invariant 3).
      macros: _macrosOf(row['macros']),
    );
  }

  static Macros? _macrosOf(Object? raw) {
    if (raw is! Map) return null;
    final kcal = raw['kcal'];
    final protein = raw['protein'];
    final carb = raw['carb'];
    final fat = raw['fat'];
    if (kcal is! num || protein is! num || carb is! num || fat is! num) {
      return null;
    }
    return Macros(
      kcal: kcal.toDouble(),
      protein: protein.toDouble(),
      carb: carb.toDouble(),
      fat: fat.toDouble(),
    );
  }

  final int fdcId;

  /// The food's name as USDA lists it ("Kale, raw") — what the row stores as
  /// `source_label` when this candidate is applied.
  final String description;

  /// USDA's food category ("Vegetables and Vegetable Products"), or null.
  /// Shown on the pick sheets as a second line; never stored.
  final String? category;

  /// The row's provenance stamp, `usda_fdc:<fdc_id>` — formatted by the
  /// server so the app and the trigger cannot disagree about it.
  final String source;

  /// The trigram similarity that cleared the server's 0.5 floor. Shown as a
  /// [band], stored beside the label, never acted on: the floor is the
  /// server's to enforce.
  final double score;

  UsdaBand get band => UsdaBand.of(score);

  final double? densityGPerMl;
  final Macros? macros;

  /// Whether there is anything worth writing. A candidate with neither a
  /// density nor a panel is a name match and nothing else — applying it would
  /// only churn the row's `source`, and the pick sheets leave it out.
  bool get hasSomethingToCopy => densityGPerMl != null || macros != null;

  @override
  String toString() =>
      'UsdaCandidate($source "$description", score: $score, '
      'density: $densityGPerMl, macros: $macros)';
}

/// The one question the app can ask the reference set.
///
/// A class with one abstract method rather than a function type, for the
/// same reason every repository here is one: tests and the unconfigured
/// build swap the whole implementation through a provider. There is only
/// [search]: a single-answer `probe()` used to exist for the automatic fills,
/// and 0029 removed the last of those.
// One member since 0029 removed `probe()`, and deliberately still a type
// rather than a callback: tests and the unconfigured build swap the whole
// implementation through a provider, which a bare function cannot do.
// ignore: one_member_abstracts
abstract class UsdaProbe {
  const UsdaProbe();

  /// The best [limit] USDA candidates for [matchText], best first, or an
  /// empty list.
  ///
  /// [matchText] is **match text** — what `normalizeMatchText` produces —
  /// because that is the shape `usda_food.match_text` is stored in and what
  /// the server tokenises against. It is the normalised form of the name in
  /// the FIELD, not of the stored row: the search asks about what the person
  /// is looking at, which is what lets a rename be searched before it is
  /// saved.
  ///
  /// Empty for a name nothing matches **and** for an unreachable server. The
  /// caller cannot tell the two apart, and the sheet does not need to — it
  /// draws its own empty state either way. Nothing fills the row behind it:
  /// since 0029 there is no probe-at-birth and no server trigger, so an empty
  /// result means the person has to look again or type the numbers, and
  /// saying so plainly is the whole point. The server caps [limit] at ten.
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5});
}
