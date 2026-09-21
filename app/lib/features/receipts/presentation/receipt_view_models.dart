/// The receipt scan session: photos, the reading checklist, the review, Save.
///
/// One controller holds the whole sitting and nothing is written until Save.
/// The notifier is `autoDispose`, and writing `state` on a disposed notifier
/// throws, so every post-await assignment is guarded by [Ref.mounted] and every
/// repository is read before the first await.
library;

import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../import/domain/import_stage.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/domain/allowed_units.dart';
import '../../ingredients/domain/ingredient.dart';
import '../../ingredients/domain/ingredient_repository.dart';
import '../../ingredients/domain/measure_repository.dart';
import '../../ingredients/domain/price.dart';
import '../../ingredients/domain/price_repository.dart';
import '../data/receipt_providers.dart';
import '../domain/receipt_payload.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_review.dart';
import '../domain/receipt_save.dart';
import '../domain/receipt_stage.dart';

part 'receipt_view_models.g.dart';

/// The arriving lines with the packs they could state, and the rows and
/// measures read once for the whole receipt.
typedef _LandedPacks = ({
  List<ReceiptLineDraft> drafts,
  Map<String, Ingredient> rows,
  Map<String, List<Measure>> measuresById,
});

/// The scan state machine.
sealed class ReceiptScanState {
  const ReceiptScanState();
}

/// Nothing started — the intake screen, with its one line of guidance and the
/// photo doors.
class ReceiptIdle extends ReceiptScanState {
  const ReceiptIdle();
}

/// `import-receipt` is running. [rows] is the checklist built from the server's
/// events; empty until the plan arrives.
class ReceiptReading extends ReceiptScanState {
  const ReceiptReading(this.rows);

  final List<StageProgress> rows;
}

/// The payload is back and the person is confirming it. Immutable — every
/// edit produces a new instance, so the screen rebuilds from a value.
class ReceiptReviewing extends ReceiptScanState {
  const ReceiptReviewing({
    required this.payload,
    required this.drafts,
    required this.store,
    required this.purchasedAt,
    DateTime? openedAt,
    this.receiptId,
    this.source = 'photo',
    this.edited = false,
    this.rows = const {},
    this.measuresById = const {},
    this.coinedStores = const [],
    this.error,
  }) : openedAt = openedAt ?? purchasedAt;

  /// The saved receipt this review is open on, or null for an unsaved scan.
  /// Save rewrites it or writes a new one accordingly.
  final String? receiptId;

  /// How the receipt came to be — `photo`, or `manual` for a price typed on
  /// an ingredient's page.
  final String source;

  /// Whether anything has been changed since the review opened. A saved
  /// receipt's Save stays shut until it has.
  final bool edited;

  bool get isSaved => receiptId != null;

  /// A price typed on an ingredient's page: there was no paper.
  bool get isManual => source == 'manual';

  final ReceiptPayload payload;
  final List<ReceiptLineDraft> drafts;

  /// The household's word for the shop, picked from the chips. Empty until
  /// one is picked, which is what holds Save closed at the seam.
  final String store;

  /// The receipt's own moment, as **wall time** — the paper's, never the
  /// scan's.
  final DateTime purchasedAt;

  /// What [purchasedAt] was when the review opened. It never moves, so the
  /// screen can tell a chosen date from an untouched one.
  final DateTime openedAt;

  /// The matched vocabulary rows, by id. A row the device cannot find is
  /// absent, and its line reads as unmatched.
  final Map<String, Ingredient> rows;

  final Map<String, List<Measure>> measuresById;

  /// A store named through `＋` in this sitting. It joins the chip row at once
  /// and is remembered only when Save lands.
  final List<String> coinedStores;

  /// Why the last Save or Delete did not happen, drawn over Save. Any edit
  /// clears it.
  final String? error;

  /// The review unchanged, with [message] over its Save.
  ReceiptReviewing withError(String message) => ReceiptReviewing(
    payload: payload,
    drafts: drafts,
    store: store,
    purchasedAt: purchasedAt,
    openedAt: openedAt,
    receiptId: receiptId,
    source: source,
    edited: edited,
    rows: rows,
    measuresById: measuresById,
    coinedStores: coinedStores,
    error: message,
  );

