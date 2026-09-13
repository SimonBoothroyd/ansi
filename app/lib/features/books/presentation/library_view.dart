/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
///
/// **Two bodies over one screen.** On a phone and a portrait tablet the books
/// are cards that fold open onto their sections, which is the only honest shape
/// for one column. At [AnsiLayout.expanded] they are a shelf of fixed-height
/// tiles instead: a name, its count line and the first titles on it, opening
/// the book's own page ([BookPageView]) where the sections get room. The fold
/// is not read there — a tile is already the folded book, and a page is already
/// the open one. Everything else on the screen is the same object in both: the
/// search field, the one ranked column of results, the `＋ new book` door and
/// the Ingredients shelf.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/presentation/account_view.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/presentation/ingredient_list_view.dart'
    show kIngredientsRoute;
import '../../recipes/domain/recipe.dart';
import '../data/book_providers.dart';
import '../domain/book.dart';
import '../domain/library_search.dart';
import 'book_page_view.dart';
import 'book_rows.dart';
import 'book_view_models.dart';
import 'text_prompt.dart';

class LibraryView extends HookConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // The field owns its controller (a hook, so it survives every rebuild) and
    // the body branches on WHAT THE FIELD SAYS, never on a query stored
    // elsewhere that could outlive the text that produced it, and the
    // ingredients manager is the working example.
    final field = useTextEditingController();
    final typed = useValueListenable(field).text;
    final searching = typed.trim().isNotEmpty;
    // The one band this screen reads: a shelf of tiles is a different honest
    // answer, not a wider version of the card list, and it arrives with its own
    // board frame. Everything below the band is written for one width, as ever.
    final shelf = AnsiLayout.of(context) == AnsiLayout.expanded;

    return FScaffold(
      // A tab root sits INSIDE the shell's scaffold, which already shrinks
      // the branch area for the keyboard; a second scaffold subtracting the
      // same inset squeezes the content twice (Android showed a list a few
      // lines tall after the sign-in keyboard).
      resizeToAvoidBottomInset: false,
      childPad: false,
      // E1: no screen name — the lit tab says where you are, the rule Week,
      // Cook and Shop already ship. The field D2 pinned under the header takes
      // the slot instead, and the one control left is a LINK, not a menu: a
      // control that navigates has nowhere to put a sixth item, which is the
      // whole difference between this and the `⋯` it replaces.
      header: FHeader.nested(
        title: AnsiSearchField(hint: 'Search recipes', controller: field),
        suffixes: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.users),
            onPress: () => context.pushOnce(kAccountRoute),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: library.when(
              loading: () => const Center(child: FCircularProgress()),
              error: (e, st) => AnsiErrorState(
                what: 'the library',
                error: e,
                stackTrace: st,
                onRetry: () => ref.invalidate(libraryProvider),
              ),
              // While a query is live the tree is gone, so the fold state is
              // ignored: there is nothing to fold. Clearing the field restores
              // it exactly as it was, folds included.
              data: (books) => switch (books) {
                _ when searching => _SearchResults(books: books, query: typed),
                [] => const _EmptyState(),
                _ when shelf => _Shelf(books: books),
                _ => ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 28),
                  children: [
                    for (final b in books) _BookCard(book: b, books: books),
                    // E7: the dashed row the v2 board drew and the build
                    // missed. It closes the books.
                    const _NewBookDoor(),
                    // E5: and then a different kind of shelf.
                    const _IngredientsShelf(),
                  ],
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A live query replaces the tree with flat rows that say where each recipe
/// lives (D2) — and, when nothing matches, with two doors (D7·5).
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.books, required this.query});

  final List<Book> books;
  final String query;

  @override
  Widget build(BuildContext context) {
    final hits = searchLibrary(books, query);
    if (hits.isEmpty) return _NoHits(query: query.trim());
    // Guesses are labelled, never mixed in (search & matching v1, D2): the
    // list is either all spellings or all guesses.
    final guessed = librarySearchIsGuess(books, query);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            guessed
                ? 'DID YOU MEAN'
                : '${hits.length} ${plural(hits.length, 'recipe')}',
            style: ansiLabel(),
          ),
        ),
        for (final hit in hits)
          LibraryRecipeRow(recipe: hit.recipe, filing: hit.filing),
      ],
    );
  }
}

