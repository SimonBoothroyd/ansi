/// What the amount slot of a reviewed import line may say. Pure Dart.
///
/// A raw amount with no number and no mappable unit ("(to serve (optional))")
/// must not read as a quantity. The slot shows the qualifier the source named
/// ("to serve"), or nothing; the raw text goes to the notes slot. Both are
/// substrings of what the source printed.
library;

/// The relative amount words a source uses in place of a quantity, longest
/// first so "for the garnish" wins over "garnish". Matched case-insensitively;
/// the matched entry is what the slot shows.
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

/// The qualifier [rawAmount] names, in [kAmountQualifiers]' spelling, or null.
/// Case-insensitive.
String? amountQualifier(String rawAmount) {
  final lower = rawAmount.toLowerCase();
  for (final q in kAmountQualifiers) {
    if (lower.contains(q)) return q;
  }
  return null;
}

/// Whether [rawAmount] is prose rather than an amount: something written, with
/// no digits. The caller routes it to notes.
bool isProseAmount(String rawAmount) =>
    rawAmount.trim().isNotEmpty && !RegExp('[0-9]').hasMatch(rawAmount);

/// [rawAmount] cleaned for the notes slot: outer brackets peeled and whitespace
/// collapsed. Null when nothing is left.
String? amountAsNote(String rawAmount) {
  var text = rawAmount.trim().replaceAll(RegExp(r'\s+'), ' ');
  // Peel only balanced outer brackets: "(to serve (optional))" is a wrapper,
  // "(400g) tin" is not.
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
