import 'package:ansi/core/text/name_clean.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('whitespace and trailing punctuation — every kind', () {
    for (final kind in NameKind.values) {
      // Cased inputs, so this group is about whitespace and stops alone —
      // what each kind does to case is asserted per kind below.
      test('$kind trims, collapses runs and drops one trailing stop', () {
        expect(cleanName('  Spaced  ', kind), 'Spaced');
        expect(cleanName('A\t\tB\n C', kind), 'A B C');
        expect(cleanName('Trailing Stop.', kind), 'Trailing Stop');
        expect(cleanName('Trailing Comma,', kind), 'Trailing Comma');
        expect(cleanName('', kind), '');
        expect(cleanName('   ', kind), '');
      });

      test('$kind keeps a deliberate run of stops', () {
        expect(cleanName('And So On...', kind), 'And So On...');
        expect(cleanName('One, Two,,', kind), 'One, Two,,');
      });

      test('$kind is idempotent', () {
        for (final raw in [
          '  2  CUPS of  flour.. ',
          'jalapeño, sliced,',
          'BBQ sauce',
          'stir-fry SAUCE ',
          '(optional) garnish.',
          'x',
          '.',
          ',',
        ]) {
          final once = cleanName(raw, kind);
          expect(cleanName(once, kind), once, reason: '$raw as $kind');
        }
      });
    }
  });

  group('NameKind.ingredient — Title Case', () {
    test('capitalises every word', () {
      expect(cleanName('red onion', NameKind.ingredient), 'Red Onion');
    });

    test('leaves the small words alone after the first', () {
      expect(
        cleanName('cream of tartar', NameKind.ingredient),
        'Cream of Tartar',
      );
      expect(
        cleanName('salt and pepper for the pot', NameKind.ingredient),
        'Salt and Pepper for the Pot',
      );
    });

    test('a comma qualifier is left as typed — only the head is a label', () {
      expect(
        cleanName('chicken thigh, boneless', NameKind.ingredient),
        'Chicken Thigh, boneless',
      );
      expect(cleanName('Mango, ripe', NameKind.ingredient), 'Mango, ripe');
      expect(
        cleanName('coconut milk, Canned', NameKind.ingredient),
        'Coconut Milk, Canned',
      );
    });

    test('a small word FIRST is still capitalised', () {
      expect(cleanName('of the earth', NameKind.ingredient), 'Of the Earth');
      expect(cleanName('a2 milk', NameKind.ingredient), 'A2 Milk');
    });

    test('a small word the user capitalised is left capitalised', () {
      expect(
        cleanName('Cream Of Tartar', NameKind.ingredient),
        'Cream Of Tartar',
      );
    });

    test('never lowercases a letter the user typed', () {
      expect(cleanName('BBQ sauce', NameKind.ingredient), 'BBQ Sauce');
      expect(cleanName('pH buffer', NameKind.ingredient), 'PH Buffer');
      expect(
        cleanName('McIntosh apple', NameKind.ingredient),
        'McIntosh Apple',
      );
    });

    test('each hyphenated part gets the rule', () {
      expect(
        cleanName('stir-fry sauce', NameKind.ingredient),
        'Stir-Fry Sauce',
      );
      expect(
        cleanName('all-purpose flour', NameKind.ingredient),
        'All-Purpose Flour',
      );
    });

    test('leading punctuation is stepped over to find the letter', () {
      expect(
        cleanName('(optional) garnish', NameKind.ingredient),
        '(Optional) Garnish',
      );
      expect(
        cleanName('“quoted” thing', NameKind.ingredient),
        '“Quoted” Thing',
      );
    });

    test('diacritics survive, and lead a word when they must', () {
      expect(
        cleanName('jalapeño pepper', NameKind.ingredient),
        'Jalapeño Pepper',
      );
      expect(cleanName('ñoquis', NameKind.ingredient), 'Ñoquis');
      expect(cleanName('crème fraîche', NameKind.ingredient), 'Crème Fraîche');
    });

    test('a word with no letter at all is left as typed', () {
      expect(cleanName('vitamin 12', NameKind.ingredient), 'Vitamin 12');
      expect(cleanName('米 flour', NameKind.ingredient), '米 Flour');
    });
  });

  group('NameKind.recipe, book and section — the first letter only', () {
    for (final kind in [NameKind.recipe, NameKind.book, NameKind.section]) {
      test('$kind caps the first letter and nothing else', () {
        expect(cleanName('wild garlic pesto', kind), 'Wild garlic pesto');
        expect(cleanName('  wild   garlic pesto ', kind), 'Wild garlic pesto');
        expect(cleanName('desserts', kind), 'Desserts');
        expect(cleanName('éclairs and buns', kind), 'Éclairs and buns');
        expect(cleanName('“midweek” things', kind), '“Midweek” things');
        expect(cleanName('BBQ nights', kind), 'BBQ nights');
      });
    }
  });

  group('NameKind.alias — no recasing at all', () {
    test('the vocabulary stores aliases lowercase, so case is left alone', () {
      expect(cleanName('  spring   onion ', NameKind.alias), 'spring onion');
      expect(cleanName('scallion.', NameKind.alias), 'scallion');
      expect(cleanName('BBQ sauce', NameKind.alias), 'BBQ sauce');
    });
  });
}