  /// The review's one map: the header count, the flags, the join and Save all
  /// read it. A hand-typed receipt has no printed totals to check against.
  ReceiptReviewMap get map => receiptReviewMap(
    drafts,
    printedSubtotalCents: isManual ? null : payload.subtotalCents,
    printedTaxCents: isManual ? null : payload.taxCents,
    printedTotalCents: isManual ? null : payload.totalCents,
  );

  ReceiptReviewing copyWith({
    List<ReceiptLineDraft>? drafts,
    String? store,
    DateTime? purchasedAt,
    Map<String, Ingredient>? rows,
    Map<String, List<Measure>>? measuresById,
    List<String>? coinedStores,
  }) => ReceiptReviewing(
    payload: payload,
    drafts: drafts ?? this.drafts,
    store: store ?? this.store,
    purchasedAt: purchasedAt ?? this.purchasedAt,
    openedAt: openedAt,
    receiptId: receiptId,
    source: source,
    // Rows and measures arriving under a match are part of that edit, so
    // every copy is one.
    edited: true,
    // No `error`: it was about the write that failed, and an edit answers it.
    rows: rows ?? this.rows,
    measuresById: measuresById ?? this.measuresById,
    coinedStores: coinedStores ?? this.coinedStores,
  );
}

/// A saved receipt is being read back into the review.
class ReceiptOpening extends ReceiptScanState {
  const ReceiptOpening();
}

/// The saved receipt asked for is not there — deleted here, or on the other
/// phone.
class ReceiptGone extends ReceiptScanState {
  const ReceiptGone();
}

/// Save is writing through PowerSync.
class ReceiptSaving extends ReceiptScanState {
  const ReceiptSaving();
}

/// Saved; [receiptId] is the new receipt, and the ledger opens on it.
class ReceiptSaved extends ReceiptScanState {
  const ReceiptSaved(this.receiptId);
  final String receiptId;
}

/// The read or the save failed; [message] is the sentence a person reads.
class ReceiptScanFailed extends ReceiptScanState {
  const ReceiptScanFailed(this.message);
  final String message;
}

@riverpod
class ReceiptScanController extends _$ReceiptScanController {
  @override
  ReceiptScanState build() {
    ref.onDispose(_stopStageLadder);
    return const ReceiptIdle();
  }

  /// True while a read is in flight. Reading is a billed model call, so a
  /// double-tapped door must not fire two of them.
  bool _reading = false;

  Timer? _stageTimer;
  static const _stageTick = Duration(seconds: 1);

  List<PipelineStage> _plan = const [];
  final Map<PipelineStage, Duration> _finished = {};
  Duration _elapsed = Duration.zero;

  void _startStageClock() {
    _stageTimer?.cancel();
    _plan = const [];
    _finished.clear();
    _elapsed = Duration.zero;
    _publishStages();
    _stageTimer = Timer.periodic(_stageTick, (timer) {
      if (!ref.mounted || state is! ReceiptReading) {
        timer.cancel();
        return;
      }
      _elapsed += _stageTick;
      _publishStages();
    });
  }

  void _onProgress(ReceiptProgress progress) {
    if (!ref.mounted || state is! ReceiptReading) return;
    switch (progress) {
      case ReceiptPlanned(:final stages):
        _plan = stages;
      case ReceiptStageDone(:final stage, :final elapsed):
        _finished[stage] = elapsed;
        // The server's clock is the authority on how far in we are; a local
        // one left behind it would start the running row negative.
        if (elapsed > _elapsed) _elapsed = elapsed;
    }
    _publishStages();
  }

  void _publishStages() => state = ReceiptReading(
    stageChecklist(plan: _plan, finished: _finished, elapsed: _elapsed),
  );

  void _stopStageLadder() {
    _stageTimer?.cancel();
    _stageTimer = null;
  }

