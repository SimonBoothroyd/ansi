import 'package:ansi/features/recipes/domain/method_draft.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/step_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readAmountWords', () {
    const cases = <({String text, double? qty, String word})>[
      (text: 'one empty can', qty: 1, word: 'can'),
      (text: '4 tablespoons', qty: 4, word: 'tablespoons'),
      (text: '1 1/2 cups of stock', qty: 1.5, word: 'cups'),
      (text: '½ cup', qty: 0.5, word: 'cup'),
      (text: 'a cup of the pasta water', qty: 1, word: 'cup'),
      (text: 'half a lemon', qty: 0.5, word: 'lemon'),
      (text: 'some water', qty: null, word: 'water'),
      (text: '', qty: null, word: ''),
    ];
    for (final c in cases) {
      test('"${c.text}" reads ${c.qty} ${c.word}', () {
        final read = readAmountWords(c.text);
        expect(read.qty, c.qty);
        expect(read.word, c.word);
      });
    }
  });

  group('an amount in the editor draft', () {
    const step = MethodStep(
      tokens: [
        MethodText(s: 'Fill '),
        MethodAmount(text: 'one empty can', qty: 1, unit: 'can'),
        MethodText(s: ' with water.'),
      ],
    );

    test('round-trips through the draft unchanged', () {
      final draft = toDraft(step, id: 's');
      expect(draft.text, 'Fill one empty can with water.');
      expect(draft.spans.single, isA<AmountSpan>());
      expect(toTokens(draft), step);
    });

    test('marking keeps the words; re-stating rewrites them only when the '
        'figure changed', () {
      const plain = MethodDraftStep(id: 's', text: 'Fill one empty can.');
      final marked = markAmount(plain, start: 5, end: 18, qty: 1, unit: 'can');
      expect(marked.text, 'Fill one empty can.');
      expect(reAmount(marked, 0, qty: 1, unit: 'can').text, marked.text);
      final changed = reAmount(marked, 0, qty: 2, unit: 'cups');
      expect(changed.text, 'Fill 2 cups.');
      expect(
        toTokens(changed).tokens[1],
        const MethodAmount(text: '2 cups', qty: 2, unit: 'cups'),
      );
    });

    test('inserting writes the figure and its word', () {
      const plain = MethodDraftStep(id: 's', text: 'Add  of water.');
      final added = insertAmountAt(plain, offset: 4, qty: 0.5, unit: 'cup');
      expect(added.text, 'Add ½ cup of water.');
    });
  });
}
