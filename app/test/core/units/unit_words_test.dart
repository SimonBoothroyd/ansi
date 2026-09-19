import 'package:ansi/core/units/unit_words.dart';
import 'package:ansi/core/units/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unitFromWord', () {
    test('reads the spellings a recipe page prints', () {
      expect(unitFromWord('CUP'), cup);
      expect(unitFromWord('tablespoons'), tbsp);
      expect(unitFromWord('grammes'), g);
      expect(unitFromWord(' pints '), pint);
    });

    test('reads the spellings a product label prints', () {
      expect(unitFromWord('gr'), g);
      expect(unitFromWord('fl oz'), flOz);
      expect(unitFromWord('floz'), flOz);
      expect(unitFromWord('qt'), quart);
    });

    test('one table, so each reader now knows the other half', () {
      // `gr` came from the pack table and `kilo` from the yield table; a word
      // either reader understood is a word both understand.
      expect(unitFromWord('kilo'), kg);
      expect(unitFromWord('milliliters'), ml);
    });

    test('a word outside the table is never approximated', () {
      expect(unitFromWord('cl'), isNull);
      expect(unitFromWord('pack'), isNull);
      expect(unitFromWord('sliders'), isNull);
      expect(unitFromWord(''), isNull);
    });

    test('families narrow the answer to what the caller can accept', () {
      const packs = {UnitFamily.mass, UnitFamily.volume};
      expect(unitFromWord('pieces'), pieces);
      expect(unitFromWord('pieces', families: packs), isNull);
      expect(unitFromWord('400', families: packs), isNull);
      expect(unitFromWord('ml', families: packs), ml);
    });
  });

  group('unitFromLabel', () {
    test('reads the word the chip row prints, however it is typed', () {
      expect(unitFromLabel('tbsp'), tbsp);
      expect(unitFromLabel('Cups '), cup);
      expect(unitFromLabel('ML'), ml);
      expect(unitFromLabel('fl oz'), flOz);
    });

    test('knows `batch`, which the spelling table does not', () {
      // The authoring half asks the catalog, so the one unit no page ever
      // prints is still refused as somebody's word for their own recipe.
      expect(unitFromWord('batch'), isNull);
      expect(unitFromLabel('batch'), batches);
      expect(unitFromLabel('Batch'), batches);
    });

    test('a household word is not a unit', () {
      expect(unitFromLabel('blob'), isNull);
      expect(unitFromLabel('ladle'), isNull);
      expect(unitFromLabel('can (400 g)'), isNull);
      expect(unitFromLabel('  '), isNull);
    });

    test('the volume half is the same lookup, narrowed', () {
      expect(volumeUnitFromLabel('tbsps'), tbsp);
      expect(volumeUnitFromLabel('g'), isNull);
      expect(isVolumeUnitLabel('Cups'), isTrue);
      expect(isVolumeUnitLabel('clove'), isFalse);
    });
  });
}