  /// Reads [photos] and opens the review. A second call while the first is in
  /// flight is a no-op.
  Future<void> scan(ReceiptPhotos photos) async {
    if (_reading) return;
    _reading = true;
    _startStageClock();
    try {
      final reader = ref.read(receiptImportRepositoryProvider);
      final vocabRepo = ref.read(ingredientRepositoryProvider);
      final measureRepo = ref.read(measureRepositoryProvider);
      final priceRepo = ref.read(priceRepositoryProvider);
      final payload = await reader.readReceipt(photos, onProgress: _onProgress);
      // Asked of the repository, not the store-words provider: that stream has
      // usually not emitted when a scan starts.
      final stores = await _storeWords(priceRepo);
      final drafts = initialReceiptDrafts(payload);
      final landed = await _landPacks(
        drafts,
        vocabRepo: vocabRepo,
        measureRepo: measureRepo,
        priceRepo: priceRepo,
      );
      if (!ref.mounted) return;
      state = ReceiptReviewing(
        payload: payload,
        drafts: landed.drafts,
        rows: landed.rows,
        measuresById: landed.measuresById,
        // The chip row opens on the household's own word for the store; the
        // printed line sits under it.
        store: _storeFor(payload, stores),
        // The receipt's printed date, else the day of the scan, which the
        // review says.
        purchasedAt: payload.purchasedAt ?? DateTime.now(),
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ReceiptScanFailed('$e');
    } finally {
      _stopStageLadder();
      _reading = false;
    }
  }

  /// Opens the review on the saved receipt [receiptId], in the same state a
  /// scan opens. No pack is landed: re-deriving a stored pack from a later shop
  /// would re-price this one.
  Future<void> open(String receiptId) async {
    final current = state;
    if (current is ReceiptReviewing && current.receiptId == receiptId) return;
    final repository = ref.read(receiptRepositoryProvider);
    final vocabRepo = ref.read(ingredientRepositoryProvider);
    final measureRepo = ref.read(measureRepositoryProvider);
    state = const ReceiptOpening();
    try {
      final stored = await repository.watchReceipt(receiptId).first;
      if (!ref.mounted) return;
      if (stored == null) {
        state = const ReceiptGone();
        return;
      }
      final drafts = [
        for (final (index, line) in stored.lines.indexed)
          storedLineDraft(line, index: index),
      ];
      final ids = {
        for (final d in drafts)
          if (d.ingredientId != null) d.ingredientId!,
      };
      var rows = const <String, Ingredient>{};
      var measures = const <String, List<Measure>>{};
      if (ids.isNotEmpty) {
        try {
          rows = await vocabRepo.byIds(ids);
          measures = await measureRepo.measuresByIngredients(ids);
        } on Object {
          // The lines still read — name, money and pack are on the join —
          // and a card simply cannot reopen its pack door until they load.
        }
      }
      if (!ref.mounted) return;
      state = ReceiptReviewing(
        payload: ReceiptPayload(
          lines: const [],
          purchasedAt: stored.purchasedAt,
          subtotalCents: stored.subtotalCents,
          taxCents: stored.taxCents,
          totalCents: stored.totalCents,
        ),
        drafts: drafts,
        store: stored.store,
        purchasedAt: stored.purchasedAt,
        receiptId: stored.id,
        source: stored.source,
        rows: rows,
        measuresById: measures,
      );
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = ReceiptScanFailed('Could not open this receipt: $e');
    }
  }

  /// Takes the open saved receipt back, lines and all.
  Future<void> delete() async {
    final s = state;
    if (s is! ReceiptReviewing || s.receiptId == null) return;
    final repository = ref.read(receiptRepositoryProvider);
    state = const ReceiptSaving();
    try {
      await repository.deleteReceipt(s.receiptId!);
      if (!ref.mounted) return;
      state = const ReceiptGone();
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = s.withError('Could not delete this receipt: $e');
    }
  }

  static Future<List<String>> _storeWords(PriceRepository repo) async {
    try {
      return await repo.watchStores().first;
    } on Object {
      return const [];
    }
  }

  /// The household word the chips open on: the one the paper's header carries,
  /// else the most recent. With none, the review holds Save until a store is
  /// named.
  static String _storeFor(ReceiptPayload payload, List<String> stores) {
    final printed = payload.storePrinted?.toLowerCase() ?? '';
    for (final word in stores) {
      final letters = word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
      if (letters.isNotEmpty &&
          printed.replaceAll(RegExp('[^a-z]'), '').contains(letters)) {
        return word;
      }
    }
    return stores.isEmpty ? '' : stores.first;
  }

  void pickStore(String word) {
    final s = state;
    if (s is! ReceiptReviewing) return;
    state = s.copyWith(
      store: word.trim(),
      coinedStores: s.coinedStores.contains(word.trim()) || word.trim().isEmpty
          ? s.coinedStores
          : [word.trim(), ...s.coinedStores],
    );
  }

  void setPurchasedAt(DateTime wall) {
    final s = state;
    if (s is! ReceiptReviewing) return;
    state = s.copyWith(purchasedAt: wall);
  }

  /// Replaces the draft at [index] through [update].
  void _updateLine(
    int index,
    ReceiptLineDraft Function(ReceiptLineDraft) update,
  ) => _updateLines({index}, update);

  /// Replaces every draft in [indexes] through [update] — one state, so six
  /// twins move in one rebuild.
  void _updateLines(
    Set<int> indexes,
    ReceiptLineDraft Function(ReceiptLineDraft) update,
  ) {
    final s = state;
    if (s is! ReceiptReviewing) return;
    state = s.copyWith(
      drafts: [
        for (final d in s.drafts)
          if (indexes.contains(d.index)) update(d) else d,
      ],
    );
  }

  /// The line at [index] and its identical twins, read before an answer is
  /// applied, since the answer ends their being identical.
  Set<int> _answeredWith(int index) {
    final s = state;
    return s is ReceiptReviewing ? linesAnsweredWith(s.drafts, index) : {index};
  }

  /// Matches the line to [row], then lands the pack it can state without
  /// asking: the paper's printed weight, else the pack its printed words were
  /// last bought in as this row, else the row's last pack anywhere. The match
  /// is applied first and never waits on the reads.
  Future<void> matchLine(int index, Ingredient row) async {
    final s = state;
    if (s is! ReceiptReviewing) return;
    // One answer for the line and for every line that is it again.
    final answered = _answeredWith(index);
    _updateLines(
      answered,
      (d) => d
          .copyWith(clearMatch: true)
          .copyWith(ingredientId: row.id, ingredientName: row.canonicalName),
    );
    final measureRepo = ref.read(measureRepositoryProvider);
    final priceRepo = ref.read(priceRepositoryProvider);
    final measures = await _measuresFor(row.id, measureRepo);
    // The answered lines' printed words, in one read.
    final byName = await _packsByPrintedName(
      s.drafts.where((d) => answered.contains(d.index)),
      priceRepo,
    );
    final last = await _lastPriceFor(row.id, priceRepo);
    if (!ref.mounted) return;
    final now = state;
    if (now is! ReceiptReviewing) return;
    state = now.copyWith(
      rows: {...now.rows, row.id: row},
      measuresById: {...now.measuresById, row.id: measures},
      drafts: [
        for (final d in now.drafts)
          if (answered.contains(d.index) && d.ingredientId == row.id)
            landPack(
              d,
              ingredient: row,
              measures: measures,
              sameName: byName[printedNameKey(d.namePrinted)],
              last: last,
            )
          else
            d,
      ],
    );
  }

  /// Adds a line the reader missed: matched to [row] at [cents], counting one,
  /// with the pack [row] was last bought in. The line is added first and never
  /// waits on the read.
  Future<void> addLine(Ingredient row, int cents) async {
    final s = state;
    if (s is! ReceiptReviewing || cents <= 0) return;
    final added = handAddedLine(s.drafts, row: row, cents: cents);
    state = s.copyWith(
      drafts: [...s.drafts, added],
      rows: {...s.rows, row.id: row},
    );
    final measureRepo = ref.read(measureRepositoryProvider);
    final priceRepo = ref.read(priceRepositoryProvider);
    final measures = await _measuresFor(row.id, measureRepo);
    final last = await _lastPriceFor(row.id, priceRepo);
    if (!ref.mounted) return;
    final now = state;
    if (now is! ReceiptReviewing) return;
    state = now.copyWith(
      measuresById: {...now.measuresById, row.id: measures},
      drafts: [
        for (final d in now.drafts)
          if (d.index == added.index)
            landPack(d, ingredient: row, measures: measures, last: last)
          else
            d,
      ],
    );
  }

  /// Removes a line added by hand in this sitting outright; no row holds it. A
  /// saved line is dropped like any other.
  void removeLine(int index) {
    final s = state;
    if (s is! ReceiptReviewing) return;
    state = s.copyWith(
      drafts: [
        for (final d in s.drafts)
          if (d.index != index) d,
      ],
    );
  }

  /// The vocabulary row behind a did-you-mean chip, read fresh. Null when this
  /// device can no longer find the row, and the chip then does nothing.
  Future<Ingredient?> rowFor(String ingredientId) async {
    final s = state;
    if (s is ReceiptReviewing) {
      final held = s.rows[ingredientId];
      if (held != null) return held;
    }
    try {
      return await ref.read(ingredientRepositoryProvider).byId(ingredientId);
    } on Object {
      return null;
    }
  }

  /// Sets what a line rang up as, typed by hand. Only the printed figure moves;
  /// the printed deduction stays.
  void setCents(int index, int cents) =>
      _updateLine(index, (d) => d.withCents(cents));

  /// Sets how many of the thing this line rang up. It applies to one line only,
  /// unlike a match: twins each printed their own count.
  void setCount(int index, int count) {
    if (count < 1) return;
    _updateLine(index, (d) => d.copyWith(count: count));
  }

  /// The *Say what the pack is* door's answer: what the cents bought, in both
  /// denominations, and the word to mint where the person asked for one.
  void setPack(
    int index, {
    required double amount,
    required UnitChoice choice,
    required double basisAmount,
    String? keepAsMeasure,
  }) {
    final entered = packAsEntered(amount, choice);
    _updateLines(
      _answeredWith(index),
      (d) => d
          .copyWith(clearPack: true, clearKeepAsMeasure: true)
          .copyWith(
            packBasisAmount: basisAmount,
            packAmount: entered.amount,
            packUnit: switch (choice) {
              UnitOption(:final unit) => unit,
              MeasureOption() => null,
              RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
                measure,
              ),
            },
            measureId: entered.measureId,
            packLabel: switch (choice) {
              MeasureOption(:final measure) => measure.label,
              UnitOption() => null,
              RecipeMeasureOption(:final measure) => notAWordForAnIngredient(
                measure,
              ),
            },
            keepAsMeasure: keepAsMeasure,
          ),
    );
  }

