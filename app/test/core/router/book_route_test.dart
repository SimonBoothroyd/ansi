/// `/books/:id` — the route the shelf's tiles open and a link can be pasted at.
///
/// Two halves, because neither alone is the claim. The structural half reads
/// the router's own source: the route is declared through `_page` (so it
/// is pushed over the shell and sits in the measure), it takes its id from the
/// path, and it is the one page that opts out of the measure at `expanded`. The
/// widget half resolves that pattern for real and lands on the book it names.
library;

import 'dart:io';

import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/presentation/book_page_view.dart';
import 'package:ansi/features/recipes/data/recipe_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/editor_harness.dart';
import '../../helpers/fake_book_repository.dart';
import '../../helpers/pump_app.dart';

const _books = [
  Book(id: 'b1', name: 'Our Cookbook'),
  Book(id: 'b2', name: 'Baking'),
];

void main() {
  test('structural: the book route is a pushed page that reads its id from the '
      'path and uses the width', () {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final start = source.indexOf("path: '/books/:id',");
    expect(start, isNot(-1), reason: 'the book route should exist');
    final route = source.substring(start, source.indexOf('),', start));

    expect(
      source.lastIndexOf('_page(', start),
      greaterThan(source.indexOf('StatefulShellRoute')),
      reason:
          'it builds through _page, below the shell, like every pushed page',
    );
    expect(route, contains("state.pathParameters['id']"));
    expect(
      route,
      contains('usesWidth: true'),
      reason: 'two panes do not fit the measure at expanded',
    );
  });

  testWidgets('a link straight to a book lands on that book', (tester) async {
    await tester.pumpWidget(
      routedHost(
        initial: '/books/b2',
        overrides: [
          bookRepositoryProvider.overrideWithValue(
            const FakeBookRepository(_books),
          ),
          recipeRepositoryProvider.overrideWithValue(FakeRecipeRepo(null)),
        ],
        routes: {
          '/': (_, _) => const BookPageView(bookId: 'unused'),
          '/books/:id': (_, state) =>
              BookPageView(bookId: state.pathParameters['id']!),
        },
      ),
    );
    await tester.pump();

    expect(find.text('Baking'), findsOneWidget);
    expect(find.text('Our Cookbook'), findsNothing);
  });
}
