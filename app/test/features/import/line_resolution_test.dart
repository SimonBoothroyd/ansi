import 'package:flutter_test/flutter_test.dart';
import 'package:mise/core/units/measure.dart';
import 'package:mise/core/units/units.dart';
import 'package:mise/features/import/domain/line_resolution.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/ingredients/domain/allowed_units.dart';

ReconLine _line(
  String text, {
  MatchBand band = MatchBand.none,
  double? qty,
  double? qtyLow,
  double? qtyHigh,
  String? unit,
  List<MatchCandidate> candidates = const [],
  bool optional = false,
  bool unitMappable = true,
  double confidence = 1,
}) => ReconLine(
  raw: RawLineItem(
    ingredientText: text,
    qty: qty,
    qtyLow: qtyLow,
    qtyHigh: qtyHigh,
    unit: unit,
    optional: optional,
    unitMappable: unitMappable,
    confidence: confidence,
  ),
  band: band,
  candidates: candidates,
);

ReconciliationPayload _payload(List<ReconLine> lines) => ReconciliationPayload(
  title: 'T',
  servingsBase: 2,
  groups: [ReconGroup(lines: lines)],
);

const _cand = MatchCandidate(
  ingredientId: 'ing-onion',
  canonicalName: 'Onion',
  score: 0.9,
);

