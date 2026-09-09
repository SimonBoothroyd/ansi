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

  group('NameKind.title — Title Case', () {
    test('capitalises every word', () {
      expect(cleanName('red onion', NameKind.title), 'Red Onion');
    });

    test('leaves the small words alone after the first', () {
      expect(cleanName('cream of tartar', NameKind.title), 'Cream of Tartar');
      expect(
        cleanName('salt and pepper for the pot', NameKind.title),
        'Salt and Pepper for the Pot',
      );
    });

    test('a comma qualifier is left as typed — only the head is a label', () {
      expect(
        cleanName('chicken thigh, boneless', NameKind.title),
        'Chicken Thigh, boneless',
      );
      expect(cleanName('Mango, ripe', NameKind.title), 'Mango, ripe');
      expect(
        cleanName('coconut milk, Canned', NameKind.title),
        'Coconut Milk, Canned',
      );
    });

    test('a small word FIRST is still capitalised', () {
      expect(cleanName('of the earth', NameKind.title), 'Of the Earth');
      expect(cleanName('a2 milk', NameKind.title), 'A2 Milk');
    });

    test('a small word the user capitalised is left capitalised', () {
      expect(cleanName('Cream Of Tartar', NameKind.title), 'Cream Of Tartar');
    });

    test('never lowercases a letter the user typed', () {
      expect(cleanName('BBQ sauce', NameKind.title), 'BBQ Sauce');
      expect(cleanName('pH buffer', NameKind.title), 'PH Buffer');
      expect(cleanName('McIntosh apple', NameKind.title), 'McIntosh Apple');
    });

    test('each hyphenated part gets the rule', () {
      expect(cleanName('stir-fry sauce', NameKind.title), 'Stir-Fry Sauce');
      expect(
        cleanName('all-purpose flour', NameKind.title),
        'All-Purpose Flour',
      );
    });

    test('leading punctuation is stepped over to find the letter', () {
      expect(
        cleanName('(optional) garnish', NameKind.title),
        '(Optional) Garnish',
      );
      expect(cleanName('“quoted” thing', NameKind.title), '“Quoted” Thing');
    });

    test('diacritics survive, and lead a word when they must', () {
      expect(cleanName('jalapeño pepper', NameKind.title), 'Jalapeño Pepper');
      expect(cleanName('ñoquis', NameKind.title), 'Ñoquis');
      expect(cleanName('crème fraîche', NameKind.title), 'Crème Fraîche');
    });

    test('a word with no letter at all is left as typed', () {
      expect(cleanName('vitamin 12', NameKind.title), 'Vitamin 12');
      expect(cleanName('米 flour', NameKind.title), '米 Flour');
    });
  });

  group('a title, a book and a section get the same rule', () {
    test('a recipe title is Title Cased like any other name', () {
      expect(
        cleanName('wild garlic pesto', NameKind.title),
        'Wild Garlic Pesto',
      );
      expect(
        cleanName('  wild   garlic pesto ', NameKind.title),
        'Wild Garlic Pesto',
      );
    });

    test('a book or section name is a label on a shelf', () {
      expect(cleanName('desserts', NameKind.title), 'Desserts');
      expect(cleanName('to serve', NameKind.title), 'To Serve');
      expect(cleanName('éclairs and buns', NameKind.title), 'Éclairs and Buns');
      expect(cleanName('“midweek” things', NameKind.title), '“Midweek” Things');
      expect(cleanName('BBQ nights', NameKind.title), 'BBQ Nights');
    });
  });

  group('NameKind.alias — no recasing at all', () {
    test('the vocabulary stores aliases lowercase, so case is left alone', () {
      expect(cleanName('  spring   onion ', NameKind.alias), 'spring onion');
      expect(cleanName('scallion.', NameKind.alias), 'scallion');
      expect(cleanName('BBQ sauce', NameKind.alias), 'BBQ sauce');
    });
  });
}