  /// *Not food* — the line folds under the list, keeps its cents, and loses
  /// its claim to be a price. Nothing about the paper changes.
  void fold(int index) => _updateLines(
    _answeredWith(index),
    (d) => d.copyWith(kind: ReceiptKind.notFood, clearMatch: true),
  );

  /// A folded line comes back as a food item.
  void unfold(int index) => _updateLines(
    _answeredWith(index),
    (d) => d.copyWith(kind: ReceiptKind.item),
  );

  void drop(int index) => _updateLine(index, (d) => d.copyWith(dropped: true));

  void undrop(int index) =>
      _updateLine(index, (d) => d.copyWith(dropped: false));

  /// Writes the receipt and its lines. Does nothing while the map says a line
  /// still needs an answer or every line is dropped. A failed write returns to
  /// this review with the reason over Save and every answer kept.
  Future<void> save() async {
    final s = state;
    if (s is! ReceiptReviewing) return;
    if (!s.map.canSave || s.store.trim().isEmpty) return;
    final repository = ref.read(receiptRepositoryProvider);
    final write = buildReceiptSave(
      store: s.store,
      purchasedAt: s.purchasedAt,
      drafts: s.drafts,
      subtotalCents: s.payload.subtotalCents,
      taxCents: s.payload.taxCents,
      totalCents: s.payload.totalCents,
    );
    state = const ReceiptSaving();
    try {
      final saved = s.receiptId;
      if (saved != null) {
        await repository.updateReceipt(saved, write);
        if (!ref.mounted) return;
        // Reopened from the rows just written, so what is on screen is what
        // was kept — the new lines now carry their ids — and Save shuts.
        await open(saved);
        return;
      }
      final id = await repository.saveReceipt(write);
      if (!ref.mounted) return;
      state = ReceiptSaved(id);
    } on Object catch (e) {
      if (!ref.mounted) return;
      state = s.withError('Could not save this receipt: $e');
    }
  }

