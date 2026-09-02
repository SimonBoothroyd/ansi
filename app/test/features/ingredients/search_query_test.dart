import 'package:ansi/features/ingredients/domain/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

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
      // The letter survives — folded to its base, never deleted.
      expect(normalizeSearchQuery('jalapeño'), 'jalapeno');
    });

    test('folds Latin diacritics so an unaccented query still hits', () {
      // The stored match_text is folded by the same rule (normalize.dart and
      // its TypeScript mirror), so the two sides meet on 'jalapeno'.
      expect(normalizeSearchQuery('Jalapeño'), 'jalapeno');
      expect(normalizeSearchQuery('jalapeno'), 'jalapeno');
      expect(normalizeSearchQuery('crème fraîche'), 'creme fraiche');
      expect(normalizeSearchQuery('AÇAÍ'), 'acai');
      // Already-decomposed input folds too (the combining mark is dropped).
      expect(normalizeSearchQuery('jalapen\u0303o'), 'jalapeno');
      // Letters that are not accented ones keep their identity, exactly as
      // the server's NFD does.
      expect(normalizeSearchQuery('Smørrebrød'), 'smørrebrød');
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
}
