import 'package:ansi/features/ingredients/domain/suggest_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a recipe line becomes the entry it was about', () {
    test('prep words drop out', () {
      expect(suggestIngredientName('Chopped Onions'), 'Onions');
    });

    test('quantity and measure words drop out', () {
      expect(suggestIngredientName('2 Cups Flour'), 'Flour');
      expect(suggestIngredientName('A Handful of Fresh Basil'), 'Fresh Basil');
    });

    test('an amount fused to its unit drops out', () {
      expect(suggestIngredientName('400g Tomatoes'), 'Tomatoes');
    });

    test('sizes and prep adverbs drop out', () {
      expect(suggestIngredientName('2 Large Finely Diced Carrots'), 'Carrots');
    });

    test('the typed order is kept — no noun-first reordering', () {
      expect(suggestIngredientName('1 Tsp Ground Cinnamon'), 'Ground Cinnamon');
    });
  });

  group('a plural is a name, not a line — the vocabulary keeps them', () {
    test('a bare plural is left alone', () {
      expect(suggestIngredientName('Onions'), isNull);
      expect(suggestIngredientName('Bay Leaves'), isNull);
      expect(suggestIngredientName('Red Pepper Flakes'), isNull);
      expect(suggestIngredientName('Hummus'), isNull);
    });

    test('a trailing comma rides along and the tidy removes it', () {
      expect(suggestIngredientName('Chopped Tomatoes,'), 'Tomatoes');
    });
  });

  group('nothing to say', () {
    test('a connective between two identity words is kept', () {
      expect(suggestIngredientName('Cream of Tartar'), isNull);
      expect(suggestIngredientName('Salt and Pepper'), isNull);
      // …but one leading the run is dropped with the measure it belonged to.
      expect(suggestIngredientName('2 Cups of Flour'), 'Flour');
    });

    test('a name that is already the entry', () {
      expect(suggestIngredientName('Fresh Ginger'), isNull);
      expect(suggestIngredientName('Onion'), isNull);
      expect(suggestIngredientName('Cream of Tartar'), isNull);
    });

    test('a difference of case alone is Tier 1’s business, not this', () {
      expect(suggestIngredientName('fresh ginger'), isNull);
    });

    test('every word was a stop word — never suggest nothing', () {
      expect(suggestIngredientName('2 Cups'), isNull);
      expect(suggestIngredientName('A Large Handful'), isNull);
      expect(suggestIngredientName(''), isNull);
    });
  });

  group('the normalizer’s carve-outs are borrowed, not re-decided', () {
    test('a garlic clove is a measure, a whole clove is a spice', () {
      expect(suggestIngredientName('2 Cloves Garlic'), 'Garlic');
      expect(suggestIngredientName('Ground Cloves'), isNull);
    });

    test('a canned cut word names the product and stays', () {
      expect(suggestIngredientName('Tinned Chopped Tomatoes'), isNull);
      // A "tin" is the measure, not the marker: outside a canned phrase the
      // cut word is prep again, exactly as the key reads it.
      expect(suggestIngredientName('1 Tin Chopped Tomatoes'), 'Tomatoes');
    });

    test('a British surface form is kept as typed', () {
      expect(suggestIngredientName('Tinned Chickpeas'), isNull);
    });

    test('a hyphenated compound survives whole', () {
      expect(
        suggestIngredientName('2 Cups All-Purpose Flour'),
        'All-Purpose Flour',
      );
    });

    test('diacritics are not folded away', () {
      expect(suggestIngredientName('4 Sliced Jalapeños'), 'Jalapeños');
    });
  });
}
