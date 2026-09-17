/// Structural test: money never enters the macro record, and macros never
/// enter the cost record.
///
/// The two summations are deliberately the same walk over the same lines
/// (`line_basis.dart` is the conversion both call), and that closeness is
/// exactly what makes this worth holding mechanically. The cheapest "fix" for
/// any future gap — a `cents` field on [RecipeMacroSummary], a `kcal` beside a
/// price — would fuse two readings that must be able to refuse independently:
/// a recipe whose macros are whole can be unpriced, and a recipe every line of
/// which is priced can still be waiting on a stub. One record carrying both
/// would have to refuse for both, and the panel could no longer offer the
/// reading that works.
///
/// It is also what keeps ADR-0017 true in code: a cost is a unit price applied
/// to an amount, not a figure derived from anything nutritional.
///
/// **What it checks.** `recipe_macros.dart` names no money type and no money
/// word; `recipe_cost.dart` names no macro type and no macro word; neither
/// imports the other, in either direction. Comments and string literals are
/// blanked first ([blankNonCode]), so this doc comment — which says both
/// vocabularies out loud — can neither trip it nor silence it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_scan.dart';

const _macroSummation = 'lib/features/recipes/domain/recipe_macros.dart';
const _costSummation = 'lib/features/recipes/domain/recipe_cost.dart';

/// Money, as this app spells it.
final _moneyWords = RegExp(
  r'\b(cents?|Cents|money|Money|PriceObservation|PricePer100|'
  r'formatMoney\w*|paidCents)\b',
);

/// Nutrition, as this app spells it.
final _macroWords = RegExp(
  r'\b(Macros|MacroLineNote|MacroLineReason|RecipeMacroSummary|kcal|protein|'
  r'carb|fat|fiber|fibre|perServing|summarizeRecipeMacros)\b',
);

/// The file with its comments AND string literals blanked — what the word
/// checks read, so prose about either vocabulary cannot trip them.
String _code(String path) => blankNonCode(File(path).readAsStringSync());

/// The file with only its comments blanked — what the import checks read,
/// since an import path IS a string literal.
String _codeWithStrings(String path) =>
    blankComments(File(path).readAsStringSync());

void main() {
  test('the macro summation names nothing about money', () {
    final source = _code(_macroSummation);
    final hits = _moneyWords
        .allMatches(source)
        .map((m) => '${lineOf(source, m.start)}: ${m.group(0)}')
        .toList();
    expect(
      hits,
      isEmpty,
      reason:
          'A macro summary must never carry a price. Put the figure in '
          "RecipeCostSummary instead — the panel reads whichever it's showing.",
    );
  });

  test('the cost summation names nothing about macros', () {
    final source = _code(_costSummation);
    final hits = _macroWords
        .allMatches(source)
        .map((m) => '${lineOf(source, m.start)}: ${m.group(0)}')
        .toList();
    expect(
      hits,
      isEmpty,
      reason:
          'A cost is a unit price applied to an amount (ADR-0017), never a '
          'figure derived from anything nutritional.',
    );
  });

  test('neither summation imports the other', () {
    expect(
      _codeWithStrings(_costSummation),
      isNot(contains('recipe_macros.dart')),
    );
    expect(
      _codeWithStrings(_macroSummation),
      isNot(contains('recipe_cost.dart')),
    );
  });

  test('both reach the basis through the one shared conversion', () {
    // The point of the separation is that it costs the walk nothing: if the
    // two ever stopped sharing `lineAmountInBasis`, a line could weigh one
    // thing for its macros and another for its cost.
    for (final path in [_macroSummation, _costSummation]) {
      expect(
        _code(path),
        contains('lineAmountInBasis'),
        reason: '$path must convert through the shared seam.',
      );
    }
  });
}
