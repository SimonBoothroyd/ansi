/// What the AMOUNT slot of a reviewed import line may say — PURE DART
/// (invariant 2).
///
/// A line whose source printed no number and no mappable unit ("Tortilla chips
/// (to serve (optional))") used to dump its whole raw amount into the amount
/// column, where it read as a quantity it is not. The owner's call: the amount
/// slot shows the QUALIFIER the source named ("to serve") when there is one and
/// nothing at all ("—", rendered by the caller) when there isn't — and the raw
/// parenthetical travels to the NOTES slot, which is where free prose belongs.
///
/// Nothing here invents: both the qualifier and the note are substrings of what
/// the source actually printed (0014).
library;

/// The relative amount words a source uses in place of a quantity, longest
/// first so "for the garnish" wins over "garnish". Matched case-insensitively
/// against the printed amount; the MATCHED text is what the amount slot shows,
/// so the vocabulary is also the display vocabulary.
const kAmountQualifiers = <String>[
  'for the garnish',
  'for serving',
  'for garnish',
  'for dusting',
  'for drizzling',
  'to garnish',
  'to serve',
  'to taste',
  'to finish',
  'plus more',
];

/// The qualifier [rawAmount] names ("to serve"), or null when it names none.
///
/// Case-insensitive; the returned string is the canonical vocabulary spelling
/// from [kAmountQualifiers], so the amount slot reads consistently however the
/// source capitalized it.
String? amountQualifier(String rawAmount) {
  final lower = rawAmount.toLowerCase();
  for (final q in kAmountQualifiers) {
    if (lower.contains(q)) return q;
  }
  return null;
}

/// Whether [rawAmount] is prose rather than an amount: no digits anywhere and
/// something written. Such a string is a note the extractor filed in the amount
/// field ("(to serve (optional))"), and the caller routes it to NOTES.
bool isProseAmount(String rawAmount) =>
    rawAmount.trim().isNotEmpty && !RegExp('[0-9]').hasMatch(rawAmount);

/// [rawAmount] cleaned up for the NOTES slot: outer brackets peeled off and
/// whitespace collapsed, nothing else — the source's own words, minus the
/// punctuation that only ever wrapped them. Null when nothing is left.
String? amountAsNote(String rawAmount) {
  var text = rawAmount.trim().replaceAll(RegExp(r'\s+'), ' ');
  // Peel only BALANCED outer brackets: "(to serve (optional))" is a wrapper,
  // "(400g) tin" is not, and stripping the latter's parenthesis would change
  // what the source said.
  while (text.length > 1 && text.startsWith('(') && text.endsWith(')')) {
    var depth = 0;
    var balanced = true;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '(') depth++;
      if (text[i] == ')') depth--;
      if (depth == 0 && i < text.length - 1) {
        balanced = false;
        break;
      }
    }
    if (!balanced) break;
    text = text.substring(1, text.length - 1).trim();
  }
  return text.isEmpty ? null : text;
}
