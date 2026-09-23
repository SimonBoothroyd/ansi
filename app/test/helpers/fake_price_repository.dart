/// An in-memory [PriceRepository] for widget tests — the price sheet's write
/// seam (the base price) and the Price group's reads, with no database under
/// them.
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/cost_price.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/ingredients/domain/price_repository.dart';

/// One call to [FakePriceRepo.setBasePrice], exactly as the sheet made it —
/// what the sheet ASKED for, which is the assertion.
typedef SetBase = ({
  String ingredientId,
  int cents,
  double packBasisAmount,
  String? store,
  double? packAmount,
  String? packUnitId,
  String? measureId,
});

class FakePriceRepo implements PriceRepository {
  FakePriceRepo({
    List<PriceObservation> prices = const [],
    List<String> stores = const [],
    List<ReceiptName> names = const [],
    Map<String, PackLastBoughtAs> packsByName = const {},
    this.basis = MacrosBasis.perG,
    this.throws = false,
    this.base,
  }) : rows = [...prices],
       storeWords = [...stores],
       receiptNames = [...names],
       packs = {
         for (final entry in packsByName.entries)
           if (printedNameKey(entry.key) case final key?) key: entry.value,
       };

  /// Newest first, like the real read.
  final List<PriceObservation> rows;
  final List<String> storeWords;
  final MacrosBasis basis;

  /// Makes the write fail, so a test can drive the honest-failure path.
  final bool throws;

  /// The row's base price, as the sheet last left it.
  BasePrice? base;

  final setCalls = <SetBase>[];
  final cleared = <String>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<PriceObservation>> watchPrices(String ingredientId) async* {
    yield [...rows];
    yield* _changes.stream.map((_) => [...rows]);
  }

  /// The same rows as a latest-per-ingredient map. The fake holds ONE
  /// ingredient's ledger, so the newest row is that ingredient's latest — and
  /// the key is whatever that row's ingredient is said to be.
  @override
  Stream<Map<String, PriceObservation>> watchLatestPrices() async* {
    yield latest;
    yield* _changes.stream.map((_) => latest);
  }

  /// Which ingredient the fake's rows belong to, for the map read above.
  String ingredientId = 'ing-1';

  Map<String, PriceObservation> get latest =>
      rows.isEmpty ? const {} : {ingredientId: rows.first};

  @override
  Stream<Map<String, UnitPrice>> watchCostPrices() async* {
    yield costs;
    yield* _changes.stream.map((_) => costs);
  }

  Map<String, UnitPrice> get costs => costPrices(
    latestPaid: latest,
    base: {if (base case final price?) ingredientId: price},
  );

  @override
  Stream<BasePrice?> watchBasePrice(String ingredientId) async* {
    yield base;
    yield* _changes.stream.map((_) => base);
  }

  /// The household's saved lines as the review reads them: the pack filed
  /// under each printed name, keyed by [printedNameKey] so a test may seed the
  /// words exactly as a receipt prints them.
  final Map<String, PackLastBoughtAs> packs;

  /// Every batch this repo was asked for, so a test can hold the "one read for
  /// the whole receipt" promise rather than trusting it.
  final asked = <Set<String>>[];

  @override
  Future<Map<String, PackLastBoughtAs>> packsByPrintedName(
    Set<String> namesPrinted,
  ) async {
    if (throws) throw StateError('no');
    asked.add(namesPrinted);
    return {
      for (final name in namesPrinted)
        if (printedNameKey(name) case final key?)
          if (packs[key] case final pack?) key: pack,
    };
  }

  @override
  Stream<List<String>> watchStores() async* {
    yield [...storeWords];
    yield* _changes.stream.map((_) => [...storeWords]);
  }

  /// The names the fake's receipts carry, newest first — already folded, the
  /// way the real read hands them over. The grouping and the ordering are the
  /// repository's own job and are pinned on the real schema, so the fake holds
  /// the answer rather than recomputing it.
  @override
  Stream<List<ReceiptName>> watchReceiptNames(String ingredientId) async* {
    yield [...receiptNames];
    yield* _changes.stream.map((_) => [...receiptNames]);
  }

  /// What [watchReceiptNames] answers with. Mutable, so a test can put a name
  /// on a receipt mid-pump and assert the fold followed it.
  final List<ReceiptName> receiptNames;

  @override
  Future<void> setBasePrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    String? store,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  }) async {
    if (throws) throw StateError('no');
    setCalls.add((
      store: store,
      ingredientId: ingredientId,
      cents: cents,
      packBasisAmount: packBasisAmount,
      packAmount: packAmount,
      packUnitId: packUnitId,
      measureId: measureId,
    ));
    base = BasePrice(
      ingredientId: ingredientId,
      cents: cents,
      packBasisAmount: packBasisAmount,
      basis: basis,
      setAt: DateTime.now().toUtc(),
      store: store,
      packAmount: packAmount,
      packUnit: unitById(packUnitId ?? ''),
      measureId: measureId,
    );
    _changes.add(null);
  }

  @override
  Future<void> clearBasePrice(String ingredientId) async {
    if (throws) throw StateError('no');
    cleared.add(ingredientId);
    base = null;
    _changes.add(null);
  }
}
