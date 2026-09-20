/// Authoring a measure's WORD — PURE DART (invariant 2).
///
/// A measure can be authored at two doors: the row's own measures editor, and
/// *keep as a measure* on a receipt's pack. They are the same act, so the
/// label is read the same way at both — by [measureLabelAsAuthored], which
/// lives under the units because a recipe's own words are authored by it too.
library;

import '../../../core/units/measure.dart';

export '../../../core/units/measure.dart'
    show measureAlreadyNamed, measureLabelAsAuthored;

/// Whether two basis weights are the same fact — the app's one tolerance for
/// that ([kWholeMeasureTolerance], one part in a hundred), so *the same
/// measure* means the same thing here as it does where a whole measure is
/// derived.
bool isSameMeasureWeight(double a, double b) =>
    a > 0 && b > 0 && (a - b).abs() <= kWholeMeasureTolerance * b;

/// Why a word cannot be minted: the row already says it, at a weight this
/// pack is not.
///
/// It names both figures and the way out, because the way out is a real one —
/// the household's own style already distinguishes two sizes of one container
/// by putting the size in the word (`can (14.5 oz)` beside `can (28 oz)`), and
/// that is what makes them two measures rather than one argument.
String measureWordTakenRefusal({
  required String label,
  required String said,
  required String taken,
}) =>
    '“$label” is already $taken on this row, and this pack is $said. Two '
    'sizes of one container are two words — say the size in it, like '
    '“$label ($said)”.';