/// Nothing matched — and the most common reason a recipe search misses is that
/// you haven't written it down yet (D7·5).
///
/// The query is echoed AS TYPED: when even the typo tier is silent there is
/// nothing honest to suggest. A dead end with two doors is not a dead end.
class _NoHits extends StatelessWidget {
  const _NoHits({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 28),
      children: [
        const Icon(FLucideIcons.search, size: 32, color: AnsiColors.muted),
        const SizedBox(height: 14),
        Text(
          'Nothing matches “$query”',
          textAlign: TextAlign.center,
          style: ansiSerif(size: 20),
        ),
        const SizedBox(height: 18),
        DashedAction(
          icon: FLucideIcons.plus,
          label: 'new recipe called “$query”',
          // The typed query becomes the new recipe's title — the ingredient
          // picker's "can't find it? add a new ingredient" move, which mints
          // from the query rather than dropping you on an empty form.
          onTap: () => context.pushOnce(
            Uri(
              path: '/recipes/new',
              queryParameters: {'title': query},
            ).toString(),
          ),
        ),
        const SizedBox(height: 8),
        DashedAction(
          icon: FLucideIcons.download,
          label: 'import a recipe instead',
          onTap: () => context.pushOnce('/import'),
        ),
      ],
    );
  }
}

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.book, required this.books});

  final Book book;

  /// The whole library — what "Move up / Move down" reorders against, and what
  /// the last-book delete refusal counts.
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folded = ref.watch(foldedBooksProvider).asData?.value ?? const {};
    final expanded = !folded.contains(book.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AnsiColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Herb header: name + the honest count line on the left, the
                  // fold chevron on the right.
                  Container(
                    color: AnsiColors.herb,
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.name,
                                style: ansiSerif(
                                  size: 19,
                                  color: AnsiColors.surface,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                bookCountLine(book),
                                style: ansiMono(
                                  size: 10,
                                  color: AnsiColors.surface,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FButton.icon(
                          variant: FButtonVariant.ghost,
                          onPress: () => unawaited(
                            ref
                                .read(foldedBooksProvider.notifier)
                                .toggle(book.id),
                          ),
                          child: Icon(
                            expanded
                                ? FLucideIcons.chevronDown
                                : FLucideIcons.chevronRight,
                            size: 18,
                            color: AnsiColors.surface,
                          ),
                        ),
                        BookMenu(book: book, books: books),
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    for (final section in book.sections)
                      BookSectionBlock(book: book, section: section),
                    if (book.unsectioned.isNotEmpty)
                      BookSectionBlock(
                        book: book,
                        unsectioned: book.unsectioned,
                      ),
                    if (_isEmpty) EmptyShelf(book: book),
                    // No dashed add-a-section row here: `New section` is in
                    // the book `⋯` immediately above. An expanded card is
                    // books, sections and recipes — no furniture.
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _isEmpty => book.sections.isEmpty && book.unsectioned.isEmpty;
}

/// The door that makes a book, under the last of them — the same row on the
/// card list and under the shelf's grid, because it closes the books in
/// either body.
class _NewBookDoor extends ConsumerWidget {
  const _NewBookDoor();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: DashedAction(
      icon: FLucideIcons.bookPlus,
      label: 'new book',
      onTap: () => unawaited(promptForNewBook(context, ref)),
    ),
  );
}

/// Every tile is this tall, whatever it holds — a band over a body, and neither
/// one negotiates.
const double kBookTileHeight = 180;

/// The widest a tile is drawn. The grid asks for as many columns as fit at this
/// extent, so the count follows the window rather than being typed in: four
/// across a 1440 window beside the chrome, three on an iPad in landscape, two
/// when the pane narrows to the measure.
const double kBookTileMaxWidth = 320;

/// The books as a shelf at [AnsiLayout.expanded]: a grid of fixed-height tiles,
/// with the doors that are not books running full width beneath it.
///
/// The grid is the only thing the width changes. The `＋ new book` row and the
/// Ingredients shelf are the phone's own, in the phone's order — a tile grid
/// is a better shelf than a column of cards; it is not a licence to redraw
/// what was never a shelf.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: kBookTileMaxWidth,
            mainAxisExtent: kBookTileHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _BookTile(book: books[i]),
            childCount: books.length,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: _NewBookDoor()),
      const SliverToBoxAdapter(child: _IngredientsShelf()),
      const SliverToBoxAdapter(child: SizedBox(height: 28)),
    ],
  );
}

