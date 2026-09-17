/// An in-memory [PriceRepository] for widget tests — the price sheet's write
/// seam and the Price group's two reads, with no database under them.
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/ingredients/domain/price_repository.dart';

/// One call to [FakePriceRepo.recordManualPrice], exactly as the sheet made
/// it — what the sheet ASKED for, which is the assertion.
typedef RecordedPrice = ({
  String ingredientId,
  int cents,
  double packBasisAmount,
  String store,
  String? measureId,
  DateTime? purchasedAt,
});

class FakePriceRepo implements PriceRepository {
  FakePriceRepo({
    List<PriceObservation> prices = const [],
    List<String> stores = const [],
    this.basis = MacrosBasis.perG,
    this.throws = false,
  }) : rows = [...prices],
       storeWords = [...stores];

  /// Newest first, like the real read.
  final List<PriceObservation> rows;
  final List<String> storeWords;
  final MacrosBasis basis;

  /// Makes the write fail, so a test can drive the honest-failure path.
  final bool throws;

  final recorded = <RecordedPrice>[];
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
  Stream<List<String>> watchStores() async* {
    yield [...storeWords];
    yield* _changes.stream.map((_) => [...storeWords]);
  }

  @override
  Future<void> recordManualPrice({
    required String ingredientId,
    required int cents,
    required double packBasisAmount,
    required String store,
    String? measureId,
    DateTime? purchasedAt,
  }) async {
    if (throws) throw StateError('no');
    recorded.add((
      ingredientId: ingredientId,
      cents: cents,
      packBasisAmount: packBasisAmount,
      store: store,
      measureId: measureId,
      purchasedAt: purchasedAt,
    ));
    rows.insert(
      0,
      PriceObservation(
        lineId: 'l-${rows.length}',
        receiptId: 'r-${rows.length}',
        cents: cents,
        packBasisAmount: packBasisAmount,
        basis: basis,
        store: store,
        purchasedAt: purchasedAt ?? DateTime.now().toUtc(),
      ),
    );
    if (!storeWords.contains(store)) storeWords.insert(0, store);
    _changes.add(null);
  }
}
