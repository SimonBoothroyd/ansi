/// The pack size a receipt's printed name states — `Organic Unsweetened
/// Soymilk, 64 fl oz`, `Beyond Beef Plant Based Ground Brick, 12 Ounce`. Pure
/// Dart (invariant 2).
///
/// Read off the paper, never guessed: a name that states no weight or volume,
/// or one that sells several of the thing at once (`Pack of 6`, `4 ct`), says
/// nothing here and the review asks.
library;

import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';

/// An amount in a catalog weight or volume unit, as the name printed it.
typedef PrintedSize = ({double amount, Unit unit});

/// The first weight or volume [name] states, or null. A figure that is a
/// nutrition claim (`12g Protein`) is not a size, and a multipack refuses
/// outright: its size is one of several, and the count is not on the line.
PrintedSize? sizeInPrintedName(String? name) {
  if (name == null) return null;
  final text = name.toLowerCase();
  if (_multipack.hasMatch(text)) return null;
  for (final m in _figure.allMatches(text)) {
    if (_claim.hasMatch(text.substring(m.end))) continue;
    final amount = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    final unit = unitFromWord(
      _unitWord(m.group(2)!),
      families: const {UnitFamily.mass, UnitFamily.volume},
    );
    if (amount == null || !(amount > 0) || unit == null) continue;
    return (amount: amount, unit: unit);
  }
  return null;
}

/// `fl. oz`, `fluid ounces` and `floz` all say `fl oz`.
String _unitWord(String word) =>
    RegExp(r'^(fl\.?\s*oz|fluid\s+ounces?)$').hasMatch(word) ? 'fl oz' : word;

/// A figure and the word after it: `64 fl oz`, `5oz`, `15.5 ounce`, `1-lb`.
final _figure = RegExp(
  r'(?<![\w.])(\d+(?:[.,]\d+)?)\s*-?\s*'
  r'(fl\.?\s*oz|fluid\s+ounces?|[a-z]+)\b',
);

/// What follows a figure that is a claim about the food, not its size.
final _claim = RegExp(
  r'^\s*(of\s+)?(protein|fat|sugars?|fib(er|re)|carbs?|net\s+carbs|'
  r'carbohydrates?|sodium|salt|calories)\b',
);

/// `Pack of 6`, `6 pack`, `6-pk`, `4 ct`, `12 count`, `6 x 330 ml`.
final _multipack = RegExp(
  r'pack\s+of\s+\d|\b\d+\s*-?\s*(pack|pk|ct|count)\b|\b\d+\s*x\s*\d',
);
