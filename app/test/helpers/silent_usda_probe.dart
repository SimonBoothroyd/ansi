/// The offline / unconfigured USDA answer: nothing, without throwing — what
/// the New-ingredient sheet's D7b probe gets in a widget test that is not
/// about enrichment.
library;

import 'package:ansi/features/ingredients/domain/usda_probe.dart';

class SilentUsdaProbe implements UsdaProbe {
  const SilentUsdaProbe();

  @override
  Future<UsdaCandidate?> probe(String matchText) async => null;
}
