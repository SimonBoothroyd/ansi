import 'package:ansi/features/import/domain/amount_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('amountQualifier', () {
    test('finds the qualifier a printed amount names', () {
      expect(amountQualifier('(to serve (optional))'), 'to serve');
      expect(amountQualifier('To Taste'), 'to taste');
      expect(amountQualifier('a few, for garnish'), 'for garnish');
    });

    test('prefers the longer phrase', () {
      expect(amountQualifier('for the garnish'), 'for the garnish');
    });

    test('is null when the amount names none', () {
      expect(amountQualifier('2–3 cloves'), isNull);
      expect(amountQualifier(''), isNull);
    });
  });

  group('isProseAmount', () {
    test('a numberless written amount is prose', () {
      expect(isProseAmount('(to serve (optional))'), isTrue);
      expect(isProseAmount('A good pinch'), isTrue);
    });

    test('anything carrying a number is an amount', () {
      expect(isProseAmount('2–3 cloves'), isFalse);
      expect(isProseAmount('1 x 400g tin'), isFalse);
    });

    test('nothing written is not prose either', () {
      expect(isProseAmount('   '), isFalse);
    });
  });

  group('amountAsNote', () {
    test('peels the brackets that only ever wrapped the words', () {
      expect(amountAsNote('(to serve (optional))'), 'to serve (optional)');
    });

    test('keeps a bracket that is part of the text', () {
      // Not a wrapper: peeling it would change what the source said.
      expect(amountAsNote('(400g) tin'), '(400g) tin');
    });

    test('collapses whitespace and reports emptiness as null', () {
      expect(amountAsNote('  to   serve '), 'to serve');
      expect(amountAsNote('()'), isNull);
      expect(amountAsNote('   '), isNull);
    });
  });
}
