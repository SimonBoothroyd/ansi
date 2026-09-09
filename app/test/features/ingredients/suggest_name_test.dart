import 'package:ansi/features/ingredients/domain/suggest_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a recipe line becomes the entry it was about', () {
    test('prep words drop out, and the noun singularizes', () {
      expect(suggestIngredientName('Chopped Onions'), 'Onion');
    });

    test('quantity and measure words drop out', () {
      expect(suggestIngredientName('2 Cups Flour'), 'Flour');
      expect(suggestIngredientName('A Handful of Fresh Basil'), 'Fresh Basil');
    });

    test('an amount fused to its unit drops out', () {
      expect(suggestIngredientName('400g Tomatoes'), 'Tomato');
    });

    test('sizes and prep adverbs drop out', () {
      expect(suggestIngredientName('2 Large Finely Diced Carrots'), 'Carrot');
    });

    test('the typed order is kept — no noun-first reordering', () {
      expect(suggestIngredientName('1 Tsp Ground Cinnamon'), 'Ground Cinnamon');
    });
  });

  group('a plural becomes the singular the vocabulary keys on', () {
    test('the last word only', () {
      expect(suggestIngredientName('Onions'), 'Onion');
      expect(suggestIngredientName('Tomatoes'), 'Tomato');
      expect(suggestIngredientName('Chickpeas'), 'Chickpea');
      expect(suggestIngredientName('Bay Leaves'), 'Bay Leaf');
    });

    test('a trailing comma rides along and the tidy removes it', () {
      expect(suggestIngredientName('Chopped Tomatoes,'), 'Tomato');
    });

    test('the singular keeps the case the person typed', () {
      expect(suggestIngredientName('BBQs'), 'BBQ');
    });
  });

  group('nothing to say', () {
    test('a word the singularizer leaves alone', () {
      expect(suggestIngredientName('Hummus'), isNull);
      expect(suggestIngredientName('Couscous'), isNull);
      expect(suggestIngredientName('Molasses'), isNull);
    });

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
      expect(suggestIngredientName('Ground Cloves'), 'Ground Clove');
    });

    test('a canned cut word names the product and stays', () {
      expect(
        suggestIngredientName('Tinned Chopped Tomatoes'),
        'Tinned Chopped Tomato',
      );
      // A "tin" is the measure, not the marker: outside a canned phrase the
      // cut word is prep again, exactly as the key reads it.
      expect(suggestIngredientName('1 Tin Chopped Tomatoes'), 'Tomato');
    });

    test('a British surface form is kept as typed', () {
      expect(suggestIngredientName('Tinned Chickpeas'), 'Tinned Chickpea');
    });

    test('a hyphenated compound survives whole', () {
      expect(
        suggestIngredientName('2 Cups All-Purpose Flour'),
        'All-Purpose Flour',
      );
    });

    test('diacritics are not folded away', () {
      expect(suggestIngredientName('4 Sliced Jalapeños'), 'Jalapeño');
    });
  });
}
