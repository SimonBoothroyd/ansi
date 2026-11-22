import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/method_uses.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lineById = {
    for (final id in ['chicken', 'lime', 'coriander', 'onion', 'garlic'])
      id: LineItem(id: id, ingredientName: id, unit: g, quantity: 1),
  };
  MethodText t(String s) => MethodText(s: s);
  MethodRef c(String id) => MethodRef(refs: [id], label: id);

  List<String> quoted(List<List<MethodToken>> steps, String id) => [
    for (final u in stepUsesOf(
      [for (final s in steps) MethodStep(tokens: s)],
      {id},
      lineById: lineById,
    ))
      '${u.step}: ${u.before}[${u.word}]${u.after}',
  ];

  final finish = [
    [t('Brown the '), c('chicken'), t('.')],
    [
      t('Off the heat, squeeze over the '),
      c('lime'),
      t(' and scatter with '),
      c('coriander'),
      t('.'),
    ],
  ];

  test('a quote is the ingredient’s own clause', () {
    expect(quoted(finish, 'lime'), [
      '2: Off the heat, squeeze over the [lime]…',
    ]);
    expect(quoted(finish, 'coriander'), ['2: …and scatter with [coriander].']);
  });

  test('a list is quoted whole: its verb is at the front', () {
    final list = [
      [t('Fry the '), c('onion'), t(', '), c('garlic'), t(' until soft.')],
    ];
    expect(quoted(list, 'garlic'), ['1: Fry the onion, [garlic] until soft.']);
    expect(quoted(list, 'onion'), ['1: Fry the [onion], garlic until soft.']);
  });

  test('only the sentence it is in, and a decimal ends none', () {
    final long = [
      [
        t('Heat 1.5 cups of stock. Stir through the '),
        c('lime'),
        t(' at the end. Serve hot.'),
      ],
    ];
    expect(quoted(long, 'lime'), ['1: Stir through the [lime] at the end.']);
  });

  test('every step that uses it, once each', () {
    final twice = [
      [t('Zest the '), c('lime'), t(', then juice the '), c('lime'), t('.')],
      [t('Serve with '), c('lime'), t('.')],
    ];
    expect(quoted(twice, 'lime'), hasLength(2));
  });

  test('a line no chip names has nothing to quote', () {
    expect(quoted(finish, 'garlic'), isEmpty);
  });
}
