/// What every receipts widget suite pumps: a vocabulary the sample payload's
/// matches resolve against, a fake ledger, and the two hosts — the scan route
/// and the ledger.
// The pumped ProviderScope IS the root scope of each test's tree.
// ignore_for_file: scoped_providers_should_specify_dependencies
library;

import 'dart:async';

import 'package:ansi/core/sync/session.dart';
import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/receipts/data/receipt_providers.dart';
import 'package:ansi/features/receipts/data/replay_receipt_repository.dart';
import 'package:ansi/features/receipts/data/sample_receipt_payloads.dart';
import 'package:ansi/features/receipts/domain/receipt_repository.dart';
import 'package:ansi/features/receipts/domain/receipt_save.dart';
import 'package:ansi/features/receipts/presentation/receipt_ledger_view.dart';
import 'package:ansi/features/receipts/presentation/receipt_scan_view.dart';
import 'package:ansi/features/receipts/presentation/receipt_view_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';
import '../../helpers/fake_price_repository.dart';

const bananas = Ingredient(
  id: 'vocab-banana',
  canonicalName: 'Bananas, organic',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 89, protein: 1.1, carb: 23, fat: 0.3),
  source: 'seed',
);

const onion = Ingredient(
  id: 'vocab-onion',
  canonicalName: 'Yellow onion',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 40, protein: 1.1, carb: 9, fat: 0.1),
  source: 'seed',
);

const salmon = Ingredient(
  id: 'vocab-salmon',
  canonicalName: 'Salmon fillet',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 208, protein: 20, carb: 0, fat: 13),
  source: 'seed',
);

const sriracha = Ingredient(
  id: 'vocab-sriracha',
  canonicalName: 'Sriracha',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 93, protein: 2, carb: 19, fat: 1),
  source: 'seed',
);

const cheddar = Ingredient(
  id: 'vocab-cheddar',
  canonicalName: 'Cheddar',
  defaultUnit: g,
  status: IngredientStatus.complete,
  macros: Macros(kcal: 403, protein: 25, carb: 1.3, fat: 33),
  source: 'seed',
);

const sampleVocabulary = [bananas, onion, salmon, sriracha, cheddar];

/// A vocabulary that answers the lookups the review makes, and nothing else.
class SampleVocabRepo extends ReadOnlyIngredientRepo {
  const SampleVocabRepo({this.rows = sampleVocabulary});

  final List<Ingredient> rows;

  @override
  Future<Ingredient?> byId(String id) async {
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final row in rows)
      if (ids.contains(row.id)) row.id: row,
  };
}

/// An in-memory [ReceiptRepository] — what Save asked for, which is the
/// assertion, plus the rows the ledger reads back.
class FakeReceiptRepo implements ReceiptRepository {
  FakeReceiptRepo({List<ReceiptLedgerRow> rows = const []})
    : ledger = [...rows];

  final List<ReceiptLedgerRow> ledger;
  final saved = <ReceiptWrite>[];
  final _changes = StreamController<void>.broadcast();

  /// Makes the write fail, so a test can drive the honest-failure path.
  bool throws = false;

  @override
  Stream<List<ReceiptLedgerRow>> watchReceipts() async* {
    yield [...ledger];
    yield* _changes.stream.map((_) => [...ledger]);
  }

  @override
  Stream<StoredReceipt?> watchReceipt(String receiptId) =>
      Stream.value(stored[receiptId]);

  /// What one receipt reads back as, by id.
  final stored = <String, StoredReceipt>{};

  @override
  Future<String> saveReceipt(ReceiptWrite write) async {
    if (throws) throw StateError('no');
    saved.add(write);
    _changes.add(null);
    return 'r-${saved.length}';
  }

  /// What an edit of a saved receipt asked for, by receipt id.
  final updated = <(String, ReceiptWrite)>[];
  final deleted = <String>[];

  @override
  Future<void> updateReceipt(String receiptId, ReceiptWrite write) async {
    if (throws) throw StateError('no');
    updated.add((receiptId, write));
  }

  @override
  Future<void> deleteReceipt(String receiptId) async {
    if (throws) throw StateError('no');
    deleted.add(receiptId);
    stored.remove(receiptId);
  }
}