/// One book on the shelf: the name on its herb band with the count line the
/// card's header carries, then **titles only**.
///
/// The Library's recipe row is two lines and carries its own `⋯`; three of
/// those do not fit the body a fixed tile leaves, and a row that drops its
/// second line is a row the app does not have. So a tile lists what is on the
/// shelf and the book's page draws the rows — which is also why the tile has
/// no menu: every control the card offered is one tap away, on the page it
/// opens.
///
/// The ★ comes along because it only ever reported. A title too long for the
/// tile is clipped here; where it is a row, it wraps.
class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});

  final Book book;

  /// How many titles a tile shows before it counts the rest.
  static const _peekCount = 3;

  /// The book's recipes in the order its page lists them, so the first titles
  /// on the tile are the first titles on the page.
  List<RecipeSummary> get _recipes => [
    for (final section in book.sections) ...section.recipes,
    ...book.unsectioned,
  ];

  @override
  Widget build(BuildContext context) {
    final recipes = _recipes;
    final peek = recipes.take(_peekCount).toList();
    final rest = recipes.length - peek.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushOnce(bookRoute(book.id)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AnsiColors.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AnsiColors.herb,
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ansiSerif(
                        size: 16,
                        color: AnsiColors.surface,
                        weight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      bookCountLine(book),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ansiMono(
                        size: 10,
                        color: AnsiColors.surface,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                  child: peek.isEmpty
                      // An empty shelf says so on its band already, so the
                      // body is the door, not a second sentence about nothing.
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: DashedAction(
                            icon: FLucideIcons.plus,
                            label: 'new recipe',
                            onTap: () => context.pushOnce(
                              Uri(
                                path: '/recipes/new',
                                queryParameters: {'book': book.id},
                              ).toString(),
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final r in peek) _TileTitle(recipe: r),
                            if (rest > 0) ...[
                              const SizedBox(height: 2),
                              Text(
                                '+ $rest more',
                                style: ansiMono(
                                  size: 10,
                                  color: AnsiColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One title on a tile: clipped at one line, with the ★ it reports.
class _TileTitle extends StatelessWidget {
  const _TileTitle({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ansiSerif(size: 14, weight: FontWeight.w400),
          ),
        ),
        if (recipe.favorite) ...[
          const SizedBox(width: 6),
          const Icon(FLucideIcons.star, size: 11, color: AnsiColors.aging),
        ],
      ],
    ),
  );
}

/// The vocabulary as a shelf of its own — **a rule and a row, not a card**.
///
/// It is not reference data filed under a menu. `shopping_list_entry` has
/// carried `ingredient_id` beside `free_text` since 0006, under a check that
/// exactly one is set — a top-up IS an ingredient put on a list with no recipe
/// anywhere near it — so the vocabulary is already something the household
/// plans with. A count line says what is on the shelf outright, which is what
/// a badge or a dot could only gesture at.
///
/// **It borrows nothing from the book card.** A book is a container that folds;
/// the vocabulary is a place you go — so there is no card here, and nothing
/// invites the fold, the `⋯` or the reorder a book header carries. A hairline,
/// the app's uppercase micro-label in herb ink, the count line, and a `›` (a
/// fold would put 300 rows inside a card). Its position, after the books, is
/// part of the claim: a different kind of shelf, drawn a different way.
class _IngredientsShelf extends ConsumerWidget {
  const _IngredientsShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(vocabularyCountProvider).asData?.value;
    final stubs = ref.watch(stubCountProvider).asData?.value ?? 0;
    // Never "0 ingredients": the stub badge's rule — a zero that renders looks
    // like a bug — and the count is absent, not zero, until it has loaded.
    final line = [
      if (total != null && total > 0) '$total ${plural(total, 'ingredient')}',
      if (stubs > 0) '$stubs ${plural(stubs, 'stub')}',
    ].join(' · ');

    return Padding(
      // The rule runs edge to edge, while the books are inset: a hairline that
      // stopped where a card stops would be drawing a card.
      padding: const EdgeInsets.only(top: 22),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.pushOnce(kIngredientsRoute),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AnsiColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
            child: Row(
              children: [
                // The vocabulary's own glyph. Not the nav's `library` icon:
                // the shelf is a door out of the Library, not a second badge
                // for it.
                const Icon(
                  FLucideIcons.carrot,
                  size: 15,
                  color: AnsiColors.herb,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INGREDIENTS',
                        style: ansiLabel(color: AnsiColors.herbDeep),
                      ),
                      if (line.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          line,
                          style: ansiMono(size: 10, color: AnsiColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  FLucideIcons.chevronRight,
                  size: 16,
                  color: AnsiColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// No books at all (D7·1) — nearly unreachable, since `ensureDefaultBook`
/// runs at bootstrap, but it stays honest and points at something ON SCREEN.
/// The old copy said "Add one with the ＋ above", which after D1 is no longer
/// where books are made.
class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(FLucideIcons.library, size: 44, color: AnsiColors.herb),
            const SizedBox(height: 14),
            Text('No books yet', style: ansiSerif(size: 22)),
            const SizedBox(height: 6),
            Text(
              'A book is a shelf — name it whatever you call it out loud.',
              textAlign: TextAlign.center,
              style: ansiMono(size: 12, color: AnsiColors.muted),
            ),
            const SizedBox(height: 18),
            DashedAction(
              icon: FLucideIcons.bookPlus,
              label: 'new book',
              onTap: () => unawaited(promptForNewBook(context, ref)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Names and creates a book, from the `⋯` menu and the no-books state alike.
Future<void> promptForNewBook(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final name = await promptForText(
    context,
    title: 'New book',
    hint: 'e.g. Our Cookbook',
    confirm: 'Create',
    clean: NameKind.title,
  );
  if (name == null || name.trim().isEmpty) return;
  await container.write(
    host,
    'create that book',
    () => container.read(bookRepositoryProvider).createBook(name),
  );
}