  /// The pack every arriving line can state without asking. The rows, measures,
  /// packs by printed name and latest prices are each read once for the whole
  /// receipt.
  Future<_LandedPacks> _landPacks(
    List<ReceiptLineDraft> drafts, {
    required IngredientRepository vocabRepo,
    required MeasureRepository measureRepo,
    required PriceRepository priceRepo,
  }) async {
    final ids = {
      for (final d in drafts)
        if (d.ingredientId != null) d.ingredientId!,
    };
    if (ids.isEmpty) return _nothingLanded(drafts);
    Map<String, Ingredient> rows;
    Map<String, List<Measure>> measures;
    Map<String, PackLastBoughtAs> byName;
    Map<String, PriceObservation> latest;
    try {
      rows = await vocabRepo.byIds(ids);
      measures = await measureRepo.measuresByIngredients(ids);
      byName = await _packsByPrintedName(
        drafts.where((d) => d.ingredientId != null),
        priceRepo,
      );
      latest = await priceRepo.watchLatestPrices().first;
    } on Object {
      // A failed read leaves every line as the server proposed it; the cards
      // then ask for their packs.
      return _nothingLanded(drafts);
    }
    return (
      drafts: [
        for (final d in drafts)
          if (d.ingredientId case final id?)
            landPack(
              // A match at a row this device cannot find reads as unmatched:
              // a tombstone has no name to print and nothing honest to price.
              rows.containsKey(id) ? d : d.copyWith(clearMatch: true),
              ingredient: rows[id],
              measures: measures[id] ?? const [],
              sameName: byName[printedNameKey(d.namePrinted)],
              last: latest[id],
            ).copyWith(ingredientName: rows[id]?.canonicalName)
          else
            d,
      ],
      rows: rows,
      measuresById: measures,
    );
  }

