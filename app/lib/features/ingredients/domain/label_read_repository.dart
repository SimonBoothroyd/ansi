/// The seam behind the ingredient form's `Read a label` door.
library;

import 'label_reading.dart';

/// Reads one photographed nutrition label.
///
/// A seam rather than a function: the app has three implementations — the edge
/// function, the one an unconfigured build refuses with, and the fake the
/// widget tests answer from. It writes nothing anywhere; what the reading
/// becomes is the form's business, and the form's Save is what stores it.
// ignore: one_member_abstracts
abstract interface class LabelReadRepository {
  /// The label in the photo at [photoPath], read. Throws an `ImportException`
  /// carrying a sentence a person can act on.
  Future<LabelReading> readLabel(String photoPath);
}
