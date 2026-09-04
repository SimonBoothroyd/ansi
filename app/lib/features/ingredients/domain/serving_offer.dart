/// What a serving's name and weight ALSO say about a row.
///
/// A pack's "one serving is 14 g · 1 Tbsp" carries two facts, not one: the
/// macros, and a weight for a named amount. The second is a density when the
/// name is a volume word (ADR-0008 §2 — a volume-named weight IS a density,
/// so the volume units unlock exactly as they would from a typed one) and a
/// measure when it names a thing (ADR-0008 §3).
///
/// Computed, never written: the form offers it, the person ticks it, and it
/// rides the same one Save as everything else (ADR-0011). The wording of the
/// offer is presentation's — this file decides only what is on offer.
library;

import '../../../core/units/macros.dart';
import '../../../core/units/units.dart';
import 'allowed_units.dart';

/// The offer a serving makes.
sealed class ServingOffer {
  const ServingOffer();
}

/// "1 tbsp = 14 g" — the weight of a named volume, which is a density.
class DensityOffer extends ServingOffer {
  const DensityOffer({
    required this.unit,
    required this.gramsPerUnit,
    required this.gPerMl,
  });

  final Unit unit;

  /// Grams for ONE of [unit], which is how a pack's own line reads even when
  /// it printed two of them ("2 Tbsp = 32 g" offers 16 g a tablespoon).
  final double gramsPerUnit;
  final double gPerMl;
}

/// "1 slice = 28 g" — a count-like human unit mapped into the basis.
class MeasureOffer extends ServingOffer {
  const MeasureOffer({
    required this.label,
    required this.amount,
    required this.basis,
  });

  final String label;

  /// In [basis]'s base unit — what a measure stores.
  final double amount;
  final MacrosBasis basis;
}

/// The offer a serving makes, or null when it makes none.
///
/// [name] is read as an optional count and a word ("2 Tbsp", "slice"). A spoon
/// word with a **mass** serving is a density — per spoon; a spoon with an ml
/// serving is a volume of itself and offers nothing. Any other word is a
/// measure of one — a count above one would need a singular nobody typed
/// ("2 slices"), so it is not offered rather than guessed at.
ServingOffer? servingOfferFor({
  required double? amount,
  required String name,
  required MacrosBasis basis,
}) {
  final word0 = name.trim();
  if (amount == null || word0.isEmpty) return null;
  final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s+(.+)$').firstMatch(word0);
  final count = m == null
      ? 1.0
      : double.tryParse(m.group(1)!.replaceAll(',', '.'));
  final word = (m == null ? word0 : m.group(2)!).trim();
  if (count == null || !(count > 0) || word.isEmpty) return null;
  final volume = volumeUnitFromLabel(word);
  if (volume != null) {
    if (basis != MacrosBasis.perG) return null;
    final perUnit = amount / count;
    final gPerMl = densityFromVolumeWeight(volume, perUnit);
    if (gPerMl == null) return null;
    return DensityOffer(unit: volume, gramsPerUnit: perUnit, gPerMl: gPerMl);
  }
  if (count != 1) return null;
  return MeasureOffer(label: word, amount: amount, basis: basis);
}
