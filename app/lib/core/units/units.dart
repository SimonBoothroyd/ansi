/// The unit system — **contract only** (roadmap step 1, spec §4 "build FIRST").
///
/// This file intentionally contains no logic yet: the scaffold ships the shape,
/// not the implementation (that's a feature, tracked in the roadmap). It's pure
/// Dart and must stay free of `package:flutter` (enforced in CI).
///
/// Intended surface, per spec §4:
///
/// - `UnitFamily` — mass | volume | count | imprecise.
/// - `Unit` — id, label, family, and (for mass/volume) a fixed ratio to the
///   canonical base (grams for mass, ml for volume). count/imprecise have none.
/// - `Quantity` — an amount paired with a `Unit`.
/// - A converter that:
///     * converts within a family via the fixed ratio table;
///     * converts volume↔mass via an ingredient's `density_g_per_ml`;
///     * refuses to convert `imprecise` units (pinch, dash, to taste) and
///       leaves them unchanged under scaling;
///     * returns a typed failure (see `core/result/result.dart`) rather than
///       throwing, e.g. when a cross-family conversion lacks a density.
///
/// When implementing, land it with the tests in `test/core/units/`.
library;

// TODO(step-1): implement UnitFamily, Unit, Quantity, and the converter.
// Golden values to target (verified): 1 kg → 1000 g; 2 tbsp → 29.5735 ml;
// 600 ml @1.02 g/ml → 612 g; 100 g @1.42 g/ml → 70.42 ml; "to taste" ×2 →
// unchanged; count→mass without density → Failure.
