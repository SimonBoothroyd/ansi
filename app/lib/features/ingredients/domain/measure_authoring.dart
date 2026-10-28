/// Authoring a measure's word. Pure Dart. A measure can be authored in the
/// row's measures editor or by *keep as a measure* on a receipt's pack; both
/// read the label through [measureLabelAsAuthored].
library;

import '../../../core/units/measure.dart';

export '../../../core/units/measure.dart'
    show measureAlreadyNamed, measureLabelAsAuthored;

/// Whether two basis weights are the same fact, within [kWholeMeasureTolerance]
/// (one part in a hundred).
bool isSameMeasureWeight(double a, double b) =>
    a > 0 && b > 0 && (a - b).abs() <= kWholeMeasureTolerance * b;

/// Why a word cannot be minted: the row already says it at a different weight
/// ([taken]). The refusal names only the way out, the size in the word (`can
/// (14.5 oz)` beside `can (28 oz)`), so [taken] is not printed.
String measureWordTakenRefusal({
  required String label,
  required String said,
  required String taken,
}) => '“$label” is taken. Try “$label ($said)”.';
