/// The component sheet's chip offer (step 8.6 / D2, board frame d): `batch` ∪
/// the yields' families, kitchen-trimmed, with the stored selection always
/// admitted.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/component_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a yield-less recipe offers batch and nothing else', () {
    final offer = componentUnitChips(yields: const []);
    expect(offer.chips, [batches]);
    expect(offer.offFilter, isNull);
  });

  test('a "makes 1 cup" yield opens its family, kitchen-trimmed', () {
    // Exactly the board's frame-d row: batch | cup tbsp tsp ml.
    final offer = componentUnitChips(yields: [(qty: 1, unit: cup)]);
    expect(offer.chips, [batches, cup, tbsp, tsp, ml]);
    // Label-reading granularity is not kitchen granularity.
    expect(offer.chips, isNot(contains(flOz)));
    expect(offer.chips, isNot(contains(l)));
  });

  test('two denominations open both families — the owner amendment', () {
    final offer = componentUnitChips(
      yields: [(qty: 250, unit: g), (qty: 16, unit: tbsp)],
    );
    expect(offer.chips, [batches, g, kg, tbsp, cup, tsp, ml]);
  });

  test('a mass-only yield does NOT open volume — no density for a recipe', () {
    final offer = componentUnitChips(yields: [(qty: 250, unit: g)]);
    expect(offer.chips, [batches, g, kg]);
    expect(offer.chips, isNot(contains(tbsp)));
  });

  test('a count yield offers pieces', () {
    final offer = componentUnitChips(yields: [(qty: 8, unit: pieces)]);
    expect(offer.chips, [batches, pieces]);
  });

  test('the stored unit is always admitted, and flagged off-filter', () {
    // An imported line printed "2 tbsp" of a butter that only says 250 g: the
    // chip stays, so the sheet never silently rewrites what the page printed.
    final offer = componentUnitChips(
      yields: [(qty: 250, unit: g)],
      stored: tbsp,
    );
    expect(offer.chips.last, tbsp);
    expect(offer.offFilter, tbsp);
  });

  test('a stored unit the rule already offers is not flagged', () {
    final offer = componentUnitChips(
      yields: [(qty: 1, unit: cup)],
      stored: tbsp,
    );
    expect(offer.offFilter, isNull);
    expect(offer.chips.where((u) => u == tbsp), hasLength(1));
  });
}
