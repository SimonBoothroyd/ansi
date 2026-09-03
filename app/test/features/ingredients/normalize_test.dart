/// Parity + behaviour tests for the Dart phrase normalizer (plan 0020 D6).
///
/// The parity group reads `normalize_vectors.json` — pairs copied verbatim
/// from `supabase/functions/_shared/normalize.test.ts`, each carrying the
/// Deno test case it came from. It is the mirror guard: the app now writes
/// `match_text` too, so a rule that drifts on either side has to fail here
/// rather than fail an import six weeks later.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shared vectors — parity with normalize.ts', () {
    final file = File('test/features/ingredients/normalize_vectors.json');
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final vectors = (decoded['vectors'] as List).cast<Map<String, dynamic>>();

    test('the vector file actually loaded', () {
      // A missing or emptied fixture would make every case below vacuous.
      expect(vectors.length, greaterThanOrEqualTo(30));
    });

    for (final v in vectors) {
      final input = v['in'] as String;
      final expected = v['out'] as String;
      final from = v['from'] as String;
      test('[$from] "$input" → "$expected"', () {
        expect(normalizeMatchText(input), expected);
      });
    }
  });

  group('the properties the cascade depends on', () {
    test('is idempotent — a stored name is already in its own normal form', () {
      for (final phrase in [
        '2 large Onions, diced',
        'a handful of curry leaves',
        'fresh ginger, grated',
        'extra-virgin olive oil',
      ]) {
        final once = normalizeMatchText(phrase);
        expect(normalizeMatchText(once), once, reason: phrase);
      }
    });

    test('is symmetric: a recipe line and the stored name it names land on '
        'the same text', () {
      expect(
        normalizeMatchText('a handful of curry leaves'),
        normalizeMatchText('Curry leaves, fresh').replaceAll(' fresh', ''),
      );
      expect(
        normalizeMatchText('2 cloves garlic, minced'),
        normalizeMatchText('Garlic'),
      );
    });

    test('a phrase of nothing but filler normalizes to empty — the repository '
        'refuses those as aliases rather than storing a match-anything', () {
      expect(normalizeMatchText('a handful of'), '');
      expect(normalizeMatchText('2 large'), '');
      expect(normalizeMatchText('   '), '');
    });

    test('it is NOT the search normalizer: a search prefix must not be '
        'singularized or reordered', () {
      // The picker types "leaves" mid-word and must still be able to hit;
      // singularizing an in-flight prefix would make matching worse.
      expect(normalizeSearchQuery('curry leaves'), 'curry leaves');
      expect(normalizeMatchText('curry leaves'), 'curry leaf');
      expect(normalizeSearchQuery('fresh ginger'), 'fresh ginger');
      expect(normalizeMatchText('fresh ginger'), 'ginger fresh');
    });
  });

  group('matchTextForms — the bridge over that gap', () {
    test('a plural token carries its singular alongside the raw form', () {
      // The two forms are what the vocab search LIKEs against: without the
      // singular, "almonds" could never word-prefix the `almond` the
      // normalizer wrote.
      expect(matchTextForms('almonds'), ['almonds', 'almond']);
      expect(matchTextForms('leaves'), ['leaves', 'leaf']);
      expect(matchTextForms('tomatoes'), ['tomatoes', 'tomato']);
    });

    test('a token the singularizer leaves alone yields one form', () {
      // No duplicate branch for the common case — including the words that
      // only look plural.
      expect(matchTextForms('almond'), ['almond']);
      expect(matchTextForms('almo'), ['almo']); // mid-typing prefix
      expect(matchTextForms('asparagus'), ['asparagus']);
      expect(matchTextForms('boneless'), ['boneless']);
      // The explicit invariant set, not the regex guard: `molass` must never
      // be tried as a second form now that no row is written with it.
      expect(matchTextForms('molasses'), ['molasses']);
    });

    test('every form is still free of LIKE wildcards', () {
      // Singularization only trims the tail, so a `%`/`_`-stripped token stays
      // stripped — the search binds these straight into LIKE patterns.
      for (final form in matchTextForms(normalizeSearchQuery('on_ons'))) {
        expect(form, isNot(anyOf(contains('%'), contains('_'))));
      }
    });

    test("singularizeToken is the normalizer's own rule, not a new one", () {
      // Same function the phrase normalizer's last step uses: one word in,
      // its singular out, with the irregulars honoured.
      expect(singularizeToken('leaves'), 'leaf');
      expect(singularizeToken('chillies'), 'chilli');
      expect(singularizeToken('boneless'), 'boneless');
      expect(singularizeToken('molasses'), 'molasses');
      expect(normalizeMatchText('Almonds'), singularizeToken('almonds'));
    });
  });
}
