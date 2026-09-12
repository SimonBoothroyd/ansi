import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

const _garlic = Ingredient(
  id: 'i-garlic',
  canonicalName: 'Garlic',
  defaultUnit: g,
  status: IngredientStatus.complete,
);

const _clove = Measure(id: 'm-clove', label: 'clove', amount: 3);

/// The board's frame-(a) row, post-curation (plan 0022): a count-default
/// produce ingredient whose ONE measure names the thing, so `piece` is not in
/// its explicit admission list.
const _avocado = Ingredient(
  id: 'i-avocado',
  canonicalName: 'Avocado',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.634,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
);

const _avocadoMeasure = Measure(id: 'm-avo', label: 'avocado', amount: 201);

/// The same shape with THREE sizes — the pick-one frame. Which one "1 potato"
/// meant is exactly what nothing here is allowed to guess.
const _potato = Ingredient(
  id: 'i-potato',
  canonicalName: 'Gold Potato',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.59,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
);

const _potatoSizes = [
  Measure(id: 'm-p-med', label: 'potato, medium', amount: 213),
  Measure(id: 'm-p-lrg', label: 'potato, large', amount: 369),
  Measure(id: 'm-p-sml', label: 'potato, small', amount: 170),
];

/// The owner's kale: `produce`, so J3 gives it `handful` and withholds
/// `pinch`/`dash`.
const _kale = Ingredient(
  id: 'i-kale',
  canonicalName: 'Kale',
  defaultUnit: cup,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.2,
);

LineResolution _res({
  String? chosenIngredientId,
  bool isRange = false,
  double? quantity,
  String? unit,
}) => LineResolution(
  lineIndex: 0,
  band: MatchBand.suggest,
  ingredientText: 'garlic',
  isRange: isRange,
  unit: unit,
  chosenIngredientId: chosenIngredientId,
  quantity: quantity,
);

