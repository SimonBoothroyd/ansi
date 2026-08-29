import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/ingredients/domain/search_query.dart';

void main() {
  group('normalizeSearchQuery', () {
    test('lowercases', () {
      expect(normalizeSearchQuery('Tofu'), 'tofu');
    });

    test('treats hyphens/dashes as word breaks (mirrors normalize.ts)', () {
      // match_text is built with hyphens→spaces, so the query must be too or
      // "all-purpose" could never hit "all purpose flour".
      expect(normalizeSearchQuery('all-purpose'), 'all purpose');
      expect(normalizeSearchQuery('extra–virgin'), 'extra virgin'); // en dash
    });

    test('strips punctuation within words, keeps unicode letters', () {
      expect(normalizeSearchQuery("won't"), 'wont');
      expect(normalizeSearchQuery('jalapeño'), 'jalapeño');
    });

    test('strips LIKE wildcards so they cannot act as patterns', () {
      expect(normalizeSearchQuery('100%_flour'), '100flour');
    });

    test('collapses and trims whitespace', () {
      expect(normalizeSearchQuery('  spring   onion  '), 'spring onion');
      expect(normalizeSearchQuery('   '), '');
      expect(normalizeSearchQuery('--'), '');
    });
  });

  group('matchesSearchQuery (in-memory word-boundary match)', () {
    test('hits any word start, not just the leading word', () {
      expect(matchesSearchQuery('Weeknight Chicken Curry', 'chicken'), isTrue);
      expect(matchesSearchQuery('Weeknight Chicken Curry', 'week'), isTrue);
      expect(matchesSearchQuery('Weeknight Chicken Curry', 'cur'), isTrue);
    });

    test('never matches mid-word', () {
      expect(matchesSearchQuery('Weeknight Chicken Curry', 'hick'), isFalse);
      expect(matchesSearchQuery('Weeknight Chicken Curry', 'night'), isFalse);
    });

    test('normalizes both sides (hyphens, case)', () {
      expect(matchesSearchQuery('All-Purpose Loaf', 'purpose'), isTrue);
      expect(matchesSearchQuery('All-Purpose Loaf', 'ALL PURPOSE'), isTrue);
    });

    test('an empty or punctuation-only query matches everything', () {
      expect(matchesSearchQuery('Anything', ''), isTrue);
      expect(matchesSearchQuery('Anything', '  --  '), isTrue);
    });
  });
}
