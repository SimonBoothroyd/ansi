/// Which corrected strings the learning loop is allowed to keep: names a
/// household would say, never the whole printed line.
library;

import 'package:ansi/features/import/domain/learnable_alias.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a plain name is learned, however many words it has', () {
    // The loop's whole value: the household's own phrasing, absorbed. Length
    // is not the test — "too descriptive" would be taste, not a rule.
    for (final name in [
      'dried sage',
      'butter beans',
      'sweet white sorghum flour',
      'brown onions',
      'extra virgin olive oil',
      'stone-ground mustard',
      'Jalapeño',
      'coco milk',
    ]) {
      expect(looksLikeAName(name), isTrue, reason: name);
    }
  });

  test('a comma means a modifier is hanging off the name', () {
    for (final line in [
      'Olive oil, for frying',
      'fresh basil, reserved for garnish',
      'tomatoes, chopped',
      'salt, to taste',
    ]) {
      expect(looksLikeAName(line), isFalse, reason: line);
    }
  });

  test('the word OR means the line named two things, not one', () {
    for (final line in [
      'stone-ground mustard or Creole mustard',
      'olive oil or cooking oil of choice',
      'vegan cheddar or American cheese',
      'Butter Or Margarine',
    ]) {
      expect(looksLikeAName(line), isFalse, reason: line);
    }
  });

  test('…and only the word, never the letters inside one', () {
    // A rule that fired on the substring would refuse half the vocabulary.
    for (final name in [
      'orange',
      'Orange Zest',
      'cilantro',
      'oregano',
      'chorizo',
      'porcini mushrooms',
    ]) {
      expect(looksLikeAName(name), isTrue, reason: name);
    }
  });

  test('a slash is the same choice, punctuated', () {
    expect(looksLikeAName('butter/margarine'), isFalse);
    expect(looksLikeAName('half and half / single cream'), isFalse);
  });

  test('a bracket is an aside, and an aside is not part of a name', () {
    expect(looksLikeAName('parsley (flat-leaf)'), isFalse);
    expect(looksLikeAName('stock [homemade]'), isFalse);
    expect(looksLikeAName('flour {plain}'), isFalse);
  });
}
