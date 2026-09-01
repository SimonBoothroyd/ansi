import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:flutter_test/flutter_test.dart';

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
        _line(
          'garlic',
          band: MatchBand.auto,
          qtyLow: 2,
          qtyHigh: 3,
          candidates: [_cand],
        ),
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

      final commit = buildCommit(
        payload,
        resolutions,
        servingsBase: 2,
        issuesByLine: null,
      );
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

      final commit = buildCommit(
        payload,
        resolutions,
        servingsBase: 2,
        issuesByLine: null,
      );
      expect(commit.corrections, hasLength(1));
      expect(commit.corrections.single.ingredientId, 'ing-scallion');
      expect(commit.corrections.single.aliasText, 'spring onion');
    });
  });

  group('setAmount (tap-to-edit)', () {
    test('writes a picked quantity + unit and resolves a range', () {
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
        _line(
          'garlic',
          band: MatchBand.auto,
          qtyLow: 2,
          qtyHigh: 3,
          candidates: [_cand],
        ),
      );
      final picked = r.pickUnit('clove');
      expect(picked.unit, 'clove');
      expect(picked.quantity, isNull); // range still open
    });

    test('a picked unit + value resolves a range through setAmount', () {
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

  group('a raw amount that is really prose routes to NOTES', () {
    test('the parenthetical lands in the note, not the amount slot', () {
      const line = ReconLine(
        raw: RawLineItem(
          ingredientText: 'Tortilla chips',
          rawAmount: '(to serve (optional))',
          optional: true,
        ),
        band: MatchBand.none,
      );
      expect(initialResolution(0, line).notes, 'to serve (optional)');
    });

    test('an extractor note is never overwritten by the amount', () {
      const line = ReconLine(
        raw: RawLineItem(
          ingredientText: 'basil',
          notes: 'torn',
          rawAmount: '(to serve)',
        ),
        band: MatchBand.none,
      );
      expect(initialResolution(0, line).notes, 'torn');
    });

    test('an amount the editor can render stays in the amount slot', () {
      // A mapped unit ("A good pinch" → pinch) and a printed number are both
      // amounts — only numberless, unmappable prose is rerouted.
      const pinchLine = ReconLine(
        raw: RawLineItem(
          ingredientText: 'chilli flakes',
          unit: 'pinch',
          rawAmount: 'A good pinch',
        ),
        band: MatchBand.none,
      );
      const tinLine = ReconLine(
        raw: RawLineItem(
          ingredientText: 'tomatoes',
          qty: 400,
          rawAmount: '1 x 400g tin',
        ),
        band: MatchBand.none,
      );
      expect(initialResolution(0, pinchLine).notes, isNull);
      expect(initialResolution(0, tinLine).notes, isNull);
    });
  });

  group('dropping a line at review', () {
    final base = initialResolution(
      0,
      _line('garlic', band: MatchBand.auto, qty: 1, candidates: [_cand]),
    );

    test('drop is reversible and edits nothing else', () {
      final dropped = base.setNotes('sliced').drop();
      expect(dropped.isDropped, isTrue);
      final back = dropped.undrop();
      expect(back.isDropped, isFalse);
      expect(back.notes, 'sliced');
      expect(back.chosenIngredientId, base.chosenIngredientId);
    });

    test('a dropped line reports no issues — it cannot hold up Save', () {
      final unmatched = initialResolution(0, _line('mystery'));
      expect(lineIssues(unmatched), [LineIssue.unmatched]);
      expect(lineIssues(unmatched.drop()), isEmpty);
    });

    test('allResolved skips a dropped line but still demands the rest', () {
      final resolutions = [
        base,
        initialResolution(1, _line('mystery')), // unresolved
      ];
      expect(allResolved(resolutions), isFalse);
      expect(allResolved([resolutions[0], resolutions[1].drop()]), isTrue);
      expect(keptLines([resolutions[0], resolutions[1].drop()]), hasLength(1));
    });

    test('buildCommit writes no line for a dropped one, and leaves its index '
        'unused so a step ref demotes instead of pointing elsewhere', () {
      final payload = _payload([
        _line('garlic', band: MatchBand.auto, qty: 1, candidates: [_cand]),
        _line('basil', band: MatchBand.auto, qty: 1, candidates: [_cand]),
        _line('parsley', band: MatchBand.auto, qty: 1, candidates: [_cand]),
      ]);
      final resolutions = [
        initialResolution(0, payload.flatLines[0]),
        initialResolution(1, payload.flatLines[1]).drop(),
        initialResolution(2, payload.flatLines[2]),
      ];
      final commit = buildCommit(
        payload,
        resolutions,
        servingsBase: 2,
        issuesByLine: null,
      );
      final lines = commit.groups.single.lines;
      expect(lines.map((l) => l.lineIndex), [0, 2]);
    });

    test('a dropped line drags no correction or stub along with it', () {
      final payload = _payload([
        _line('yellow onion', band: MatchBand.auto, qty: 1, candidates: []),
        _line('mystery', qty: 1),
      ]);
      final resolutions = [
        initialResolution(0, payload.flatLines[0])
            .resolveToIngredient('ing-scallion', 'Scallion', correction: true)
            .drop(),
        initialResolution(1, payload.flatLines[1]).resolveToNewStub('Mystery'),
      ];
      final commit = buildCommit(
        payload,
        resolutions,
        servingsBase: 2,
        issuesByLine: null,
      );
      expect(commit.corrections, isEmpty);
      expect(commit.stubs, hasLength(1));
    });

    test('a group whose every line was dropped is not written', () {
      final payload = ReconciliationPayload(
        title: 'T',
        groups: [
          ReconGroup(name: 'A', lines: [_line('x', qty: 1)]),
          ReconGroup(name: 'B', lines: [_line('y', qty: 2)]),
        ],
      );
      final commit = buildCommit(
        payload,
        [
          initialResolution(0, payload.flatLines[0]).resolveToNewStub('X'),
          initialResolution(
            1,
            payload.flatLines[1],
          ).resolveToNewStub('Y').drop(),
        ],
        servingsBase: 2,
        issuesByLine: null,
      );
      expect(commit.groups.map((g) => g.name), ['A']);
    });

    test('a dropped line’s stale issues do not block the commit', () {
      final payload = _payload([
        _line('garlic', band: MatchBand.auto, qty: 1, candidates: [_cand]),
      ]);
      final resolutions = [initialResolution(0, payload.flatLines[0]).drop()];
      // Nothing survives → refused, but for the honest reason.
      expect(
        () => buildCommit(
          payload,
          resolutions,
          servingsBase: 2,
          issuesByLine: const {
            0: [LineIssue.unitNotAllowed],
          },
        ),
        throwsA(
          isStateError.having(
            (e) => e.message,
            'message',
            contains('nothing to save'),
          ),
        ),
      );
    });
  });

  group('commit gate', () {
    test('buildCommit throws while any line is unresolved', () {
      final payload = _payload([_line('mystery', qty: 1)]);
      final resolutions = initialResolutions(payload); // none, unresolved
      expect(allResolved(resolutions), isFalse);
      expect(
        () => buildCommit(
          payload,
          resolutions,
          servingsBase: 2,
          issuesByLine: null,
        ),
        throwsStateError,
      );
    });

    test('buildCommit throws when a resolved line is still INVALID', () {
      // Unit validity used to live only in the view's disabled Save button, so
      // this function's doc claimed an invariant it did not enforce.
      final payload = _payload([
        _line('garlic', band: MatchBand.auto, qty: 1, candidates: [_cand]),
      ]);
      final resolutions = initialResolutions(payload);
      expect(allResolved(resolutions), isTrue);
      expect(
        () => buildCommit(
          payload,
          resolutions,
          servingsBase: 2,
          issuesByLine: const {
            0: [LineIssue.unitNotAllowed],
          },
        ),
        throwsStateError,
      );
      // A clean map commits.
      expect(
        buildCommit(
          payload,
          resolutions,
          servingsBase: 2,
          issuesByLine: const {0: <LineIssue>[]},
        ).groups.single.lines,
        hasLength(1),
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
      final commit = buildCommit(
        payload,
        resolutions,
        servingsBase: 4,
        issuesByLine: null,
      );
      expect(commit.groups.map((g) => g.name), ['A', 'B']);
      expect(commit.groups.expand((g) => g.lines).map((l) => l.lineIndex), [
        0,
        1,
        2,
      ]);
    });
  });
}
