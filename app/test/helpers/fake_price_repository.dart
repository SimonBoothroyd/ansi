/// An in-memory [PriceRepository] for widget tests — the price sheet's write
/// seam and the Price group's two reads, with no database under them.
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/price.dart';
import 'package:ansi/features/ingredients/domain/price_repository.dart';

/// One call to [FakePriceRepo.recordManualPrice], exactly as the sheet made
/// it — what the sheet ASKED for, which is the assertion.
typedef RecordedPrice = ({
  String ingredientId,
  int cents,
  double packBasisAmount,
  String store,
  double? packAmount,
  String? packUnitId,
  String? measureId,
  DateTime? purchasedAt,
});

/// One call to [FakePriceRepo.updatePrice] — which line was rewritten, and to
/// what.
typedef RewrittenPrice = ({
  String lineId,
  int cents,
  double packBasisAmount,
  String store,
  DateTime purchasedAt,
  double? packAmount,
  String? packUnitId,
  String? measureId,
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
  final rewritten = <RewrittenPrice>[];
  final deleted = <String>[];
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
    double? packAmount,
    String? packUnitId,
    String? measureId,
    DateTime? purchasedAt,
  }) async {
    if (throws) throw StateError('no');
    recorded.add((
      ingredientId: ingredientId,
      cents: cents,
      packBasisAmount: packBasisAmount,
      store: store,
      packAmount: packAmount,
      packUnitId: packUnitId,
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
        packAmount: packAmount,
        packUnit: unitById(packUnitId ?? ''),
        measureId: measureId,
      ),
    );
    if (!storeWords.contains(store)) storeWords.insert(0, store);
    _changes.add(null);
  }

  @override
  Future<void> updatePrice({
    required String lineId,
    required int cents,
    required double packBasisAmount,
    required String store,
    required DateTime purchasedAt,
    double? packAmount,
    String? packUnitId,
    String? measureId,
  }) async {
    if (throws) throw StateError('no');
    rewritten.add((
      lineId: lineId,
      cents: cents,
      packBasisAmount: packBasisAmount,
      store: store,
      purchasedAt: purchasedAt,
      packAmount: packAmount,
      packUnitId: packUnitId,
      measureId: measureId,
    ));
    final at = rows.indexWhere((p) => p.lineId == lineId);
    if (at >= 0) {
      final was = rows[at];
      rows[at] = PriceObservation(
        lineId: was.lineId,
        receiptId: was.receiptId,
        cents: cents,
        discountCents: was.discountCents,
        packBasisAmount: packBasisAmount,
        basis: was.basis,
        store: store,
        purchasedAt: purchasedAt,
        packAmount: packAmount,
        packUnit: unitById(packUnitId ?? ''),
        packLabel: measureId == null ? null : was.packLabel,
        measureId: measureId,
      );
    }
    _changes.add(null);
  }

  @override
  Future<void> deletePrice(String lineId) async {
    if (throws) throw StateError('no');
    deleted.add(lineId);
    rows.removeWhere((p) => p.lineId == lineId);
    _changes.add(null);
  }
}
