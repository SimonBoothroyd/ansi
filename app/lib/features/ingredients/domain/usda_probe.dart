/// The USDA enrichment probe. Pure Dart.
///
/// `usda_food` never syncs to a device (ADR-0005), so the app asks the server
/// for candidates by name through the write-free `probe_usda` RPC, which
/// returns a capped short-list ranked by coverage.
///
/// [UsdaProbe.search] returns an empty list both for "nothing matches" and for
/// "could not ask", and nothing else fills the row afterwards. Callers degrade
/// with copy, never a dialog.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';

/// Whether a candidate accounts for every word of the name it was found for, or
/// only some.
///
/// It is coverage, not confidence: `score` is the query's idf-weighted
/// coverage. Over the curated ingredient → FDC pairs it is bimodal (nothing
/// falls between 0.85 and 1.0), so it is a yes/no reading; a full-coverage pick
/// is the right food about twice as often as a partial one. Older rows carry a
/// trigram score, where 1.0 also means every word matched.
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

/// One USDA candidate, as `probe_usda` returns it: what the prefill copies (a
/// density, a macro panel, the provenance stamp) plus what a person needs to
/// recognise it ([description], [category], [score]).
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

  /// Parses one RPC row, or null when the shape is wrong, so a malformed answer
  /// never becomes a half-populated candidate. A row with no description is
  /// malformed.
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
    // Fibre is read when present and optional otherwise ([Macros.fiber]).
    final fiber = raw['fiber'];
    return Macros(
      kcal: kcal.toDouble(),
      protein: protein.toDouble(),
      carb: carb.toDouble(),
      fat: fat.toDouble(),
      fiber: fiber is num ? fiber.toDouble() : null,
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

  /// The server's match score, already above its floor. Shown as a [fit] and
  /// stored beside the label, never acted on.
  final double score;

  UsdaMatchFit get fit => UsdaMatchFit.of(score);

  final double? densityGPerMl;
  final Macros? macros;

  /// Whether there is anything worth writing. A candidate with neither a
  /// density nor a panel would only churn the row's `source`, so the pick
  /// sheets leave it out.
  bool get hasSomethingToCopy => densityGPerMl != null || macros != null;

  @override
  String toString() =>
      'UsdaCandidate($source "$description", score: $score, '
      'density: $densityGPerMl, macros: $macros)';
}

/// The one question the app can ask the reference set. A type rather than a
/// callback so tests and the unconfigured build can swap the implementation
/// through a provider.
// ignore: one_member_abstracts
abstract class UsdaProbe {
  const UsdaProbe();

  /// The best [limit] USDA candidates for [matchText], best first, or an empty
  /// list. The server caps [limit] at ten.
  ///
  /// [matchText] is what `normalizeMatchText` produces, from the name in the
  /// field rather than the stored row, so a rename can be searched before it is
  /// saved. Empty for no match and for an unreachable server alike; the sheet
  /// draws its own empty state.
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5});
}
