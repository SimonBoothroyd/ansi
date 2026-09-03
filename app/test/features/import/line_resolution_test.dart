import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gold_fixture.dart';

/// The header draft as the review hands it to `buildCommit` (plan 0025 #4):
/// the page's own title and times, the serving count and yield the test
/// states. Explicit rather than `headerDraft`, so a test says exactly what
/// the header held.
Recipe _header(
  ReconciliationPayload payload, {
  double servingsBase = 2,
  double? yieldQty,
  Unit? yieldUnit,
}) => Recipe(
  id: 'draft',
  title: payload.title,
  servingsBase: servingsBase,
  yieldQty: yieldQty,
  yieldUnit: yieldUnit,
  cookTimeSeconds: payload.cookTimeSeconds?.lowSeconds,
  totalTimeSeconds: payload.totalTimeSeconds?.lowSeconds,
);

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
        header: _header(payload),
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
        header: _header(payload),
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
        header: _header(payload),
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
        header: _header(payload),
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
        header: _header(payload),
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
          header: _header(payload),
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
          header: _header(payload),
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
          header: _header(payload),
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
          header: _header(payload),
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
        header: _header(payload, servingsBase: 4),
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

  // --- Step 8.6 / D6: a recipe is OFFERED at review, never auto-linked ------

  group('linking a line to a household recipe (D6)', () {
    ReconciliationPayload aioliPayload() => _payload([
      const ReconLine(
        raw: RawLineItem(
          ingredientText: 'Romesco Aioli (page 38)',
          qty: 0.25,
          unit: 'cup',
          rawAmount: '¼ cup',
        ),
        band: MatchBand.suggest,
        candidates: [
          MatchCandidate(ingredientId: 'v-aioli', canonicalName: 'Aioli'),
        ],
        recipeCandidates: [
          RecipeCandidate(
            recipeId: 'r-aioli',
            title: 'Romesco Aioli',
            score: 1,
          ),
        ],
      ),
    ]);

    test(
      'a recipe candidate is NEVER adopted on arrival — even at score 1',
      () {
        final r = initialResolution(0, aioliPayload().flatLines[0]);
        expect(r.linkedRecipeId, isNull);
        expect(r.isComponent, isFalse);
        // And it is not silently matched to the ingredient candidate either:
        // `suggest` still waits for a human (the round-3 rule, unchanged).
        expect(r.chosenIngredientId, isNull);
        expect(r.isResolved, isFalse);
      },
    );

    test('linking clears any ingredient match — one identity, D1s XOR', () {
      final linked = initialResolution(0, aioliPayload().flatLines[0])
          .resolveToIngredient('v-aioli', 'Aioli', correction: true)
          .linkToRecipe('r-aioli', 'Romesco Aioli');
      expect(linked.isComponent, isTrue);
      expect(linked.linkedRecipeTitle, 'Romesco Aioli');
      expect(linked.chosenIngredientId, isNull);
      expect(linked.chosenName, isNull);
      // A link is not an ingredient correction: there is no alias to write.
      expect(linked.isCorrection, isFalse);
      // The printed amount survives — "¼ cup" is what the page said.
      expect(linked.quantity, 0.25);
      expect(linked.unit, 'cup');
    });

    test(
      'a link is reversible before Save — unlink, or match an ingredient',
      () {
        final linked = initialResolution(
          0,
          aioliPayload().flatLines[0],
        ).linkToRecipe('r-aioli', 'Romesco Aioli');

        final unlinked = linked.unlink();
        expect(unlinked.isComponent, isFalse);
        expect(unlinked.linkedRecipeTitle, isNull);
        expect(unlinked.quantity, 0.25); // the amount it had is not disturbed

        // Re-matching an ingredient is the other way back (D7's "re-pick").
        final rematched = linked.resolveToIngredient('v-aioli', 'Aioli');
        expect(rematched.isComponent, isFalse);
        expect(rematched.chosenIngredientId, 'v-aioli');
        // As is creating a stub.
        expect(linked.resolveToNewStub('Aioli').isComponent, isFalse);
      },
    );

    group('the save-gate arithmetic', () {
      test('a linked line is valid the moment its amount is set — no '
          'ingredient match, no allowed-units gate', () {
        final withAmount = initialResolution(
          0,
          aioliPayload().flatLines[0],
        ).linkToRecipe('r-aioli', 'Romesco Aioli');
        expect(withAmount.isResolved, isTrue);
        expect(lineIssues(withAmount), isEmpty);
        expect(allResolved([withAmount]), isTrue);

        // Even with an ingredient handed in, the admission check does not run:
        // admission is an ingredient concept, and this line has none. The unit
        // meets the target's yield family later, at derive time (D2).
        expect(
          lineIssues(
            withAmount.setAmount(quantity: 0.25, unit: 'cup'),
            ingredient: const Ingredient(
              id: 'v-garlic',
              canonicalName: 'Garlic',
              defaultUnit: g,
              status: IngredientStatus.complete,
            ),
          ),
          isEmpty,
        );
      });

      test('a linked line with NO amount is the one thing that blocks it', () {
        final noAmount = initialResolution(
          0,
          aioliPayload().flatLines[0],
        ).linkToRecipe('r-aioli', 'Romesco Aioli').setAmount();
        expect(noAmount.quantity, isNull);
        expect(noAmount.isResolved, isFalse);
        expect(lineIssues(noAmount), [LineIssue.amountMissing]);
        expect(allResolved([noAmount]), isFalse);
      });

      test('a dropped linked line is excluded, like any other', () {
        final dropped = initialResolution(
          0,
          aioliPayload().flatLines[0],
        ).linkToRecipe('r-aioli', 'Romesco Aioli').setAmount().drop();
        expect(lineIssues(dropped), isEmpty);
        expect(allResolved([dropped]), isTrue);
      });
    });

    group('buildCommit — the same rule, re-asserted at the seam', () {
      test('a linked line commits as a component: sub_recipe_id set, no '
          'ingredient, no stub', () {
        final payload = aioliPayload();
        final commit = buildCommit(
          payload,
          [
            initialResolution(
              0,
              payload.flatLines[0],
            ).linkToRecipe('r-aioli', 'Romesco Aioli'),
          ],
          header: _header(payload),
          issuesByLine: const {0: <LineIssue>[]},
        );
        final line = commit.groups.single.lines.single;
        expect(line.subRecipeId, 'r-aioli');
        expect(line.ingredientId, isNull);
        expect(line.stubKey, isNull);
        expect(line.quantity, 0.25);
        expect(line.unit, 'cup');
        expect(commit.stubs, isEmpty);
        expect(commit.corrections, isEmpty);
      });

      test('an amount-less linked line is refused at the seam, not hoped '
          'about in the view', () {
        final payload = aioliPayload();
        final resolutions = [
          initialResolution(
            0,
            payload.flatLines[0],
          ).linkToRecipe('r-aioli', 'Romesco Aioli').setAmount(),
        ];
        expect(
          () => buildCommit(
            payload,
            resolutions,
            header: _header(payload),
            // Even with a LYING issue map, the structural gate holds.
            issuesByLine: const {0: <LineIssue>[]},
          ),
          throwsStateError,
        );
      });

      test('a resolution carrying both identities is refused', () {
        final payload = aioliPayload();
        // Constructed by hand: no mutator can produce this, and that is
        // exactly why the seam asserts it rather than trusting the caller.
        const both = LineResolution(
          lineIndex: 0,
          band: MatchBand.suggest,
          ingredientText: 'Romesco Aioli (page 38)',
          isRange: false,
          unit: 'cup',
          quantity: 0.25,
          chosenIngredientId: 'v-aioli',
          chosenName: 'Aioli',
          linkedRecipeId: 'r-aioli',
          linkedRecipeTitle: 'Romesco Aioli',
        );
        expect(
          () => buildCommit(
            payload,
            [both],
            header: _header(payload),
            issuesByLine: const {0: <LineIssue>[]},
          ),
          throwsStateError,
        );
      });

      test('the review yield rides the commit — both halves or neither', () {
        final payload = aioliPayload();
        final resolutions = [
          initialResolution(
            0,
            payload.flatLines[0],
          ).linkToRecipe('r-aioli', 'Romesco Aioli'),
        ];
        final stated = buildCommit(
          payload,
          resolutions,
          header: _header(payload, yieldQty: 8, yieldUnit: pieces),
          issuesByLine: null,
        );
        expect(stated.yieldQty, 8);
        expect(stated.yieldUnit, pieces);

        // Half a yield is half a fact — and the migration's CHECK says so too.
        final halfStated = buildCommit(
          payload,
          resolutions,
          header: _header(payload, yieldQty: 8),
          issuesByLine: null,
        );
        expect(halfStated.yieldQty, isNull);
        expect(halfStated.yieldUnit, isNull);

        // And nothing stated is a perfectly good save: the yield never gates.
        final none = buildCommit(
          payload,
          resolutions,
          header: _header(payload),
          issuesByLine: null,
        );
        expect(none.yieldQty, isNull);
      });
    });

    group('offered and declined — the gold specimens commit unchanged', () {
      /// The blessed sausage-sliders extraction, with the D6 offers the server
      /// would now attach to its six sub-recipe references.
      ReconciliationPayload slidersWithOffers() {
        final gold = goldPayload('sausage-sliders');
        var n = 0;
        return gold.copyWith(
          groups: [
            for (final group in gold.groups)
              group.copyWith(
                lines: [
                  for (final line in group.lines)
                    if (line.raw.ingredientText.contains('(page'))
                      line.copyWith(
                        recipeCandidates: [
                          RecipeCandidate(
                            recipeId: 'r-${n++}',
                            title: line.raw.ingredientText,
                            score: 1,
                          ),
                        ],
                      )
                    else
                      line,
                ],
              ),
          ],
        );
      }

      List<LineResolution> resolveEveryLine(ReconciliationPayload payload) => [
        for (var i = 0; i < payload.flatLines.length; i++)
          initialResolution(
            i,
            payload.flatLines[i],
          ).resolveToNewStub(payload.flatLines[i].raw.ingredientText),
      ];

      test('nobody taps ⇒ the commit is IDENTICAL to the offer-free one', () {
        final withOffers = slidersWithOffers();
        final without = goldPayload('sausage-sliders');
        // The specimen really does carry the offers we are ignoring.
        expect(
          withOffers.flatLines.where((l) => l.recipeCandidates.isNotEmpty),
          hasLength(6),
        );

        final offered = buildCommit(
          withOffers,
          resolveEveryLine(withOffers),
          header: _header(withOffers, servingsBase: 8),
          issuesByLine: null,
        );
        final plain = buildCommit(
          without,
          resolveEveryLine(without),
          header: _header(without, servingsBase: 8),
          issuesByLine: null,
        );
        // Freezed equality is deep: groups, lines, stubs, steps, corrections.
        expect(offered, plain);
        expect(
          offered.groups
              .expand((g) => g.lines)
              .every((l) => l.subRecipeId == null),
          isTrue,
          reason: 'an offer nobody took writes no component line',
        );
      });

      test('tapping ONE offer changes that line and nothing else', () {
        final payload = slidersWithOffers();
        final aioliIndex = payload.flatLines.indexWhere(
          (l) => l.raw.ingredientText.toLowerCase().contains('romesco aioli'),
        );
        expect(aioliIndex, isNot(-1));

        final resolutions = [
          for (final r in resolveEveryLine(payload))
            if (r.lineIndex == aioliIndex)
              r.linkToRecipe('r-aioli', 'Romesco Aioli')
            else
              r,
        ];
        final commit = buildCommit(
          payload,
          resolutions,
          header: _header(payload, servingsBase: 8),
          issuesByLine: null,
        );
        final lines = commit.groups.expand((g) => g.lines).toList();
        final linked = lines.firstWhere((l) => l.lineIndex == aioliIndex);
        expect(linked.subRecipeId, 'r-aioli');
        expect(linked.ingredientId, isNull);
        expect(linked.stubKey, isNull);
        // Every other line is untouched, and the linked line's stub is gone
        // from the vocabulary write (nothing mints an ingredient for it).
        expect(lines.where((l) => l.subRecipeId != null), hasLength(1));
        expect(
          commit.stubs.length,
          resolveEveryLine(
                payload,
              ).map((r) => r.createStubName!.toLowerCase()).toSet().length -
              1,
        );
      });
    });
  });
}
