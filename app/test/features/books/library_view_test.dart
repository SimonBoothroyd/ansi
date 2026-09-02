import 'package:ansi/core/theme/ansi_theme.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/books/domain/book.dart';
import 'package:ansi/features/books/presentation/library_view.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart' show Override;

import '../../helpers/fake_book_repository.dart';

class _FakeBookRepo extends FakeBookRepository {
  const _FakeBookRepo(super.books);
}

const _library = [
  Book(
    id: 'b1',
    name: 'Our Cookbook',
    sections: [
      BookSection(
        id: 's1',
        name: 'Weeknight',
        recipes: [
          RecipeSummary(id: 'r1', title: 'Chicken Curry', servingsBase: 4),
        ],
      ),
    ],
    unsectioned: [RecipeSummary(id: 'r2', title: 'Toast', servingsBase: 1)],
  ),
];

Widget _host(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    home: FTheme(data: ansiThemeData(), child: const LibraryView()),
  ),
);

List<Override> _repo(List<Book> books) => [
  bookRepositoryProvider.overrideWithValue(_FakeBookRepo(books)),
];

/// The library inside a real router, so a menu item can push and the pushed
/// route can be popped again.
Widget _routedHost(List<Override> overrides, void Function(GoRouter) expose) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LibraryView()),
      GoRoute(
        path: '/import',
        builder: (_, _) => const FScaffold(child: Text('import screen')),
      ),
    ],
  );
  addTearDown(router.dispose);
  expose(router);
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => FTheme(data: ansiThemeData(), child: child!),
    ),
  );
}

void main() {
  testWidgets('LibraryView renders the book, its sections and recipes', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Our Cookbook'), findsOneWidget);
    expect(find.text('2 recipes'), findsOneWidget);
    expect(find.text('Weeknight'), findsOneWidget);
    expect(find.text('Chicken Curry'), findsOneWidget);
    // The book-less recipe shows under the synthetic Unsectioned bucket.
    expect(find.text('Unsectioned'), findsOneWidget);
    expect(find.text('Toast'), findsOneWidget);
  });

  testWidgets('LibraryView shows an empty state with no books', (tester) async {
    await tester.pumpWidget(_host(_repo(const [])));
    await tester.pump();

    expect(find.text('No books yet'), findsOneWidget);
  });

  testWidgets('the + menu offers Sign out', (tester) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();

    expect(find.text('New recipe'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('the add-section affordance uses an icon, not a raw ＋ glyph', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_repo(_library)));
    await tester.pump();

    // U+FF0B is missing from the bundled fonts and renders as tofu.
    expect(find.textContaining('＋'), findsNothing);
    expect(find.textContaining('new section'), findsOneWidget);
  });

  testWidgets('the + menu closes behind the page it opens', (tester) async {
    late GoRouter router;
    await tester.pumpWidget(_routedHost(_repo(_library), (r) => router = r));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(FLucideIcons.plus).first);
    await tester.pumpAndSettle();
    expect(find.text('Import a recipe'), findsOneWidget);

    await tester.tap(find.text('Import a recipe'));
    await tester.pumpAndSettle();
    expect(find.text('import screen'), findsOneWidget);

    // Backing out of the pushed page must not reveal a menu left hanging open.
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Import a recipe'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });
}
