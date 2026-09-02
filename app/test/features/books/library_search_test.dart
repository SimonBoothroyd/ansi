/// `searchLibrary` over a hand-built aggregate (Library v2 / D2) — pure Dart,
/// no widgets: the whole point of putting the fold in `domain/`.
library;

import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/domain/library_search.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

const _curry = RecipeSummary(
  id: 'r1',
  title: 'Weeknight Chicken Curry',
  servingsBase: 4,
);
const _stock = RecipeSummary(id: 'r2', title: 'Chicken Stock', servingsBase: 8);
const _cake = RecipeSummary(
  id: 'r3',
  title: 'Toasted Almond Cake',
  servingsBase: 8,
);
const _ragu = RecipeSummary(id: 'r4', title: 'House Ragù', servingsBase: 6);

const _library = [
  Book(
    id: 'b1',
    name: 'Our Cookbook',
    sections: [
      BookSection(id: 's1', name: 'Weeknight', recipes: [_curry]),
    ],
    unsectioned: [_ragu],
  ),
  Book(
    id: 'b2',
    name: 'Baking',
    sections: [
      BookSection(id: 's2', name: 'Sweet', recipes: [_cake]),
    ],
    unsectioned: [_stock],
  ),
];

List<String> _titles(String query) =>
    searchLibrary(_library, query).map((h) => h.recipe.title).toList();

void main() {
  test('an empty query returns nothing — the tree renders instead', () {
    expect(searchLibrary(_library, ''), isEmpty);
    expect(searchLibrary(_library, '   '), isEmpty);
  });

  test('matching is word-prefix, never mid-word', () {
    expect(_titles('chicken'), contains('Chicken Stock'));
    expect(_titles('hick'), isEmpty);
  });

  test('tokens are order-independent', () {
    expect(_titles('curry chicken'), ['Weeknight Chicken Curry']);
  });

  test('a plural query reaches a singular title through the shared rank', () {
    // Search & matching v1: recipe titles go through `searchRank`, whose
    // tier 0/1 tries every token raw OR singular — the "almonds" fix the
    // ingredient picker shipped in 8.6, now one rule for titles too.
    expect(_titles('almonds'), ['Toasted Almond Cake']);
    expect(_titles('almond'), ['Toasted Almond Cake']);
  });

  test('an exact first-word hit leads, then the tree order', () {
    // "Chicken Stock" starts with the query; "Weeknight Chicken Curry" merely
    // contains it — and it would otherwise come first, being in book 1.
    // Everything after keeps the tree's order: book, then section.
    expect(_titles('c'), [
      'Chicken Stock',
      'Weeknight Chicken Curry',
      'Toasted Almond Cake',
    ]);
  });

  test('every row carries its filing, sectioned or not', () {
    final hits = searchLibrary(_library, 'chicken');
    expect(
      {for (final h in hits) h.recipe.title: h.filing},
      {
        'Chicken Stock': (book: 'Baking', section: null),
        'Weeknight Chicken Curry': (book: 'Our Cookbook', section: 'Weeknight'),
      },
    );
  });

  test('filingByRecipe covers both buckets of every book', () {
    expect(filingByRecipe(_library), {
      'r1': (book: 'Our Cookbook', section: 'Weeknight'),
      'r4': (book: 'Our Cookbook', section: null),
      'r3': (book: 'Baking', section: 'Sweet'),
      'r2': (book: 'Baking', section: null),
    });
  });
}
