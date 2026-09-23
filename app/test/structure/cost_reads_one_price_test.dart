/// Structural: every cost reads ONE price per row, chosen in one place.
///
/// A cost reads the newest price paid on a receipt, else the row's base price
/// (`ingredients/domain/cost_price.dart`, ADR-0017). That rule is only true if
/// nothing else answers the question, so this test fails on the ways a second
/// answer creeps in:
///
/// - a file other than the price repository reading the base-price columns, or
///   reading `receipt_line` for anything but a watch trigger;
/// - a file other than the price repository calling the resolver itself;
/// - the paid-only map (`watchLatestPrices`, `latestByIngredient`) reaching a
///   cost — it is the receipt review's pack memory and nothing else;
/// - a cost walk (`pricingResolver`, `sumPlannedCost`, `ingredientPricing`)
///   fed from anything but the resolved map (`loadCostPrices`,
///   `costPriceMapProvider`).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

const _priceRepo = 'lib/features/ingredients/data/price_repository_impl.dart';

/// Where each token may appear under `lib/`. A file not listed is an offender.
const _allowed = <String, Set<String>>{
  // The columns: the repository reads and writes them; the schema declares
  // them.
  'base_price_': {_priceRepo, 'lib/core/sync/schema.dart'},
  // The resolver's two entry points, called by the repository alone.
  'costPriceOf(': {
    _priceRepo,
    'lib/features/ingredients/domain/cost_price.dart',
  },
  'costPrices(': {
    _priceRepo,
    'lib/features/ingredients/domain/cost_price.dart',
  },
  // The paid-only map: the receipt review carries a pack from it, and never
  // prices anything with it.
  'watchLatestPrices': {
    _priceRepo,
    'lib/features/ingredients/domain/price_repository.dart',
    'lib/features/receipts/presentation/receipt_view_models.dart',
  },
  'latestByIngredient': {_priceRepo},
  // `receipt_line` in SQL: the ledgers that own it, and two cost loads that
  // join it only so a synced shop re-runs them. Neither reads a column from it
  // into a figure — their prices come from `loadCostPrices`. (The token is
  // matched case-sensitively, which is how every query here is written.)
  'JOIN receipt_line': {
    _priceRepo,
    'lib/features/receipts/data/receipt_repository_impl.dart',
    'lib/features/recipes/data/recipe_repository_impl.dart',
    'lib/features/planning/data/week_variant_repository_impl.dart',
  },
  'FROM receipt_line': {
    _priceRepo,
    'lib/features/receipts/data/receipt_repository_impl.dart',
  },
};

/// A cost walk, and the resolved map every file that runs one must read.
const _costWalks = [
  'pricingResolver(',
  'sumPlannedCost(',
  'IngredientPricing>',
];
const _resolved = ['loadCostPrices(', 'costPriceMapProvider'];

void main() {
  final files = [
    for (final file in dartFiles(Directory('lib')))
      (path: file.path, source: blankComments(file.readAsStringSync())),
  ];

  test('structural: one place answers which price a cost reads', () {
    final offenders = <String>[];
    for (final MapEntry(key: token, value: allowed) in _allowed.entries) {
      for (final file in files) {
        if (allowed.contains(file.path)) continue;
        final at = file.source.indexOf(token);
        if (at >= 0) {
          offenders.add(
            '${file.path}:${lineOf(file.source, at)}: `$token` outside '
            'its allowed files',
          );
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a cost reads `costPriceOf` through the price repository '
          '(`watchCostPrices` / `loadCostPrices`) and nothing else:\n'
          '${offenders.join('\n')}',
    );
  });

  test('structural: every cost walk is fed the resolved prices', () {
    final offenders = <String>[];
    for (final file in files) {
      // A domain walk takes its prices as a parameter; the file that hands
      // them in is the one that must have read the resolved map.
      if (file.path.contains('/domain/')) continue;
      final walks = _costWalks.where(file.source.contains).toList();
      if (walks.isEmpty || _resolved.any(file.source.contains)) continue;
      offenders.add('${file.path}: runs ${walks.join(', ')}');
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a file that costs something reads `loadCostPrices` or '
          '`costPriceMapProvider`:\n${offenders.join('\n')}',
    );
  });
}
