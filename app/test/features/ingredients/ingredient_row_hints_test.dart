/// The vocabulary row's muted second line, as a table.
///
/// It is one string built from four independent facts, so the interesting
/// cases are the combinations — a stub that also lacks a density, a row whose
/// only fact is its category, a row with nothing to say at all. Proving those
/// through a pumped widget costs a frame each and reads as a screen test; the
/// join itself is a pure function, and one rendered assertion in
/// `ingredient_list_test.dart` is what proves it reaches the screen.
library;

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_picker.dart';
import 'package:flutter_test/flutter_test.dart';

Ingredient _ing({
  String? category,
  double? density,
  int measures = 0,
  IngredientStatus status = IngredientStatus.complete,
}) => Ingredient(
  id: 'i',
  canonicalName: 'thing',
  defaultUnit: g,
  status: status,
  category: category,
  densityGPerMl: density,
  measureCount: measures,
);

void main() {
  final table = <({String name, Ingredient ing, bool advisory, String hints})>[
    (
      name: 'a bare complete row has nothing to say, and says nothing',
      ing: _ing(),
      advisory: false,
      hints: '',
    ),
    (
      name: 'a category alone is the whole line',
      ing: _ing(category: 'produce'),
      advisory: false,
      hints: 'produce',
    ),
    (
      name: 'a density is a capability, stated as one',
      ing: _ing(category: 'produce', density: 0.66),
      advisory: false,
      hints: 'produce · has density',
    ),
    (
      name: 'one measure is singular, and the count leads the word',
      ing: _ing(measures: 1),
      advisory: false,
      hints: '1 measure',
    ),
    (
      name: 'more than one is plural',
      ing: _ing(measures: 3),
      advisory: false,
      hints: '3 measures',
    ),
    (
      name: 'a stub names what it is short of, in the last clause',
      ing: _ing(category: 'baking', status: IngredientStatus.stub),
      advisory: false,
      hints: 'baking · needs macros — no zeros shown',
    ),
    (
      name: 'the picker stays quiet about a missing density',
      ing: _ing(category: 'pantry'),
      advisory: false,
      hints: 'pantry',
    ),
    (
      name: 'the manager, which can fix it, says so',
      ing: _ing(category: 'pantry'),
      advisory: true,
      hints: 'pantry · no density — volume units locked',
    ),
    (
      name: 'a density beats the advisory: there is no gap left to report',
      ing: _ing(category: 'pantry', density: 1.03),
      advisory: true,
      hints: 'pantry · has density',
    ),
    (
      name: 'the full line, in order: category, density, measures, macros',
      ing: _ing(
        category: 'produce',
        measures: 3,
        status: IngredientStatus.stub,
      ),
      advisory: true,
      hints:
          'produce · no density — volume units locked · 3 measures · '
          'needs macros — no zeros shown',
    ),
  ];

  for (final c in table) {
    test('vocabRowHints — ${c.name}', () {
      expect(vocabRowHints(c.ing, advisoryDensityGap: c.advisory), c.hints);
    });
  }

  test('the table covers every clause', () {
    // A clause no row above earns is a clause that could be deleted from the
    // function without failing anything here.
    final all = table.map((c) => c.hints).join();
    for (final clause in [
      'has density',
      'no density — volume units locked',
      'measure',
      'measures',
      'needs macros — no zeros shown',
    ]) {
      expect(all, contains(clause), reason: clause);
    }
  });
}
