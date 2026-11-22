/// Reading a step's own amount out of the words a person selected. Pure Dart.
///
/// Runs once, on text the person chose to mark (ADR-0004): prose is never
/// pattern-matched into an amount as it is drawn.
library;

import '../../../core/units/number_format.dart';

/// The number words a step says an amount in.
const _numberWords = <String, double>{
  'a': 1,
  'an': 1,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'half': 0.5,
  'half a': 0.5,
  'half an': 0.5,
};

/// [text]'s leading number and the word it counts: `one empty can` is 1 and
/// `can`, `4 tablespoons` 4 and `tablespoons`, `1 1/2 cups of stock` 1.5 and
/// `cups`. The word is the last before any `of`, so an adjective does not
/// become the unit. A null `qty` where no number leads: the sheet then opens
/// with the field empty.
({double? qty, String word}) readAmountWords(String text) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.isEmpty || words.first.isEmpty) return (qty: null, word: '');
  double? qty;
  var used = 0;
  // The longest number that leads: `1 1/2`, then `1`, then a word.
  for (var n = words.length < 2 ? words.length : 2; n > 0 && qty == null; n--) {
    final lead = words.take(n).join(' ');
    final parsed = parseAmount(lead) ?? _numberWords[lead.toLowerCase()];
    if (parsed != null) {
      qty = parsed;
      used = n;
    }
  }
  var rest = words.skip(used).toList();
  final of = rest.indexWhere((w) => w.toLowerCase() == 'of');
  if (of >= 0) rest = rest.take(of).toList();
  return (qty: qty, word: rest.isEmpty ? '' : rest.last);
}
