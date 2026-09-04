/// The USDA enrichment probe — PURE DART (invariant 2).
///
/// `usda_food` never syncs to a device (ADR-0005), so the app cannot search
/// it. What it *can* do, since migration 0016, is ask the server for candidates
/// by name through a security-definer RPC that writes nothing (`probe_usda`).
/// The answer names each candidate (its `description`) and is a short-list
/// ranked by coverage, so the form can offer *Choose another*. The reference
/// set is still not browsable: the server caps the list.
///
/// **The offline contract is part of the type.** [UsdaProbe.search] returns an
/// empty list for "nothing matches" *and* for "could not ask", and nothing else
/// will fill the row afterwards — there is no probe-at-birth and no server
/// trigger. Callers degrade with honest copy; they never raise a dialog for a
/// missing connection.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';

/// Whether a candidate accounts for **every word of the name it was found
/// for**, or only some of them.
///
/// It is coverage, not confidence: a person picks the food, so how sure a
/// machine was is not the useful thing to say, and `score` is the query's
/// idf-weighted coverage rather than a graded likelihood. Measured over the 267
/// curated pairs in `seed_prefill.sql` it is **bimodal**: 226 of 264 top picks
/// sit at exactly 1.0 and *nothing* falls between 0.85 and 1.0, so every
/// threshold in that range asks the same yes/no question. A band with no middle
/// is a boolean wearing a threshold's clothes.
///
/// It earns its place all the same: a full-coverage pick is the right food
/// **63%** of the time against **34%** for a partial one.
///
/// A row stamped before 0029 carries a trigram score, where 1.0 meant an
/// identical string — which also means every word matched, so the reading
/// stays true for those rows rather than quietly meaning something else.
enum UsdaMatchFit {
  full,
  partial;

  static UsdaMatchFit of(double score) => score >= 0.999 ? full : partial;

  /// The tag the pick sheet puts on a candidate row, where space is one word
  /// beside a description.
  String get tag => switch (this) {
    full => 'all words',
    partial => 'some words',
  };

  /// The sentence the form's provenance line prints, naming what was asked.
  String phraseFor(String name) => switch (this) {
    full => 'matches every word of “$name”',
    partial => 'matches only part of “$name”',
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
  /// [fit], stored beside the label, never acted on: the floor is the
  /// server's to enforce.
  final double score;

  UsdaMatchFit get fit => UsdaMatchFit.of(score);

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
/// One member, and deliberately a type rather than a callback: tests and the
/// unconfigured build swap the whole implementation through a provider, which a
/// bare function cannot do.
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