void main() {
  group('acceptableUnitTokens (allowed set + measures + imprecise)', () {
    test('a mass ingredient admits its catalog units, its measures, and the '
        'imprecise words it earns — nothing else', () {
      final tokens = acceptableUnitTokens(_garlic, const [_clove]);
      expect(tokens, containsAll(<String>['g', 'kg'])); // mass default set
      expect(tokens, contains('clove')); // its measure, by label
      // `to taste` rides on every import line ("plus more, to serve").
      expect(tokens, contains('to_taste'));
      // A volume unit is NOT admitted (no density) — enforcement, not anything.
      expect(tokens, isNot(contains('ml')));
    });

    test('pinch and dash are NOT unioned onto every match — the review offered '
        '"a dash of kale" because they were', () {
      // A line that printed a real volume unit: nothing pulls an imprecise
      // word in through the J3b printed leg.
      final tokens = acceptableUnitTokens(_kale, const [], parsedUnit: 'cup');
      expect(tokens, isNot(contains('pinch')));
      expect(tokens, isNot(contains('dash')));
      // Real cooking language survives: a handful of greens, and to taste.
      expect(tokens, containsAll(<String>['handful', 'to_taste']));
    });

    test('a '
        "line's OWN printed imprecise word is admitted whatever the category — "
        'never-invent cuts both ways', () {
      // THE SCENARIO-4 SHAPE. A row created at review is a plain `g` stub
      // with NO category until the form gives it one, so it earns no
      // imprecise word at all; the source printed "a pinch of chilli flakes".
      // Under the bare J3 gate that line flagged `unitNotAllowed` and locked
      // the Save gate on a unit nobody could ever have picked, because it was
      // never offered.
      const stub = Ingredient(
        id: 'ing-chilli',
        canonicalName: 'Chilli flakes',
        defaultUnit: g,
        status: IngredientStatus.stub,
      );
      expect(
        acceptableUnitTokens(stub, const [], parsedUnit: 'pinch'),
        contains('pinch'),
      );
      expect(
        lineIssues(
          _res(chosenIngredientId: 'ing-chilli', unit: 'pinch'),
          ingredient: stub,
        ),
        isEmpty,
      );
      // And it is OFFERED, so the amount sheet can render what the line says.
      expect(
        acceptableUnitChips(
          stub,
          const [],
          parsedUnit: 'pinch',
        ).map((c) => c.token),
        contains('pinch'),
      );
    });

    test(
      'the admission is exactly the printed word, not the rest of the tail',
      () {
        // "A pinch of kale" would be honoured if a source really printed it —
        // but it still buys kale no `dash`, which is the offer J3 closed.
        final tokens = acceptableUnitTokens(
          _kale,
          const [],
          parsedUnit: 'pinch',
        );
        expect(tokens, contains('pinch'));
        expect(tokens, isNot(contains('dash')));
      },
    );

    test('the printed-word admission does NOT extend to mass/volume: a printed '
        'unit the converter cannot resolve still flags', () {
      // The pass is for imprecise WORDS, which cost the converter nothing.
      // "1 cup" of a density-less row is a different animal entirely.
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-garlic', quantity: 1, unit: 'ml'),
          ingredient: _garlic,
        ),
        [LineIssue.unitNotAllowed],
      );
    });

    test('so no imprecise unit can flag on the import surface at all — the '
        'only reachable states are printed (admitted as the line’s own word) '
        'and tapped (offered, therefore admitted)', () {
      // Worth pinning as a property: the gate lives in what is OFFERED. A
      // word the editor never shows is a word the user cannot pick, so a
      // flag on one could only ever be unclearable.
      for (final word in ['pinch', 'dash', 'handful', 'to_taste']) {
        expect(
          lineIssues(
            _res(chosenIngredientId: 'i-kale', quantity: 1, unit: word),
            ingredient: _kale,
          ),
          isEmpty,
          reason: word,
        );
      }
      // The vocab surface is where the gate still bites: the manager offers
      // greens no pinch, whatever an import line once said.
      expect(allowedUnitsFor(_kale), isNot(contains(pinch)));
    });

    test('a seasoning still earns the whole tail', () {
      const salt = Ingredient(
        id: 'i-salt',
        canonicalName: 'Salt',
        defaultUnit: tsp,
        category: 'spices & seasoning',
        status: IngredientStatus.complete,
      );
      expect(
        acceptableUnitTokens(salt, const []),
        containsAll(<String>['pinch', 'dash', 'handful', 'to_taste']),
      );
    });
  });

  group('acceptableUnitChips (inline "did you mean" for the unit)', () {
    test('offers allowed units + measures + imprecise as chips', () {
      final chips = acceptableUnitChips(_garlic, const [_clove]);
      final tokens = chips.map((c) => c.token).toSet();
      expect(tokens, containsAll(<String>['g', 'kg', 'clove']));
      expect(tokens, contains('to_taste'));
      // Every chip is a token the amount sheet could produce — so tapping one
      // is always valid (it never re-seeds an invalid unit).
      final acceptable = acceptableUnitTokens(_garlic, const [_clove]);
      expect(tokens.every(acceptable.contains), isTrue);
    });

    test(
      'a serving measure is offered in the chip voice, stored by its label',
      () {
        const serving = Measure(
          id: 'm-serving',
          label: 'serving · 3 g',
          amount: 3,
        );
        final chips = acceptableUnitChips(_garlic, const [_clove, serving]);
        final chip = chips.singleWhere((c) => c.token == 'serving · 3 g');
        expect(chip.label, 'serving (3 g)');
      },
    );
  });

  group('lineIssues', () {
    test('unmatched line → unmatched', () {
      expect(lineIssues(_res()), [LineIssue.unmatched]);
    });

    test('matched range with no picked number → rangeUnpicked', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', isRange: true),
        ingredient: _garlic,
      );
      expect(issues, contains(LineIssue.rangeUnpicked));
    });

    test('a unit outside the ingredient allowed set → unitNotAllowed', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 1, unit: 'ml'),
        ingredient: _garlic,
      );
      expect(issues, [LineIssue.unitNotAllowed]);
    });

    test('deleting '
        "an ingredient's density degrades a line already saying a cross-family "
        'unit — flagged, never rewritten', () {
      // The mango shape before and after the density is deleted. The line is
      // byte-identical in both calls: nothing rewrites what the user wrote,
      // and the only thing that changes is whether the unit is still
      // supported (plan 0020 D4b — `clearDensity` strips the admission, this
      // is what the recipe side then sees).
      const line = 'cup';
      const withDensity = Ingredient(
        id: 'i-mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        densityGPerMl: 0.66,
        allowedUnits: [pieces, g, tsp, tbsp, cup, ml],
      );
      const stripped = Ingredient(
        id: 'i-mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        allowedUnits: [pieces, g],
      );

      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-mango', quantity: 1, unit: line),
          ingredient: withDensity,
        ),
        isEmpty,
      );
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-mango', quantity: 1, unit: line),
          ingredient: stripped,
        ),
        [LineIssue.unitNotAllowed],
      );
    });

    test('a line saying a unit only the DEFAULT unit used to admit degrades '
        'the same way — a stale allowed list does not make it sayable', () {
      // The renamed-rice shape: cup default, per-100 g macros, no density,
      // and an `allowed_units` list materialized under the looser pre-D4c
      // rule (the server still writes those, and this is what stops one from
      // smuggling an unconvertible unit onto a line).
      const rice = Ingredient(
        id: 'i-rice',
        canonicalName: 'Black rice',
        defaultUnit: cup,
        status: IngredientStatus.stub,
        allowedUnits: [cup, tbsp, ml, l, g, kg],
      );
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-rice', quantity: 1, unit: 'cup'),
          ingredient: rice,
        ),
        [LineIssue.unitNotAllowed],
      );
      // Flagged, never rewritten — and honest again the moment a density
      // bridges the two families.
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-rice', quantity: 1, unit: 'cup'),
          ingredient: rice.copyWith(densityGPerMl: 0.75),
        ),
        isEmpty,
      );
    });

    test('a measure-label unit is allowed when the ingredient has it', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 2, unit: 'clove'),
        ingredient: _garlic,
        measures: const [_clove],
      );
      expect(issues, isEmpty);
    });

    test('an imprecise unit is always allowed (to serve)', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'ing-aleppo', unit: 'to_taste'),
        // A row just created at review is a plain g-shaped stub.
        ingredient: const Ingredient(
          id: 'ing-aleppo',
          canonicalName: 'Aleppo chilli',
          defaultUnit: g,
          status: IngredientStatus.stub,
        ),
      );
      expect(issues, isEmpty);
    });

    test('a matched line with an allowed unit is clean', () {
      final issues = lineIssues(
        _res(chosenIngredientId: 'i-garlic', quantity: 400, unit: 'g'),
        ingredient: _garlic,
      );
      expect(issues, isEmpty);
    });
  });

  group('rankedUnitChips (5 visible, the rest behind the fold)', () {
    // The Tomato-shaped flood: a dozen-plus admissible chips.
    final chips = acceptableUnitChips(
      const Ingredient(
        id: 'i-tom',
        canonicalName: 'Tomato',
        defaultUnit: g,
        status: IngredientStatus.complete,
        densityGPerMl: 1,
      ),
      const [
        Measure(id: 'm-small', label: 'small', amount: 90),
        Measure(id: 'm-large', label: 'large', amount: 180),
      ],
    );

    test('the parsed unit leads, then its family', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'kg');
      expect(ranked.first.token, 'kg');
      // The rest of the mass family comes next, before any measure.
      expect(ranked[1].token, 'g');
    });

    test('measures beat the generic g, and keep their given order', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'ml');
      final tokens = ranked.map((c) => c.token).toList();
      expect(tokens.indexOf('small'), lessThan(tokens.indexOf('large')));
      expect(tokens.indexOf('large'), lessThan(tokens.indexOf('g')));
    });

    test('the imprecise words fold — they are last', () {
      final visible = rankedUnitChips(
        chips,
        parsedUnit: 'kg',
      ).take(kVisibleUnitChips).map((c) => c.token).toSet();
      expect(visible, isNot(contains('to_taste')));
      expect(visible, isNot(contains('pinch')));
      expect(visible, hasLength(kVisibleUnitChips));
    });

    test('an imprecise parsed amount fronts the imprecise family instead', () {
      // On a row that actually earns the word (J3): a seasoning line reading
      // "a good pinch" must not have to expand to say pinch.
      const salt = Ingredient(
        id: 'i-salt',
        canonicalName: 'Salt',
        defaultUnit: tsp,
        category: 'spices & seasoning',
        status: IngredientStatus.complete,
      );
      final visible = rankedUnitChips(
        acceptableUnitChips(salt, const []),
        parsedUnit: 'pinch',
      ).take(kVisibleUnitChips).map((c) => c.token).toList();
      expect(visible.first, 'pinch');
      expect(visible, contains('to_taste'));
    });

    test('a pinch line on a food that earns no pinch is still offered its own '
        'printed word, and that word leads', () {
      // Built the way the review screen builds it — WITH the line's unit.
      // This supersedes the J3-only reading, where an ungated row dropped the
      // printed word and fronted `to taste` instead: that left the line
      // flagged for a unit the editor would not show, which is unclearable.
      final ranked = rankedUnitChips(
        acceptableUnitChips(_kale, const [], parsedUnit: 'pinch'),
        parsedUnit: 'pinch',
      ).map((c) => c.token).toList();
      expect(ranked.first, 'pinch');
      // Its neighbours stay withheld — one word, not the tail.
      expect(ranked, isNot(contains('dash')));
    });

    test('the fold hides nothing — every chip survives the ranking', () {
      final ranked = rankedUnitChips(chips, parsedUnit: 'clove');
      expect(ranked.toSet(), chips.toSet());
      expect(ranked, hasLength(chips.length));
    });

    test('the owner’s garlic, exactly as the cloud carries it: the printed '
        '"clove" leads, measures beat generic, imprecise last', () {
      // Piece default, an explicit [piece, g] list, a `clove` measure, no
      // density — and a line that printed "1 clove". The Pixel screenshot read
      // "g piece pinch dash handful (+1 more)", which is precisely this
      // ranking run over an EMPTY measure list: the ordering never degraded,
      // the measures never arrived (see import_validation_test.dart).
      const garlic = Ingredient(
        id: 'i-garlic',
        canonicalName: 'Garlic',
        defaultUnit: pieces,
        category: 'produce',
        status: IngredientStatus.complete,
        allowedUnits: [pieces, g],
      );
      final garlicChips = acceptableUnitChips(garlic, const [_clove]);
      final ranked = rankedUnitChips(
        garlicChips,
        parsedUnit: 'clove',
      ).map((c) => c.token).toList();

      expect(ranked.first, 'clove');
      expect(ranked.indexOf('clove'), lessThan(ranked.indexOf('g')));
      expect(ranked.indexOf('g'), lessThan(ranked.indexOf('handful')));
      expect(ranked.last, 'to_taste');
      // The line's own unit is never behind the fold.
      expect(ranked.take(kVisibleUnitChips), contains('clove'));
      // And the fold still hides nothing.
      expect(ranked.toSet(), garlicChips.map((c) => c.token).toSet());
    });
  });

  group('rankedUnitChips with NO parsed unit defers to the ADR order', () {
    // The three shapes the owner read off the vocab-audit page. Densities are
    // present because R1 requires one for a volume default; the VALUE is
    // immaterial to chip order, only its presence (it unlocks the cross
    // family) is.
    const blackPepper = Ingredient(
      id: 'i-pepper',
      canonicalName: 'Black Pepper',
      defaultUnit: tsp,
      category: 'spices & seasoning',
      status: IngredientStatus.complete,
      densityGPerMl: 0.46,
    );
    const flour = Ingredient(
      id: 'i-flour',
      canonicalName: 'All-Purpose Flour',
      defaultUnit: cup,
      category: 'baking',
      status: IngredientStatus.complete,
      densityGPerMl: 0.53,
    );

    /// The ORDER SOURCE, which is the whole of this rule: a line that printed
    /// no unit has no evidence to rank on, so the chips come out exactly as
    /// `allowedUnitChoicesFor` built them — ADR-0008 kitchen order. Asserting
    /// the source (not a transcribed list) is what keeps this test true when
    /// the ADR order itself changes.
    void expectsOfferOrderPreserved(Ingredient ingredient) {
      final chips = acceptableUnitChips(ingredient, const []);
      expect(rankedUnitChips(chips, parsedUnit: null), chips);
    }

    test('the offer order is preserved, unchanged, for every shape', () {
      expectsOfferOrderPreserved(blackPepper);
      expectsOfferOrderPreserved(flour);
      expectsOfferOrderPreserved(_kale);
    });

    test('a spice leads with its own tsp, not the generic g', () {
      final ranked = rankedUnitChips(
        acceptableUnitChips(blackPepper, const []),
        parsedUnit: null,
      ).map((c) => c.token).toList();
      expect(ranked.first, 'tsp');
      expect(ranked.indexOf('tsp'), lessThan(ranked.indexOf('g')));
    });

    test(
      'flour leads with its own cup — american recipes, not metric jugs',
      () {
        final ranked = rankedUnitChips(
          acceptableUnitChips(flour, const []),
          parsedUnit: null,
        ).map((c) => c.token).toList();
        expect(ranked.first, 'cup');
        // The spoon beats the jug, per the ADR kitchen order within the family.
        expect(ranked.indexOf('tbsp'), lessThan(ranked.indexOf('ml')));
        // `g` is the DEMOTED cross-family leg, so it sits behind the whole
        // volume family — the ADR's order, which this rule defers to.
        expect(ranked.indexOf('ml'), lessThan(ranked.indexOf('g')));
      },
    );

    test('kale leads with its own cup, not ml·g (the audit-page report)', () {
      final ranked = rankedUnitChips(
        acceptableUnitChips(_kale, const []),
        parsedUnit: null,
      ).map((c) => c.token).toList();
      expect(ranked.first, 'cup');
      expect(ranked.indexOf('cup'), lessThan(ranked.indexOf('ml')));
      expect(ranked.indexOf('cup'), lessThan(ranked.indexOf('g')));
      // Its imprecise words still fold to the back — the one its category
      // earns (J3) plus the always-offered `to taste`.
      expect(ranked.sublist(ranked.length - 2), ['handful', 'to_taste']);
    });

    test('the imprecise tail sinks even when the offer front-loads it', () {
      // Built by hand, NOT by the offer: the sink is this rule's own promise,
      // not something inherited from a caller that already ordered well.
      const chips = [
        UnitSuggestion(token: 'pinch', label: 'pinch'),
        UnitSuggestion(token: 'tsp', label: 'tsp'),
        UnitSuggestion(token: 'to_taste', label: 'to taste'),
        UnitSuggestion(token: 'g', label: 'g'),
      ];
      final ranked = rankedUnitChips(
        chips,
        parsedUnit: null,
      ).map((c) => c.token).toList();
      expect(ranked, ['tsp', 'g', 'pinch', 'to_taste']);
    });

    test('an empty parsed unit is the same as none — the review screen passes '
        "the line's unit straight through", () {
      final chips = acceptableUnitChips(flour, const []);
      expect(rankedUnitChips(chips, parsedUnit: ''), chips);
    });

    test('a measure keeps its offer position — in front, ahead of the '
        'catalog units and the imprecise tail', () {
      // The ranking used to boost a measure to rank 2 by a rule of its own;
      // deferring drops the boost, and the offer's own placement — measures
      // first, because a measure names THIS row — is what stands.
      final chips = acceptableUnitChips(_garlic, const [_clove]);
      final ranked = rankedUnitChips(chips, parsedUnit: null);
      expect(ranked, chips);
      final tokens = ranked.map((c) => c.token).toList();
      expect(tokens.indexOf('clove'), lessThan(tokens.indexOf('g')));
      expect(tokens.indexOf('clove'), lessThan(tokens.indexOf('to_taste')));
    });
  });

  group('a count on a piece-default row (ADR-0015)', () {
    // No explicit admission list on either row, so what they admit is what the
    // rule derives — and the piece weight is the whole of the difference.
    const unweighed = Ingredient(
      id: 'i-tin',
      canonicalName: 'Tinned Butter Bean',
      defaultUnit: pieces,
      status: IngredientStatus.complete,
    );
    const weighed = Ingredient(
      id: 'i-tin',
      canonicalName: 'Tinned Butter Bean',
      defaultUnit: pieces,
      status: IngredientStatus.complete,
      pieceBasisAmount: 400,
      pieceSource: 'manual',
    );

    test('the review offers a weighed piece in the words the sheet uses — '
        '"piece (400 g)", never a bare count', () {
      final chips = acceptableUnitChips(weighed, const []);
      final piece = chips.singleWhere((c) => c.token == 'piece');
      expect(piece.label, 'piece (400 g)');
      // The TOKEN is still the catalog id: what a tap writes onto the line
      // is the unit, not the sentence.
      expect(piece.token, 'piece');
    });

    test('a printed `piece` is unitNotAllowed until the row says what one '
        'weighs, and clean the moment it does', () {
      final line = _res(
        chosenIngredientId: 'i-tin',
        quantity: 1,
        unit: 'piece',
      );
      expect(lineIssues(line, ingredient: unweighed), [
        LineIssue.unitNotAllowed,
      ]);
      expect(lineIssues(line, ingredient: weighed), isEmpty);
    });

    test('a number with NO unit word is that same count and is judged the '
        'same way — it is what the commit path stores as `piece`', () {
      final line = _res(chosenIngredientId: 'i-tin', quantity: 2);
      expect(lineIssues(line, ingredient: unweighed), [
        LineIssue.unitNotAllowed,
      ]);
      expect(lineIssues(line, ingredient: weighed), isEmpty);
      // …and the empty string the review screen passes is the same nothing.
      expect(
        lineIssues(
          _res(chosenIngredientId: 'i-tin', quantity: 2, unit: ''),
          ingredient: unweighed,
        ),
        [LineIssue.unitNotAllowed],
      );
    });

    test('a numberless line is no count at all — "to taste" onions flag for '
        'nothing', () {
      expect(
        lineIssues(_res(chosenIngredientId: 'i-tin'), ingredient: weighed),
        isEmpty,
      );
      expect(
        lineIssues(_res(chosenIngredientId: 'i-tin'), ingredient: unweighed),
        isEmpty,
      );
    });

    test('a counted line the review landed on the whole measure is an '
        'ordinary measure-label line: clean, and not the piece-weight door '
        '(ADR-0016)', () {
      const whole = Measure(id: 'm-tin', label: 'tin', amount: 400);
      final landed = landOnWholeMeasure(
        _res(chosenIngredientId: 'i-tin', quantity: 2, unit: 'piece'),
        ingredient: weighed,
        measures: const [whole],
      );
      expect(landed.unit, 'tin');
      expect(
        lineIssues(landed, ingredient: weighed, measures: const [whole]),
        isEmpty,
      );
      expect(countNeedsPieceWeight(landed, weighed), isFalse);
      // The unweighed row is exactly as gated as before.
      final gated = landOnWholeMeasure(
        _res(chosenIngredientId: 'i-tin', quantity: 2, unit: 'piece'),
        ingredient: unweighed,
        measures: const [whole],
      );
      expect(
        lineIssues(gated, ingredient: unweighed, measures: const [whole]),
        [LineIssue.unitNotAllowed],
      );
      expect(countNeedsPieceWeight(gated, unweighed), isTrue);
    });

    test('a bare number on a MASS-default row is unitNotAllowed too — `piece` '
        'is never admitted there, and no weight would admit it', () {
      final line = _res(chosenIngredientId: _garlic.id, quantity: 2);
      expect(lineIssues(line, ingredient: _garlic, measures: const [_clove]), [
        LineIssue.unitNotAllowed,
      ]);
      // The fix is on this card: the units the row CAN say, as chips.
      final chips = acceptableUnitChips(_garlic, const [_clove]);
      expect(chips.map((c) => c.token), containsAll(<String>['g', 'clove']));
      expect(chips.map((c) => c.token), isNot(contains('piece')));
      // …and it is not the piece-weight gap, so the card offers no door.
      expect(countNeedsPieceWeight(line, _garlic), isFalse);
    });
  });

  group('resolutionIsCount / countNeedsPieceWeight', () {
    test('a count is a printed `piece` or a number with no unit word — '
        'nothing else', () {
      expect(resolutionIsCount(_res(quantity: 1, unit: 'piece')), isTrue);
      expect(resolutionIsCount(_res(quantity: 2)), isTrue);
      expect(resolutionIsCount(_res(quantity: 2, unit: '')), isTrue);
      // A measure label names a thing, not a bare count.
      expect(resolutionIsCount(_res(quantity: 1, unit: 'clove')), isFalse);
      expect(resolutionIsCount(_res(quantity: 200, unit: 'g')), isFalse);
      expect(resolutionIsCount(_res(quantity: 1, unit: 'pinch')), isFalse);
      // No unit AND no number: nothing was counted.
      expect(resolutionIsCount(_res()), isFalse);
    });

    test('the gap is the ROW’s, so it needs both a count and an unweighed '
        'piece-default row', () {
      const unweighed = Ingredient(
        id: 'i-lime',
        canonicalName: 'Lime',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
      );
      const weighed = Ingredient(
        id: 'i-lime',
        canonicalName: 'Lime',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        pieceBasisAmount: 67,
        pieceSource: 'manual',
      );
      final count = _res(chosenIngredientId: 'i-lime', quantity: 2);
      expect(countNeedsPieceWeight(count, unweighed), isTrue);
      expect(countNeedsPieceWeight(count, weighed), isFalse);
      // A mass-default row has no piece default to strand.
      expect(countNeedsPieceWeight(count, _garlic), isFalse);
      // An unmatched line has no row to ask.
      expect(countNeedsPieceWeight(count, null), isFalse);
      // And a line that is not a count never asks, whatever the row.
      expect(
        countNeedsPieceWeight(
          _res(chosenIngredientId: 'i-lime', quantity: 200, unit: 'g'),
          unweighed,
        ),
        isFalse,
      );
    });
  });

  group('preselectedMeasure (one confirm tap, not a scroll-and-choose)', () {
    test('an inadmissible unit on a row with ONE measure pre-picks it', () {
      final picked = preselectedMeasure(
        _garlic,
        const [_clove],
        unit: 'ml', // garlic has no density: not admissible
      );
      expect(picked, _clove);
    });

    test('an admissible unit pre-picks nothing', () {
      expect(preselectedMeasure(_garlic, const [_clove], unit: 'g'), isNull);
      expect(
        preselectedMeasure(_garlic, const [_clove], unit: 'clove'),
        isNull,
      );
    });

    test('no unit, or no measure to offer, pre-picks nothing', () {
      expect(preselectedMeasure(_garlic, const [_clove], unit: null), isNull);
      expect(preselectedMeasure(_garlic, const [], unit: 'ml'), isNull);
    });

    test('a volume-named measure is skipped — density owns volume', () {
      expect(
        preselectedMeasure(_garlic, const [
          Measure(id: 'm-cup', label: 'cup', amount: 120),
        ], unit: 'ml'),
        isNull,
      );
    });

    test('THREE measures pre-select nothing — which size a `piece` meant is '
        'not the machine’s to decide', () {
      expect(preselectedMeasure(_potato, _potatoSizes, unit: 'piece'), isNull);
      // …while the same shape with ONE measure still fires: there is nothing
      // else the line could have meant.
      expect(
        preselectedMeasure(_avocado, const [_avocadoMeasure], unit: 'piece'),
        _avocadoMeasure,
      );
    });
  });

  group('ADR-0010: a `piece` line on a measured row', () {
    LineResolution pieceLine(String ingredientId) => LineResolution(
      lineIndex: 0,
      band: MatchBand.auto,
      ingredientText: 'ripe avocado',
      isRange: false,
      unit: 'piece',
      quantity: 1,
      chosenIngredientId: ingredientId,
    );

    test('is flagged unitNotAllowed — the state the review screen has always '
        'known how to handle', () {
      expect(
        lineIssues(
          pieceLine(_avocado.id),
          ingredient: _avocado,
          measures: const [_avocadoMeasure],
        ),
        [LineIssue.unitNotAllowed],
      );
      // …and the Save gate holds because of it.
      expect(
        allLinesValid({
          0: const [LineIssue.unitNotAllowed],
        }),
        isFalse,
      );
    });

    test('is offered the row’s measures and NOT `piece` — the chips are the '
        'offer, and the offer refuses the word', () {
      final chips = acceptableUnitChips(_avocado, const [
        _avocadoMeasure,
      ], parsedUnit: 'piece');
      expect(chips.map((c) => c.token), contains('avocado'));
      expect(chips.map((c) => c.token), isNot(contains('piece')));
    });

    test('ranks the measures in front: a refused `piece` takes no rank at all, '
        'and its family has nobody else to lift', () {
      final ranked = rankedUnitChips(
        acceptableUnitChips(_potato, _potatoSizes, parsedUnit: 'piece'),
        parsedUnit: 'piece',
      );
      final tokens = ranked.map((c) => c.token).toList();
      expect(tokens, isNot(contains('piece')));
      expect(tokens.take(3), _potatoSizes.map((m) => m.label));
      // All three sizes are in front of the fold, so the pick is one tap.
      expect(
        tokens.take(kVisibleUnitChips),
        containsAll(_potatoSizes.map((m) => m.label)),
      );
    });

    test('a measure-less WEIGHED count row still says `piece` happily — the '
        'fallback the whole rule exists to protect', () {
      const tin = Ingredient(
        id: 'i-tin',
        canonicalName: 'Tinned Butter Bean',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
        pieceBasisAmount: 400,
        pieceSource: 'manual',
      );
      expect(lineIssues(pieceLine(tin.id), ingredient: tin), isEmpty);
    });
  });

  group('allLinesValid (the Save gate)', () {
    test('true only when every line is clean', () {
      expect(allLinesValid({0: const [], 1: const []}), isTrue);
      expect(
        allLinesValid({
          0: const [],
          1: const [LineIssue.unmatched],
        }),
        isFalse,
      );
    });
  });

  group('crossReferenceFlag', () {
    test('a printed page reference is surfaced, in its own words', () {
      expect(crossReferenceFlag('Romesco Aioli (page 38)'), '(page 38)');
      expect(crossReferenceFlag('Garlic Butter (p. 17)'), '(p. 17)');
      expect(crossReferenceFlag('Pretzel Buns (see page 97)'), '(see page 97)');
    });

    test('an ordinary parenthetical is NOT a cross-reference', () {
      expect(crossReferenceFlag('tomatoes (400 g tin)'), isNull);
      expect(crossReferenceFlag('parsley (optional)'), isNull);
      expect(crossReferenceFlag('onion'), isNull);
    });
  });
}
