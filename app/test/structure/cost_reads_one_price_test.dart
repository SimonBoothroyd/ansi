/// Structural: a cost reads by one of TWO rules, each chosen in one place.
///
/// Every cost but the Shop's reads the newest price paid on a receipt, else
/// the row's base price (`costPriceOf`). The Shop — its rows, its trip, and
/// Ask's answer about the trip — reads the cheapest paid in the window, else
/// that same price (`shopPriceOf`). Both live in
/// `ingredients/domain/cost_price.dart` (ADR-0017). Each rule is only true if
/// nothing else answers its question, so this test fails on the ways a third
/// answer, or a crossed wire, creeps in:
///
/// - a file other than the price repository reading the base-price columns, or
///   reading `receipt_line` for anything but a watch trigger;
/// - a file other than the price repository calling either resolver itself;
/// - the paid-only map (`watchLatestPrices`, `latestByIngredient`) reaching a
///   cost — it is the receipt review's pack memory and nothing else;
/// - a cost walk (`pricingResolver`, `sumPlannedCost`, `IngredientPricing`)
///   fed from anything but the latest map (`loadCostPrices`,
///   `costPriceMapProvider`);
/// - the Shop's map (`watchShopPrices`, `shopPriceMapProvider`, the Shop's
///   pricing) read anywhere but the Shop's own files, or a file that reads it
///   running any cost walk but the Shop's;
/// - the Shop's walk (`tripCostCents`, `shoppingItemCostCents`) fed from
///   anything but the Shop's map.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

const _priceRepo = 'lib/features/ingredients/data/price_repository_impl.dart';
const _priceInterface = 'lib/features/ingredients/domain/price_repository.dart';
const _resolvers = 'lib/features/ingredients/domain/cost_price.dart';
const _shopViewModels =
    'lib/features/shopping/presentation/shopping_view_models.dart';
const _shopView = 'lib/features/shopping/presentation/shopping_view.dart';
const _shopCost = 'lib/features/shopping/domain/shopping_cost.dart';

/// Where each token may appear under `lib/`. A file not listed is an offender.
const _allowed = <String, Set<String>>{
  // The columns: the repository reads and writes them; the schema declares
  // them.
  'base_price_': {_priceRepo, 'lib/core/sync/schema.dart'},
  // The resolvers' entry points, called by the repository alone.
  'costPriceOf(': {_priceRepo, _resolvers},
  'costPrices(': {_priceRepo, _resolvers},
  'shopPriceOf(': {_priceRepo, _resolvers},
  // The paid-only map: the receipt review carries a pack from it, and never
  // prices anything with it.
  'watchLatestPrices': {
    _priceRepo,
    _priceInterface,
    'lib/features/receipts/presentation/receipt_view_models.dart',
  },
  'latestByIngredient': {_priceRepo},
  // The Shop's map, and the pricing built from it: the Shop's files alone.
  // Ask's trip answer reaches it through `readShopTripCost`, the Shop's own
  // reading, never by building one of its own.
  'watchShopPrices(': {_priceRepo, _priceInterface, _shopViewModels},
  'shopPriceMapProvider': {_shopViewModels},
  'shopPricingProvider': {_shopViewModels, _shopView},
  'shopPricingOf(': {_shopViewModels, _shopCost},
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

/// Every cost but the Shop's, and the latest map every file that runs one must
/// read.
const _latestWalks = [
  'pricingResolver(',
  'sumPlannedCost(',
  'IngredientPricing>',
];
// `watchCostPrices(` is the stream `costPriceMapProvider` wraps, read
// directly where a provider would be read once and lost (Ask's figures,
// `no_future_on_autodispose_test.dart`).
const _latest = ['loadCostPrices(', 'watchCostPrices(', 'costPriceMapProvider'];

/// The Shop's cost, and the Shop's map every file that runs it must read.
const _shopWalks = ['tripCostCents(', 'shoppingItemCostCents('];
const _shop = [
  'watchShopPrices(',
  'shopPriceMapProvider',
  'shopPricingProvider',
  'shopPricingOf(',
];

void main() {
  final files = [
    for (final file in dartFiles(Directory('lib')))
      (path: file.path, source: blankComments(file.readAsStringSync())),
  ];

  test('structural: one place answers each rule', () {
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
          'a cost reads `costPriceOf` or, in the Shop, `shopPriceOf`, through '
          'the price repository and nothing else:\n${offenders.join('\n')}',
    );
  });

  test('structural: every cost walk is fed its own rule', () {
    final offenders = <String>[];
    for (final file in files) {
      // A domain walk takes its prices as a parameter; the file that hands
      // them in is the one that must have read the map.
      if (file.path.contains('/domain/')) continue;
      final latestWalks = _latestWalks.where(file.source.contains).toList();
      final shopWalks = _shopWalks.where(file.source.contains).toList();
      final readsLatest = _latest.any(file.source.contains);
      final readsShop = _shop.any(file.source.contains);
      if (latestWalks.isNotEmpty && !readsLatest) {
        offenders.add(
          '${file.path}: runs ${latestWalks.join(', ')} without the latest '
          'map',
        );
      }
      if (latestWalks.isNotEmpty && readsShop) {
        offenders.add(
          "${file.path}: the Shop's map reaches ${latestWalks.join(', ')}",
        );
      }
      if (shopWalks.isNotEmpty && !readsShop) {
        offenders.add(
          "${file.path}: runs ${shopWalks.join(', ')} without the Shop's map",
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a file that costs something reads `loadCostPrices` or '
          "`costPriceMapProvider`; the Shop's walk reads the Shop's map, and "
          "the Shop's map reaches no other cost:\n${offenders.join('\n')}",
    );
  });
}