/// One ledger row, spelled out.
ReceiptLedgerRow ledgerRow({
  required DateTime on,
  String id = 'r1',
  String store = "TJ's",
  String source = 'photo',
  int? total = 8412,
  int lines = 24,
  int notFood = 2,
  int linesSum = 8330,
}) => (
  id: id,
  store: store,
  purchasedAt: on,
  source: source,
  subtotalCents: 8330,
  taxCents: 82,
  totalCents: total,
  lineCount: lines,
  notFoodCount: notFood,
  linesSumCents: linesSum,
);

List<Override> receiptOverrides({
  ReceiptRepository? ledger,
  IngredientRepository? vocab,
  FakeMeasureRepo? measures,
  FakePriceRepo? prices,
  String json = sampleReceiptJson,
  Duration pace = Duration.zero,
}) => [
  currentHouseholdIdProvider.overrideWithValue('h'),
  receiptImportRepositoryProvider.overrideWithValue(
    ReplayReceiptRepository(json: json, pace: pace),
  ),
  receiptRepositoryProvider.overrideWithValue(ledger ?? FakeReceiptRepo()),
  ingredientRepositoryProvider.overrideWithValue(
    vocab ?? const SampleVocabRepo(),
  ),
  measureRepositoryProvider.overrideWithValue(measures ?? FakeMeasureRepo()),
  priceRepositoryProvider.overrideWithValue(
    prices ?? FakePriceRepo(stores: const ["TJ's", 'Whole Foods']),
  ),
];

/// The scan route under a real router, with the ledger's two destinations
/// standing in — Save REPLACES its page, and a replacement cannot be observed
/// without one.
Widget scanHost({
  required List<Override> overrides,
  void Function(GoRouter router)? expose,
}) {
  final router = GoRouter(
    initialLocation: '/receipts/review',
    routes: [
      GoRoute(
        path: '/receipts/review',
        builder: (_, _) => const ReceiptScanView(),
      ),
      GoRoute(path: '/receipts', builder: (_, _) => const ReceiptLedgerView()),
      GoRoute(
        path: '/receipts/:id',
        builder: (_, state) => Text('receipt ${state.pathParameters['id']}'),
      ),
    ],
  );
  expose?.call(router);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: ansiHostTheme(),
      routerConfig: router,
      builder: (context, child) => FTheme(
        data: ansiThemeData(),
        child: FToaster(child: child!),
      ),
    ),
  );
}

/// The ledger under a router, so a row can be tapped.
Widget ledgerHost({required List<Override> overrides}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp.router(
    theme: ansiHostTheme(),
    routerConfig: GoRouter(
      initialLocation: '/receipts',
      routes: [
        GoRoute(
          path: '/receipts',
          builder: (_, _) => const ReceiptLedgerView(),
        ),
        GoRoute(
          path: '/receipts/:id',
          builder: (_, state) => Text('receipt ${state.pathParameters['id']}'),
        ),
      ],
    ),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

/// One saved receipt on its own page — the review, open on the rows.
Widget storedReceiptHost({
  required List<Override> overrides,
  required String receiptId,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp.router(
    theme: ansiHostTheme(),
    routerConfig: GoRouter(
      initialLocation: '/receipts/$receiptId',
      routes: [
        GoRoute(
          path: '/receipts/:id',
          builder: (_, state) =>
              StoredReceiptView(receiptId: state.pathParameters['id']!),
        ),
      ],
    ),
    builder: (context, child) => FTheme(
      data: ansiThemeData(),
      child: FToaster(child: child!),
    ),
  ),
);

/// A surface tall enough to hold a whole receipt at once.
///
/// The review is a long column by nature — the paper's own facts, then every
/// line — and a 600 px test window builds only the top of it, so a finder for
/// a line further down reports "not found" when the screen is perfectly
/// correct. The alternative is a scroll before every assertion, which tests
/// the scroll rather than the screen.
void tallSurface(WidgetTester tester, {double height = 3000}) {
  tester.view.physicalSize = Size(900, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Walks the scan from the intake to the review: the replay repository
/// answers instantly, so one settle is the whole read.
Future<void> runTheScan(
  WidgetTester tester,
  ProviderContainer container,
) async {
  // The photo intake is a platform door; the controller is driven directly,
  // which is what every test of this screen actually wants to exercise.
  await container
      .read(receiptScanControllerProvider.notifier)
      .scan(const ReceiptPhotos(['a.jpg']));
  await tester.pumpAndSettle();
}
