/// The shape every import-review widget suite pumps: a reconciliation payload
/// of one group, built from what the source printed and what the server
/// matched it to — plus the vocabulary rows those payloads point at.
///
/// Eight hand-written `_somethingPayload()` builders restated the same four
/// nested constructors to vary one field each, which put 500 lines of scaffold
/// in front of the first test in a file. Here the variation is the argument
/// list, so a suite's fixture is one line and the thing it varies is the only
/// thing you read. The builders keep the shape `line_resolution_test` already
/// uses.
library;

import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';

/// One extracted line, optionally matched to one candidate ingredient.
///
/// [ingredientId] is the one-candidate shorthand every suite wants; a suite
/// that needs two or none passes [candidates] instead.
ReconLine reconLine(
  String text, {
  MatchBand band = MatchBand.auto,
  double? qty,
  double? qtyLow,
  double? qtyHigh,
  String? unit,
  String rawAmount = '',
  String? ingredientId,
  String? canonicalName,
  double score = 0.97,
  List<MatchCandidate> candidates = const [],
  List<RecipeCandidate> recipeCandidates = const [],
}) => ReconLine(
  raw: RawLineItem(
    ingredientText: text,
    qty: qty,
    qtyLow: qtyLow,
    qtyHigh: qtyHigh,
    unit: unit,
    rawAmount: rawAmount,
  ),
  band: band,
  candidates: [
    ...candidates,
    if (ingredientId != null)
      MatchCandidate(
        ingredientId: ingredientId,
        canonicalName: canonicalName ?? ingredientId,
        score: score,
      ),
  ],
  recipeCandidates: recipeCandidates,
);

/// A payload of one group holding [lines] — grouping is
/// `reconciliation_payload_test`'s subject, and no screen suite varies it.
ReconciliationPayload reconPayload(
  List<ReconLine> lines, {
  String title = 'T',
  int? servingsBase = 2,
  String? yieldRaw,
  TimeRange? cookTimeSeconds,
  List<String> parseWarnings = const [],
  List<Step> steps = const [],
}) => ReconciliationPayload(
  title: title,
  servingsBase: servingsBase,
  yieldRaw: yieldRaw,
  cookTimeSeconds: cookTimeSeconds,
  parseWarnings: parseWarnings,
  groups: [ReconGroup(lines: lines)],
  steps: steps,
);

/// The plain complete row a review suite matches its one line to when which
/// row it is is not the subject.
///
/// Two of them, because the printed unit has to be one the row can carry: a
/// line that says "200 g" needs [onionByWeight] and a line that says "1 onion"
/// needs [onionByPiece], or the line arrives flagged and the suite's actual
/// subject never gets a clean Save.
const onionByWeight = Ingredient(
  id: 'ing-onion',
  canonicalName: 'Onion',
  defaultUnit: g,
  status: IngredientStatus.complete,
);
const onionByPiece = Ingredient(
  id: 'ing-onion',
  canonicalName: 'Onion',
  defaultUnit: pieces,
  status: IngredientStatus.complete,
);

const garlic = Ingredient(
  id: 'ing-garlic',
  canonicalName: 'Garlic',
  defaultUnit: g,
  status: IngredientStatus.complete,
);
const garlicClove = Measure(id: 'm-clove', label: 'clove', amount: 3);

/// A sized family with a curated default — "2 red peppers" means two mediums,
/// and the review says so on the card.
const pepper = Ingredient(
  id: 'ing-pepper',
  canonicalName: 'Red bell pepper',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.5,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
  defaultMeasureId: 'm-pep-med',
);
const pepperSizes = [
  Measure(id: 'm-pep-med', label: 'pepper, medium', amount: 119),
  Measure(id: 'm-pep-lrg', label: 'pepper, large', amount: 164),
  Measure(id: 'm-pep-sml', label: 'pepper, small', amount: 74),
];

/// One measure and no stated default. There is nothing else the line could
/// have meant, which is ADR-0010 consequence 4's own sentence.
const cucumber = Ingredient(
  id: 'ing-cucumber',
  canonicalName: 'Cucumber',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
);
const cucumberMeasure = Measure(id: 'm-cuc', label: 'cucumber', amount: 301);

/// A fragment set — three KINDS of countable thing and no dominant one, so
/// the row states no default and the line keeps its flag.
const broccoli = Ingredient(
  id: 'ing-broccoli',
  canonicalName: 'Broccoli',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
);
const broccoliParts = [
  Measure(id: 'm-b-whole', label: 'whole', amount: 608),
  Measure(id: 'm-b-spear', label: 'spear', amount: 31),
  Measure(id: 'm-b-crown', label: 'crown', amount: 150),
];

/// The scope rule's counter-case: a row whose default is its SOLE measure, on
/// a line that printed a word of its own.
const cilantro = Ingredient(
  id: 'ing-cilantro',
  canonicalName: 'Cilantro',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  allowedUnits: [g, handful],
  defaultMeasureId: 'm-cil-sprig',
);
const cilantroSprig = Measure(id: 'm-cil-sprig', label: 'sprig', amount: 2.22);

/// Three sizes, so nothing is pre-selected and the user picks.
const potato = Ingredient(
  id: 'ing-potato',
  canonicalName: 'Gold Potato',
  defaultUnit: pieces,
  category: 'produce',
  status: IngredientStatus.complete,
  densityGPerMl: 0.59,
  allowedUnits: [g, tsp, tbsp, cup, ml, handful],
);
const potatoSizes = [
  Measure(id: 'm-p-med', label: 'potato, medium', amount: 213),
  Measure(id: 'm-p-lrg', label: 'potato, large', amount: 369),
  Measure(id: 'm-p-sml', label: 'potato, small', amount: 170),
];