  static _LandedPacks _nothingLanded(List<ReceiptLineDraft> drafts) => (
    drafts: drafts,
    rows: const <String, Ingredient>{},
    measuresById: const <String, List<Measure>>{},
  );

  Future<List<Measure>> _measuresFor(String id, MeasureRepository repo) async {
    try {
      return (await repo.measuresByIngredients({id}))[id] ?? const [];
    } on Object {
      return const [];
    }
  }

  /// The pack each of [drafts]'s printed names was last bought in, in one read.
  /// A failed read answers with nothing, and lines fall back to their row's
  /// last pack.
  static Future<Map<String, PackLastBoughtAs>> _packsByPrintedName(
    Iterable<ReceiptLineDraft> drafts,
    PriceRepository repo,
  ) async {
    final names = {
      for (final d in drafts)
        if (d.namePrinted case final printed?) printed,
    };
    if (names.isEmpty) return const {};
    try {
      return await repo.packsByPrintedName(names);
    } on Object {
      return const {};
    }
  }

  Future<PriceObservation?> _lastPriceFor(
    String id,
    PriceRepository repo,
  ) async {
    try {
      final prices = await repo.watchPrices(id).first;
      return prices.isEmpty ? null : prices.first;
    } on Object {
      return null;
    }
  }
}

/// A stored line as the review's own draft — one shape for a receipt line,
/// fresh off a scan or read back from the ledger.
ReceiptLineDraft storedLineDraft(
  StoredReceiptLine line, {
  required int index,
}) => ReceiptLineDraft(
  index: index,
  lineId: line.id,
  printedText: line.printedText,
  namePrinted: line.namePrinted,
  cents: line.cents,
  count: line.count,
  discountCents: line.discountCents,
  kind: ReceiptKind.fromWire(line.kind),
  ingredientId: line.ingredientId,
  ingredientName: line.ingredientName,
  packBasisAmount: line.packBasisAmount,
  packAmount: line.packAmount,
  packUnit: unitById(line.packUnit ?? ''),
  measureId: line.measureId,
  packLabel: line.measureLabel,
);
