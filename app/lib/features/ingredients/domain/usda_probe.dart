/// The USDA enrichment probe — PURE DART (invariant 2).
///
/// Plan 0020 **D7b**. `usda_food` never syncs to a device (ADR-0005), so the
/// app cannot search it. What it *can* do, since migration 0016, is ask the
/// server for **one** candidate by name through a security-definer RPC that
/// writes nothing (`probe_usda`). That is the whole of this interface: a
/// question with at most one answer.
///
/// Why it exists at all, when the 0014/0015 trigger already enriches stubs on
/// upload: the trigger is a *reaction to a round trip*. A stub written on a
/// phone is enriched only after write → upload → trigger → sync down. D7b
/// lets a creation flow ask the question at birth and lets "Look up in USDA"
/// be a real query rather than a re-read of a row nothing has changed yet.
///
/// **The offline contract is part of the type.** [UsdaProbe.probe] returns
/// null for "no confident candidate" *and* for "could not ask" — a network
/// miss is not an error here, because the trigger path is still running and
/// will catch the row when it syncs. Callers degrade with honest copy; they
/// never raise a dialog for a missing connection.
library;

import 'package:meta/meta.dart';

import '../../../core/units/macros.dart';

/// One USDA candidate's copyable fields, as `probe_usda` returns them.
///
/// Deliberately only what the server prefill itself copies: a density, a
/// macro panel, the provenance stamp, and the trigram [score] that earned it.
/// Nothing here describes the reference set — this is an answer about one
/// ingredient, not a window onto `usda_food`.
@immutable
class UsdaCandidate {
  const UsdaCandidate({
    required this.fdcId,
    required this.source,
    required this.score,
    this.densityGPerMl,
    this.macros,
  });

  /// Parses one RPC row, or null when the shape is not what 0016 promises —
  /// a malformed answer must degrade to "nothing came back", never to a
  /// half-populated candidate that then writes half a panel.
  static UsdaCandidate? tryParse(Map<String, Object?> row) {
    final fdcId = row['fdc_id'];
    final source = row['source'];
    final score = row['score'];
    if (fdcId is! num || source is! String || score is! num) return null;
    final density = row['density_g_per_ml'];
    return UsdaCandidate(
      fdcId: fdcId.toInt(),
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

  /// The row's provenance stamp, `usda_fdc:<fdc_id>` — formatted by the
  /// server so the app and the trigger cannot disagree about it.
  final String source;

  /// The trigram similarity that cleared the server's 0.5 floor. Shown, not
  /// acted on: the floor is the server's to enforce.
  final double score;

  final double? densityGPerMl;
  final Macros? macros;

  /// Whether there is anything worth writing. A candidate with neither a
  /// density nor a panel is a name match and nothing else — applying it would
  /// only churn the row's `source`.
  bool get hasSomethingToCopy => densityGPerMl != null || macros != null;

  @override
  String toString() =>
      'UsdaCandidate($source, score: $score, density: $densityGPerMl, '
      'macros: $macros)';
}

// An interface, not a bare function type, for the same reason every
// repository here is one: tests and the unconfigured build swap the whole
// implementation through a provider, and a named type is what makes the two
// substitutions read as the same idea.
// ignore: one_member_abstracts
abstract interface class UsdaProbe {
  /// The best USDA candidate for [matchText], or null.
  ///
  /// [matchText] is the ingredient's **match text** — what
  /// `normalizeMatchText` produces and what the row stores — so this probe
  /// and the server trigger's probe read the same input and reach the same
  /// candidate. Passing a raw display name would quietly ask a different
  /// question than the trigger asks.
  ///
  /// Returns null for a name nothing confidently matches **and** for an
  /// unreachable server. The caller cannot tell the two apart, and must not
  /// need to: in both cases the honest thing to say is that nothing came
  /// back, and the trigger will still catch the row when it syncs.
  Future<UsdaCandidate?> probe(String matchText);
}
