/// The week's leftovers in one line, and one batch's answer in words.
library;

import 'package:ansi/features/cook_plan/domain/leftovers.dart';
import 'package:ansi/features/cook_plan/presentation/cook_view_models.dart';
import 'package:ansi/features/cook_plan/presentation/leftover_question.dart';
import 'package:flutter_test/flutter_test.dart';

BatchLeftover _left(String key, double portions) => BatchLeftover(
  key: key,
  recipeId: key,
  title: key,
  cookDate: DateTime(2026, 10, 26),
  useBy: DateTime(2026, 10, 30),
  portions: portions,
);

void main() {
  test('what was binned, then what cooked batches still have left', () {
    expect(
      leftoverLineFor(
        answers: {'ragu': (kept: 0, binned: 2, eaten: 0)},
        leftovers: [_left('curry', 1)],
      ),
      '2 portions binned · 1 left',
    );
  });

  test('eaten after all is not waste, and a kept answer is no answer', () {
    expect(
      leftoverLineFor(
        answers: {
          'ragu': (kept: 0, binned: 0, eaten: 2),
          'dal': (kept: 1, binned: 0, eaten: 0),
        },
        leftovers: [_left('dal', 1)],
      ),
      '1 portion left',
    );
  });

  test('nothing binned and nothing left says nothing', () {
    expect(leftoverLineFor(answers: const {}, leftovers: const []), isNull);
  });

  test('an answer said in words', () {
    expect(
      leftoverAnswerLine((kept: 0, binned: 1, eaten: 0)),
      '1 portion binned',
    );
    expect(
      leftoverAnswerLine((kept: 0, binned: 0, eaten: 2)),
      '2 portions eaten after all',
    );
    expect(
      leftoverAnswerLine((kept: 1, binned: 0.5, eaten: 0)),
      '1 kept · ½ binned',
    );
  });
}