void main() {
  group('initial band handling', () {
    test('auto adopts the top candidate', () {
      final r = initialResolution(
        0,
        _line('onion', band: MatchBand.auto, qty: 1, candidates: [_cand]),
      );
      expect(r.chosenIngredientId, 'ing-onion');
      expect(r.isCorrection, isFalse);
      expect(r.isResolved, isTrue);
    });

    test('suggest does NOT auto-adopt — it surfaces candidates to confirm', () {
      // Band-based lock (round-3): only the `auto` band (the automatch tier)
      // locks the ingredient. `suggest` (mid-confidence) surfaces "did you
      // mean" pills for the user to confirm.
      final r = initialResolution(
        0,
        _line('onion', band: MatchBand.suggest, qty: 1, candidates: [_cand]),
      );
      expect(r.chosenIngredientId, isNull);
      expect(r.isResolved, isFalse);
    });

    test('an auto line locks its ingredient even while its RANGE is unpicked '
        '(ingredient lock ⟂ amount — round-3 #4)', () {
      final r = initialResolution(
        0,
        _line('garlic', band: MatchBand.auto, qtyLow: 2, qtyHigh: 3,
            candidates: [_cand]),
      );
      // Locked on the exact/auto match…
      expect(r.chosenIngredientId, 'ing-onion');
      // …while the amount stays open (the range only blocks Save, not the
      // ingredient match).
      expect(r.isRange && r.quantity == null, isTrue);
      expect(r.isResolved, isFalse);
    });

    test('none starts unresolved', () {
      final r = initialResolution(0, _line('mystery spice', qty: 1));
      expect(r.chosenIngredientId, isNull);
      expect(r.createStubName, isNull);
      expect(r.isResolved, isFalse);
    });
  });

  group('range resolution', () {
    test('a range is unresolved until a number is picked', () {
      final r = initialResolution(
        0,
        _line(
          'garlic',
          band: MatchBand.auto,
          qtyLow: 2,
          qtyHigh: 3,
          candidates: [_cand],
        ),
      );
      expect(r.isRange, isTrue);
      expect(r.quantity, isNull);
      expect(r.isResolved, isFalse); // has an ingredient, but no picked number

      final picked = r.pickQuantity(3);
      expect(picked.quantity, 3);
      expect(picked.isResolved, isTrue);
    });
  });

  group('create-new + coalescing', () {
    test('identical no-match lines coalesce onto one stub', () {
      final payload = _payload([
        _line('Aleppo chilli flakes'),
        _line('Aleppo chilli flakes'),
        _line('fresh basil'),
      ]);
      final resolutions = [
        initialResolution(
          0,
          payload.flatLines[0],
        ).resolveToNewStub('Aleppo chilli flakes'),
        initialResolution(
          1,
          payload.flatLines[1],
        ).resolveToNewStub('Aleppo chilli flakes'),
        initialResolution(2, payload.flatLines[2]).resolveToNewStub('basil'),
      ];

      final commit = buildCommit(payload, resolutions, servingsBase: 2);
      // Two distinct stubs: the duplicate chilli lines share one.
      expect(commit.stubs, hasLength(2));
      final lines = commit.groups.single.lines;
      expect(lines[0].stubKey, lines[1].stubKey);
      expect(lines[0].stubKey, isNot(lines[2].stubKey));
      // No stub line carries an ingredientId (it's created at write).
      expect(lines.every((l) => l.ingredientId == null), isTrue);
    });
  });

  group('corrections → alias write-back', () {
    test('a user override records an alias, but a candidate does not', () {
      final payload = _payload([
        _line(
          'yellow onion',
          band: MatchBand.auto,
          qty: 1,
          candidates: [_cand],
        ),
        _line(
          'spring onion',
          band: MatchBand.suggest,
          qty: 1,
          candidates: [_cand],
        ),
      ]);
      final resolutions = [
        // Accept the auto match: not a correction.
        initialResolution(0, payload.flatLines[0]),
        // Override the suggestion via search: a correction.
        initialResolution(
          1,
          payload.flatLines[1],
        ).resolveToIngredient('ing-scallion', 'Scallion', correction: true),
      ];

      final commit = buildCommit(payload, resolutions, servingsBase: 2);
      expect(commit.corrections, hasLength(1));
      expect(commit.corrections.single.ingredientId, 'ing-scallion');
      expect(commit.corrections.single.aliasText, 'spring onion');
    });
  });

  group('setAmount (tap-to-edit)', () {
    test('writes a picked quantity + unit and resolves a range', () {
      final r = initialResolution(
        0,
        _line('garlic', band: MatchBand.auto, qtyLow: 2, qtyHigh: 3,
            candidates: [_cand]),
      );
      expect(r.isResolved, isFalse);
      final edited = r.setAmount(quantity: 2, unit: 'clove');
      expect(edited.quantity, 2);
      expect(edited.unit, 'clove');
      expect(edited.isResolved, isTrue);
    });

    test('a null quantity clears the number (to taste)', () {
      final r = initialResolution(
        0,
        _line('salt', band: MatchBand.auto, qty: 5, candidates: [_cand]),
      );
      final edited = r.setAmount();
      expect(edited.quantity, isNull);
      // Still resolved — a numberless auto line stays committable.
      expect(edited.isResolved, isTrue);
    });
  });

  group('sheetChoiceUnit (round-1 fix: measure chip → label, not piece)', () {
    test('a catalog unit chip rides its id', () {
      expect(
        sheetChoiceUnit(
          choice: const UnitOption(g),
          unitPicked: true,
          currentUnit: 'clove',
        ),
        'g',
      );
    });

    test('a measure chip rides its LABEL, not a degraded "piece"', () {
      // The reported bug: tapping the "clove" chip (a measure) left the line
      // reading "piece". The label must survive.
      const clove = Measure(id: 'm-clove', label: 'clove', amount: 3);
      expect(
        sheetChoiceUnit(
          choice: const MeasureOption(clove),
          unitPicked: true,
          currentUnit: 'piece',
        ),
        'clove',
      );
    });

    test('no chip tapped keeps the current unit', () {
      expect(
        sheetChoiceUnit(
          choice: const UnitOption(g),
          unitPicked: false,
          currentUnit: 'clove',
        ),
        'clove',
      );
    });

    test('pickUnit sets the unit without touching the quantity (unit ⟂ '
        'amount)', () {
      final r = initialResolution(
        0,
        _line('garlic', band: MatchBand.auto, qtyLow: 2, qtyHigh: 3,
            candidates: [_cand]),
      );
      final picked = r.pickUnit('clove');
      expect(picked.unit, 'clove');
      expect(picked.quantity, isNull); // range still open
    });

    test('a picked unit + value resolves a range through setAmount', () {
      final r = initialResolution(
        0,
        _line('garlic', band: MatchBand.auto, qtyLow: 2, qtyHigh: 3,
            candidates: [_cand]),
      );
      const clove = Measure(id: 'm-clove', label: 'clove', amount: 3);
      final unit = sheetChoiceUnit(
        choice: const MeasureOption(clove),
        unitPicked: true,
        currentUnit: r.unit,
      );
      final edited = r.setAmount(quantity: 3, unit: unit);
      expect(edited.unit, 'clove');
      expect(edited.quantity, 3);
      expect(edited.isResolved, isTrue); // range collapsed to a single qty
    });
  });

  group('setNotes (edit the line note)', () {
    final base = initialResolution(
      0,
      _line('garlic', band: MatchBand.auto, qty: 1, candidates: [_cand]),
    );

    test('stores a trimmed note', () {
      expect(base.setNotes('  finely sliced ').notes, 'finely sliced');
    });

    test('blank clears the note', () {
      expect(base.setNotes('sliced').setNotes('   ').notes, isNull);
    });

    test('editing notes leaves the ingredient + amount untouched', () {
      final edited = base.setNotes('to serve');
      expect(edited.chosenIngredientId, base.chosenIngredientId);
      expect(edited.quantity, base.quantity);
    });
  });

  group('triage: needsReview', () {
    test('a clean auto match with a number does not need review', () {
      final line = _line('pasta', band: MatchBand.auto, qty: 200, unit: 'g',
          candidates: [_cand]);
      expect(needsReview(line, initialResolution(0, line)), isFalse);
    });

    test('suggest, none, ranges, unmappable, low-confidence surface', () {
      final suggest = _line('cheese', band: MatchBand.suggest, qty: 1,
          candidates: [_cand]);
      final none = _line('mystery', qty: 1);
      final range = _line('garlic', band: MatchBand.auto, qtyLow: 2,
          qtyHigh: 3, candidates: [_cand]);
      final unmappable = _line('basil', band: MatchBand.auto, unit: 'handful',
          unitMappable: false, candidates: [_cand]);
      final shaky = _line('thing', band: MatchBand.auto, qty: 1,
          confidence: 0.5, candidates: [_cand]);
      expect(needsReview(suggest, initialResolution(0, suggest)), isTrue);
      expect(needsReview(none, initialResolution(0, none)), isTrue);
      expect(needsReview(range, initialResolution(0, range)), isTrue);
      expect(needsReview(unmappable, initialResolution(0, unmappable)), isTrue);
      expect(needsReview(shaky, initialResolution(0, shaky)), isTrue);
    });
  });

  group('triage: groupReconUses', () {
    test('same identity within a group folds to one use-group', () {
      final payload = ReconciliationPayload(
        title: 'T',
        groups: [
          ReconGroup(lines: [
            _line('Aleppo chilli flakes'),
            _line('garlic', band: MatchBand.auto, qty: 1),
            _line('Aleppo chilli flakes'),
          ]),
          ReconGroup(name: 'to serve', lines: [_line('basil')]),
        ],
      );
      final groups = groupReconUses(payload);
      // chilli (folded, 2 uses), garlic, basil.
      expect(groups, hasLength(3));
      expect(groups[0].isMultiUse, isTrue);
      expect(groups[0].lineIndexes, [0, 2]);
      expect(groups[1].lineIndexes, [1]);
      expect(groups[2].lineIndexes, [3]);
    });
  });

  group('commit gate', () {
    test('buildCommit throws while any line is unresolved', () {
      final payload = _payload([_line('mystery', qty: 1)]);
      final resolutions = initialResolutions(payload); // none, unresolved
      expect(allResolved(resolutions), isFalse);
      expect(
        () => buildCommit(payload, resolutions, servingsBase: 2),
        throwsStateError,
      );
    });

    test('flattened line order and group structure are preserved', () {
      final payload = ReconciliationPayload(
        title: 'T',
        groups: [
          ReconGroup(name: 'A', lines: [_line('x', qty: 1)]),
          ReconGroup(
            name: 'B',
            lines: [_line('y', qty: 2), _line('z', qty: 3)],
          ),
        ],
      );
      final resolutions = [
        for (var i = 0; i < payload.flatLines.length; i++)
          initialResolution(i, payload.flatLines[i]).resolveToNewStub('s$i'),
      ];
      final commit = buildCommit(payload, resolutions, servingsBase: 4);
      expect(commit.groups.map((g) => g.name), ['A', 'B']);
      expect(commit.groups.expand((g) => g.lines).map((l) => l.lineIndex), [
        0,
        1,
        2,
      ]);
    });
  });
}
