/// The scan session: photos → the reading checklist → the review → Save.
///
/// One controller holds the whole sitting, exactly as the recipe import's
/// does, and for the same reason: **nothing is written until Save**, so the
/// review is state and not a half-written row. Backing out of the screen
/// leaves the ledger as it was.
///
/// It is `autoDispose` (the default), so a person can leave mid-read — and in
/// Riverpod 3 writing `state` on a disposed notifier throws, in release too.
/// Every post-await assignment here is guarded by [Ref.mounted], and every
/// repository is read BEFORE the first await, because `ref` does not survive
/// this notifier's disposal.
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

/// `import-receipt` is running. [rows] is the checklist the server's own
/// events built; empty until the plan arrives, because before then there is
/// nothing true to draw.
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

  /// The saved receipt this review is open on, or null for a scan nobody has
  /// saved yet. It is the ONE difference between the two: the same screen
  /// confirms a fresh read and corrects a kept one, and Save writes a new
  /// receipt or rewrites this one accordingly.
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

  /// What [purchasedAt] was when the review opened — read off the paper, or
  /// the day of the scan. It never moves, so the screen can tell a date
  /// somebody chose from one nobody has looked at.
  final DateTime openedAt;

  /// The matched vocabulary rows, by id — what the cards read a basis and a
  /// density off. A row the device cannot find is simply absent, and its line
  /// reads as unmatched, which is the honest thing for a match at a row
  /// retired since the server answered.
  final Map<String, Ingredient> rows;

  final Map<String, List<Measure>> measuresById;

  /// A store named through `＋` but not written anywhere yet. It belongs in
  /// the chip row from the moment it is typed and becomes a remembered word
  /// only when Save lands the receipt that used it.
  final List<String> coinedStores;

  /// Why the last Save or Delete did not happen, drawn over Save. A write
  /// that fails changes nothing else: every answer is still here — a read is
  /// billed for — and Save is still there to try again. Any edit clears it.
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

  /// The review's one map — the header count, the flags, the join and Save
  /// all read this. A hand-typed receipt printed nothing, so its lines are
  /// held against nothing.
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
      // Asked of the REPOSITORY, not of the store-words provider: that
      // provider is a stream, and at the moment a scan starts it has usually
      // not emitted yet — reading it would open the chips on nothing and
      // hold Save shut over a household that has shopped for months.
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
        // The store the paper printed is NOT the household's word for it. The
        // chip row opens on the word this household used last, and the
        // printed line sits under it as what the paper said.
        store: _storeFor(payload, stores),
        // The receipt's own date where it printed one, and the day of the
        // scan where it did not — which the review says, rather than
        // inventing a Sunday.
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

  /// Opens the review on the SAVED receipt [receiptId] — the same state a
  /// scan opens, built from the rows instead of from a payload, so a kept
  /// receipt is corrected on the screen it was confirmed on.
  ///
  /// No pack is landed here: a stored line's pack is what was said at the
  /// time, and re-deriving it from a later shop would re-price this one.
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

  /// The household word the chips open on: the one whose letters the paper's
  /// header carries, else the most recent. A store never seen before is the
  /// `＋`, and until somebody taps it the review holds Save.
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

  /// The line at [index] and every line that is it again, as they stand NOW —
  /// read before an answer is applied, because the answer is what stops them
  /// being identical to anything unanswered.
  Set<int> _answeredWith(int index) {
    final s = state;
    return s is ReceiptReviewing ? linesAnsweredWith(s.drafts, index) : {index};
  }

  /// Answers *Match an ingredient*: the line takes [row], and then the pack
  /// it can state without asking — the paper's printed weight, else the pack
  /// its own printed words were last bought in as this row, else the pack this
  /// row was last bought in anywhere.
  ///
  /// The match is applied FIRST and never waits on the reads: it is the
  /// person's act, and a lookup must not be able to lose it.
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
    // The answered lines' own printed words, asked for in ONE read: twins each
    // carry the words their card is titled with, and they all land the pack
    // filed under them.
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

  /// The vocabulary row behind a did-you-mean chip, read fresh.
  ///
  /// The chip carries the server's id and its word for the row; the match has
  /// to be made against the row **this device** can still find, because a row
  /// retired since the server answered has no name to print and nothing
  /// honest to price. Null is the answer for one, and the chip does nothing.
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

  /// The *Set the amount* door's answer: what a line the reader could not
  /// make out actually rang up as, read off the paper by a person.
  ///
  /// Only the printed figure moves. The deduction printed under the item is
  /// the paper's and is left exactly where it was.
  void setCents(int index, int cents) =>
      _updateLine(index, (d) => d.withCents(cents));

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

  /// *It is food* — a line under the fold comes back as an item, whether the
  /// paper called it one or a person folded it. There is nothing else it
  /// could come back as: the fold holds exactly the lines that are not food,
  /// and saying one of them is food is the only thing the door means.
  void unfold(int index) => _updateLines(
    _answeredWith(index),
    (d) => d.copyWith(kind: ReceiptKind.item),
  );

  void drop(int index) => _updateLine(index, (d) => d.copyWith(dropped: true));

  void undrop(int index) =>
      _updateLine(index, (d) => d.copyWith(dropped: false));

  /// Writes the receipt and its lines. Refuses quietly while the map says a
  /// line still needs somebody, or while every line is dropped — the button is
  /// already shut, and `saveReceipt` re-asserts the store at the seam.
  ///
  /// A write that fails returns to this same review with the reason over
  /// Save: nothing a person answered, and nothing the read was billed for, is
  /// thrown away by a failure they can try again.
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

  /// The pack every arriving line can state without asking, with the rows, the
  /// measures, the packs filed under the printed names and the rows' latest
  /// prices each read ONCE for the whole receipt rather than per line.
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
      // A read that fails leaves every line exactly as the server proposed
      // it: the review still works, and the cards simply ask for the packs
      // they could otherwise have stated.
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

  /// The pack each of [drafts]'s printed names was last bought in — ONE read
  /// for the whole receipt, however many lines carry words.
  ///
  /// A read that fails answers with nothing, and every line falls through to
  /// the pack its row was last bought in: a carry-over lost, never a wrong one.
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
