/// The Dart half of the `read-label` contract: what the function's JSON
/// decodes to, and what a missing, unusable or unknown value becomes.
///
/// The TypeScript half is `supabase/functions/_shared/label_types.ts`, coerced
/// by `_shared/adapters/label_schema.ts`. The two coerce the same way on
/// purpose: a figure that is not a usable printed figure is null at both ends,
/// and null means the form leaves that field alone.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/label_reading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LabelReading.fromJson', () {
    test('an EU label decodes whole, both columns', () {
      final reading = LabelReading.fromJson(const {
        'serving': {
          'amount': 30,
          'unit_printed': 'g',
          'text_printed': 'per 30 g serving',
        },
        'per_serving': {
          'kcal': 113,
          'protein_g': 4.1,
          'carbohydrate_g': 18.6,
          'fat_g': 1.9,
          'fibre_g': 3.2,
        },
        'per_100': {
          'basis': 'g',
          'kcal': 377,
          'protein_g': 13.7,
          'carbohydrate_g': 62.1,
          'fat_g': 6.2,
          'fibre_g': 10.6,
        },
        'notes': <String>[],
      });

      expect(reading.serving.amount, 30);
      expect(reading.serving.unit, g);
      expect(reading.serving.textPrinted, 'per 30 g serving');
      expect(reading.perServing.kcal, 113);
      expect(reading.perServing.fiber, 3.2);
      expect(reading.per100!.basis, MacrosBasis.perG);
      expect(reading.per100!.macros.kcal, 377);
      expect(reading.notes, isEmpty);
    });

    test('a US panel prints no per-100 column, and none is invented', () {
      final reading = LabelReading.fromJson(const {
        'serving': {
          'amount': 55,
          'unit_printed': 'g',
          'text_printed': 'Serving size 2/3 cup (55g)',
        },
        'per_serving': {
          'kcal': 230,
          'protein_g': 3,
          'carbohydrate_g': 37,
          'fat_g': 8,
          'fibre_g': 4,
        },
        'per_100': null,
        'notes': <String>[],
      });

      expect(reading.per100, isNull);
      expect(reading.perServing.kcal, 230);
    });

    test('a beverage column is per 100 ml, and the serving may be absent', () {
      final reading = LabelReading.fromJson(const {
        'serving': {'amount': null, 'unit_printed': null, 'text_printed': null},
        'per_serving': {
          'kcal': null,
          'protein_g': null,
          'carbohydrate_g': null,
          'fat_g': null,
          'fibre_g': null,
        },
        'per_100': {
          'basis': 'ml',
          'kcal': 59,
          'protein_g': 1.1,
          'carbohydrate_g': 7.1,
          'fat_g': 3,
          'fibre_g': 0.8,
        },
        'notes': ['The label prints only a per 100 ml column.'],
      });

      expect(reading.per100!.basis, MacrosBasis.perMl);
      expect(reading.perServing.isEmpty, isTrue);
      expect(reading.serving.unit, isNull);
      expect(reading.notes.single, contains('per 100 ml'));
    });

    test('a figure the label did not print decodes as null, never as zero', () {
      final reading = LabelReading.fromJson(const {
        'per_serving': {'kcal': 90, 'protein_g': null, 'carbohydrate_g': 21},
      });
      expect(reading.perServing.kcal, 90);
      expect(reading.perServing.protein, isNull);
      expect(reading.perServing.fat, isNull);
      expect(reading.perServing.fiber, isNull);
      // A zero IS a figure, and a label does print one.
      final zero = LabelReading.fromJson(const {
        'per_serving': {'fat_g': 0},
      });
      expect(zero.perServing.fat, 0);
    });

    test('a figure that cannot be a printed figure decodes as null', () {
      final reading = LabelReading.fromJson(const {
        'per_serving': {
          'kcal': -12, // a label never prints a negative
          'protein_g': '4.1', // a number sent as a string is still a number
          'carbohydrate_g': 'not a number',
        },
      });
      expect(reading.perServing.kcal, isNull);
      expect(reading.perServing.protein, 4.1);
      expect(reading.perServing.carb, isNull);
    });

    test('a per-100 column whose basis is neither g nor ml is dropped', () {
      // We would not know which 100 it was, and the form converts by it.
      final reading = LabelReading.fromJson(const {
        'per_serving': {'kcal': 100},
        'per_100': {'basis': 'oz', 'kcal': 350},
      });
      expect(reading.per100, isNull);
    });

    test('a serving unit this kitchen does not keep stays unparsed', () {
      final reading = LabelReading.fromJson(const {
        'serving': {'amount': 1, 'unit_printed': 'biscuit'},
        'per_serving': {'kcal': 50},
      });
      expect(reading.serving.amount, 1);
      expect(reading.serving.unitPrinted, 'biscuit');
      // Not approximated into something: the form keeps the row's own serving.
      expect(reading.serving.unit, isNull);
    });

    test('a household measure is read as the unit it names', () {
      final reading = LabelReading.fromJson(const {
        'serving': {'amount': 1, 'unit_printed': 'tbsp'},
        'per_serving': {'kcal': 90},
      });
      expect(reading.serving.unit, tbsp);
    });

    test('an answer with nothing in it decodes to an empty reading', () {
      final reading = LabelReading.fromJson(const {});
      expect(reading.perServing.isEmpty, isTrue);
      expect(reading.per100, isNull);
      expect(reading.serving.amount, isNull);
      expect(reading.notes, isEmpty);
    });
  });
}
