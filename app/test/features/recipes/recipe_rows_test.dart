import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe_rows.dart';
import 'package:flutter_test/flutter_test.dart';

/// One line row as the app's SQLite hands it over: flags as 0/1, jsonb as
/// text.
StoredRow _sqliteLine() => {
  'id': 'l1',
  'group_id': 'g1',
  'ingredient_id': 'soy',
  'sub_recipe_id': null,
  'quantity': 1,
  'unit': 'tbsp',
  'recipe_measure_id': null,
  'optional': 0,
  'note': 'light',
  'measure_id': null,
  'ingredient_name': 'Soy sauce',
  'ingredient_basis': 'g',
  'ingredient_macros': '{"kcal":53,"protein":8,"carb":5,"fat":0}',
  'ingredient_density': 1.2,
  'ingredient_piece_weight': null,
  'ingredient_status': 'complete',
  'ingredient_deleted_at': null,
};

/// The same row as Postgres JSON hands it over: flags as booleans, jsonb as
/// an object, a `numeric` as text.
StoredRow _postgresLine() => {
  ..._sqliteLine(),
  'optional': false,
  'quantity': '1',
  'ingredient_macros': {'kcal': 53, 'protein': 8, 'carb': 5, 'fat': 0},
  'ingredient_density': '1.2',
};

void main() {
  group('the two stores read alike', () {
    test('a line row', () {
      expect(
        lineItemOfRow(_postgresLine(), const {}),
        lineItemOfRow(_sqliteLine(), const {}),
      );
    });

    test("a line row's nutrition", () {
      final sqlite = nutritionOfLineRow(_sqliteLine())!;
      final postgres = nutritionOfLineRow(_postgresLine())!;
      expect(postgres.macros, sqlite.macros);
      expect(postgres.macros!.kcal, 53);
      expect(postgres.basis, MacrosBasis.perG);
      expect(postgres.densityGPerMl, 1.2);
    });

    test('flags, numbers and json', () {
      expect(rowFlag(1), isTrue);
      expect(rowFlag(true), isTrue);
      expect(rowFlag(0), isFalse);
      expect(rowFlag(null), isFalse);
      expect(rowNumber('2.5'), 2.5);
      expect(rowNumber(3), 3.0);
      expect(rowNumber('n/a'), isNull);
      expect(rowInt('7'), 7);
      expect(rowJson('[1,2]'), [1, 2]);
      expect(rowJson([1, 2]), [1, 2]);
      expect(rowJson('{not json'), isNull);
    });
  });

  group('the honest-numbers rules', () {
    test("a stub's macros are excluded, whatever lingers on the row", () {
      final stub = nutritionOfLineRow({
        ..._postgresLine(),
        'ingredient_status': 'stub',
      })!;
      expect(stub.macros, isNull);
    });

    test('a retired or unknown ingredient contributes nothing', () {
      expect(
        nutritionOfLineRow({
          ..._postgresLine(),
          'ingredient_deleted_at': '2026-01-01T00:00:00Z',
        }),
        isNull,
      );
      expect(
        nutritionOfLineRow({..._postgresLine(), 'ingredient_status': null}),
        isNull,
      );
    });

    test('a line said in a recipe word has no unit', () {
      final line = lineItemOfRow({
        ..._postgresLine(),
        'ingredient_id': null,
        'sub_recipe_id': 'mb',
        'sub_title': 'Miso butter',
        'unit': null,
        'recipe_measure_id': 'm-blob',
        'quantity': 2,
      }, const {});
      expect(line.unit, isNull);
      expect(line.ingredientName, 'Miso butter');
      expect(line.recipeMeasureId, 'm-blob');
    });

    test('an unknown unit reads as piece on a line', () {
      final line = lineItemOfRow({
        ..._postgresLine(),
        'unit': 'smidgen',
      }, const {});
      expect(line.unit, pieces);
    });

    test(
      'an unknown unit drops a recipe measure rather than inventing one',
      () {
        final byRecipe = recipeMeasuresByRecipe([
          {
            'id': 'm1',
            'recipe_id': 'mb',
            'label': 'blob',
            'amount': 15,
            'unit': 'g',
            'sort_order': 0,
            'created_at': '2026-01-01T00:00:00Z',
          },
          {
            'id': 'm2',
            'recipe_id': 'mb',
            'label': 'dollop',
            'amount': '30',
            'unit': 'smidgen',
            'sort_order': 1,
            'created_at': '2026-01-02T00:00:00Z',
          },
        ]);
        expect([for (final m in byRecipe['mb']!) m.label], ['blob']);
        expect(byRecipe['mb']!.single.amount, 15);
      },
    );

    test('duplicate words merge, oldest first, the twin kept behind it', () {
      final byRecipe = recipeMeasuresByRecipe([
        {
          'id': 'late',
          'recipe_id': 'mb',
          'label': 'blob',
          'amount': 20,
          'unit': 'g',
          'created_at': '2026-02-01T00:00:00Z',
        },
        {
          'id': 'early',
          'recipe_id': 'mb',
          'label': 'blob',
          'amount': 15,
          'unit': 'g',
          'created_at': '2026-01-01T00:00:00Z',
        },
      ]);
      expect([for (final m in byRecipe['mb']!) m.id], ['early', 'late']);
    });
  });

  group('stepsOfColumn', () {
    test('plain steps, as text or as a list', () {
      expect(stepsOfColumn('["Boil.","Drain."]').$1, ['Boil.', 'Drain.']);
      expect(stepsOfColumn(['Boil.']).$1, ['Boil.']);
      expect(stepsOfColumn(null).$2, isNull);
    });

    test('tokenized steps', () {
      final (plain, tokenized) = stepsOfColumn([
        {
          'tokens': [
            {'t': 'text', 's': 'Simmer for '},
            {'t': 'timer', 'low_seconds': 1200, 'high_seconds': 1500},
          ],
        },
      ]);
      expect(plain, isEmpty);
      expect(tokenized!.single.tokens.last, isA<MethodTimer>());
    });
  });

  test('yields read under a prefix', () {
    final yields = yieldsOfRow({
      'sub_yield_qty': '300',
      'sub_yield_unit': 'g',
    }, prefix: 'sub_');
    expect(yields.single.qty, 300);
    expect(yields.single.unit, g);
  });
}
