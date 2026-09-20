/// Which corrected strings the learning loop is allowed to keep: names a
/// household would say — never a line, and never a decision.
library;

import 'dart:io';

import 'package:ansi/features/import/domain/learnable_alias.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/source_scan.dart';

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

  test('a phrase that names a DECISION is not a name, however it is '
      'punctuated', () {
    // The gap the marks could not see. "your favourite pasta" is punctuated
    // exactly like "brown onions" and got through on that alone; what is
    // wrong with it is the words. The next cook's favourite pasta is a
    // different pasta, so no future line can print these words meaning this
    // row.
    for (final line in [
      // Second person and possessive.
      'your favourite pasta',
      'your usual bread',
      'my go-to hot sauce',
      'our usual bread',
      // Open choice.
      'any plant milk',
      'either pasta shape',
      'whatever greens are in the fridge',
      'whichever noodles you have',
      'some kind of squash',
      // Preference.
      'favourite pasta',
      'pasta of choice',
      'preferred sweetener',
      'desired berries',
      'desired pasta noodles',
      'noodles to your liking',
      'salt to taste',
      'optional garnish',
      'ideally cavatappi',
    ]) {
      expect(looksLikeAName(line), isFalse, reason: line);
    }
  });

  test('…and only whole words, so the set cannot eat a food name', () {
    // The set is matched word by word: a name is refused because it contains
    // the word, never because it contains the letters. "sesame" is not
    // "some", and a page printing a name in title case says "Your" no
    // differently.
    for (final name in [
      'sesame seeds',
      'anise',
      'ancho chilli',
      'tastee cheese',
      'mineral water',
      'sourdough',
      'choy sum',
      'youngberry',
    ]) {
      expect(looksLikeAName(name), isTrue, reason: name);
    }
    expect(looksLikeAName('Your Favourite Pasta'), isFalse);
  });

  test("the owner's own vocabulary is the evidence the rule is not too "
      'tight', () {
    // Swept over his whole vocabulary, seed aliases and learned ones alike:
    // every phrase he has ever corrected onto a row survives the rule —
    // including the judgement call, "cooking oil spray", which is a thing a
    // shop sells and a page can print again. Only the decision shape is
    // refused, and his vocabulary no longer carries any.
    for (final name in [
      'cooking oil spray',
      'full-fat oat milk',
      'chipotle chile flakes',
      'Tenderstem broccoli',
      'vegetable stock cube',
      'chocolate protein powder',
      'ground white pepper',
      'lime wedges',
      'fresh coriander leaves',
      'Creole Spice Blend',
      'boiling water',
      'wild garlic',
      'cornflour',
    ]) {
      expect(looksLikeAName(name), isTrue, reason: name);
    }
  });

  group('structural', () {
    test('every learning door in the app asks this question', () {
      // The predicate is only worth what its callers are. A second write of a
      // learned alias that forgot to ask would reopen the whole class, so the
      // sweep names the file that writes one — the ingredient form's alias
      // chips are a human typing a name on purpose (`source = 'manual'`) and
      // are not a learning door.
      final writers = [
        for (final file in dartFiles(Directory('lib')))
          // Comments blanked, string literals kept: the source it hunts for IS
          // a literal, and prose about it must neither trip nor silence this.
          if (blankComments(
            file.readAsStringSync(),
          ).contains("'import_correction'"))
            file.path,
      ]..sort();
      expect(writers, ['lib/features/import/data/import_repository_impl.dart']);
      expect(
        blankNonCode(File(writers.single).readAsStringSync()),
        contains('looksLikeAName('),
        reason: 'the one learning door must gate its write on the predicate',
      );
    });

    test('no alias the seed template carries could be learned today', () {
      // The seed is generated from the owner's own vocabulary, so a phrase the
      // loop should never learn must not be able to ride into every future
      // household's template either. There is no allowance: every alias in the
      // generated file answers the same question a learned one does, and a
      // regeneration that carried a new decision-shaped phrase fails here
      // rather than seeding it into every household to come. The fix is always
      // in the vocabulary this file is generated from — rename the alias when
      // its key is worth keeping, retire it when it is not.
      final seed = File('../supabase/seed_vocab.sql').readAsStringSync();
      final block = seed.substring(
        seed.indexOf('insert into ingredient_alias'),
      );
      final aliases = RegExp(
        r"^  \('(?:[^']|'')*', '((?:[^']|'')*)',",
        multiLine: true,
      ).allMatches(block.substring(0, block.indexOf(') as a(')));
      final texts = [for (final m in aliases) m[1]!.replaceAll("''", "'")];
      expect(texts, hasLength(greaterThan(100)), reason: 'the block was read');
      expect(
        {
          for (final t in texts)
            if (!looksLikeAName(t)) t,
        },
        isEmpty,
        reason:
            'rename or retire it in the vocabulary, then re-export the seed',
      );
    });
  });
}
