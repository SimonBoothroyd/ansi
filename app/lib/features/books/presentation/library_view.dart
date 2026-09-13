/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
///
/// **Two bodies over one screen.** On a phone and a portrait tablet the books
/// are cards that fold open onto their sections, which is the only honest shape
/// for one column. At [AnsiLayout.expanded] they are a **ledger** instead: one
/// column of books at [kLedgerWidth], centred, with a [kAzIndexWidth] A–Z index
/// down the right margin. A book is a heading row — its name, a dotted leader,
/// its count line in a column of numbers, its `⋯` — over its first recipes as
/// indented lines and one remainder row saying what the rest of it is. No tile,
/// no grid, no dark band: the owner refused those on sight ("corporate"), and
/// what replaced them states every fact once and sets it in a column on bare
/// paper.
///
/// **What the width does not change.** The fold is the phone's own, per book
/// and per device, read from the same store; the search field, the one ranked
/// column of results, the `＋ new book` door and the Ingredients shelf are the
/// same objects; and every row, menu and section widget is shared with the card
/// and with the book page ([BookPageView]), which a heading row still opens.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/search/search_query.dart' show foldDiacritics;
import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/dotted_leader.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/presentation/account_view.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/presentation/ingredient_list_view.dart'
    show kIngredientsRoute;
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
    // The one band this screen reads: a ledger is a different honest answer,
    // not a wider version of the card list, and it arrives with its own board
    // frame. Everything below the band is written for one width, as ever.
    final ledger = AnsiLayout.of(context) == AnsiLayout.expanded;

    final body = library.when(
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
        // A ranked column is a column at every width: the results keep the
        // measure and the ledger's own left edge, and the A–Z margin goes with
        // the books it indexes.
        _ when searching && ledger => Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ansiMeasureWidth(context)),
            child: _SearchResults(books: books, query: typed),
          ),
        ),
        _ when searching => _SearchResults(books: books, query: typed),
        [] => const _EmptyState(),
        _ when ledger => _Ledger(books: books),
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
    );

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
      //
      // The ledger has NO header: a field stretched over a pane is the admin
      // bar the owner refused, so on a desk the field is a 300 px line at the
      // head of the ledger's own column ([_LedgerHead]) and there is nothing
      // else up there to hold. The household door is hidden either way once the
      // chrome is beside the content — Account is the sidebar's footer item,
      // and that is the only door there is.
      header: ledger
          ? null
          : FHeader.nested(
              title: AnsiSearchField(hint: 'Search recipes', controller: field),
              suffixes: [
                if (!AnsiShell.of(context).beside)
                  FHeaderAction(
                    icon: const Icon(FLucideIcons.users),
                    onPress: () => context.pushOnce(kAccountRoute),
                  ),
              ],
            ),
      child: ledger
          ? _LedgerFrame(field: field, child: body)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(child: body)],
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

/// The widest the ledger's one column of books is drawn.
///
/// Measured from the longest line a book heading makes — a name, a leader, and
/// `42 recipes · 3 sections` — rather than chosen to fill the pane: past this
/// the leader is doing nothing but crossing empty paper. Below it the column is
/// fluid, and the index stays in the margin.
const double kLedgerWidth = 900;

/// The A–Z index down the right margin, and the clear paper before it.
const double kAzIndexWidth = 34;
const double kAzIndexGap = 40;

/// The search field at the head of the ledger — a line you type a recipe name
/// into, not a bar across the pane.
const double kLedgerFieldWidth = 300;

/// How far a book's recipe lines are set in from its heading row.
const double kLedgerIndent = 24;

/// How many recipes a book lists before the remainder row counts the rest.
///
/// The same three the phone's tile listed and the book page opens with: enough
/// to recognise a book by what is in it, few enough that ten books are still
/// one screen.
const int kLedgerPeek = 3;

/// The ledger's own frame: the head strip, then whatever the body is, in one
/// centred column no wider than the ledger and its margin together.
///
/// The strip is **outside** the body on purpose. It holds the field, and a
/// field that scrolled away with the books — or vanished when a query emptied
/// the tree under it — would be a field you cannot clear.
class _LedgerFrame extends StatelessWidget {
  const _LedgerFrame({required this.field, required this.child});

  final TextEditingController field;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: ansiPageGutter),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kLedgerWidth + kAzIndexGap + kAzIndexWidth,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            _LedgerHead(field: field),
            const SizedBox(height: 18),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// The head strip: the field as a line, and the quiet door that makes a book.
class _LedgerHead extends StatelessWidget {
  const _LedgerHead({required this.field});

  final TextEditingController field;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: kLedgerFieldWidth,
        child: AnsiSearchField(hint: 'Search recipes', controller: field),
      ),
      const Spacer(),
      const _NewBookLink(),
    ],
  );
}

/// `＋ new book` as a word, not a dashed slab.
///
/// The phone's [DashedAction] closes a column of cards, where a dashed rule is
/// the last thing on the page and reads as an invitation. At the head of a
/// ledger the same slab would be furniture across the top of a page whose whole
/// claim is that it has none — so the door keeps its icon, its mono voice and
/// its herb ink, and loses the box.
class _NewBookLink extends ConsumerWidget {
  const _NewBookLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(promptForNewBook(context, ref)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.bookPlus, size: 13, color: AnsiColors.herb),
          const SizedBox(width: 6),
          Text(
            'new book',
            style: ansiMono(
              size: 10.5,
              color: AnsiColors.herb,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The books as a ledger at [AnsiLayout.expanded]: one column of heading rows
/// and their lines, with the A–Z index in the margin beside it.
///
/// The index is a **jump**, not a sort and not a filter: the books stay in the
/// household's own order — what `Move up` and `Move down` write — and a lit
/// letter scrolls to the first book that starts with it. That is what lets the
/// shape hold at twenty-five books without becoming a grid.
///
/// A [StatefulWidget] for the same reason the book page's panes are: it owns a
/// scroll position, which belongs to the widget that owns the controller and
/// dies with it.
class _Ledger extends StatefulWidget {
  const _Ledger({required this.books});

  final List<Book> books;

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  final _scroll = ScrollController();

  /// One key per book, so the index can scroll to it. Kept across rebuilds — a
  /// fresh key would rebuild the book and lose the row states inside it.
  final _keys = <String, GlobalKey>{};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Scrolls the ledger until [bookId]'s heading row is at the top.
  void _show(String bookId) {
    final target = _keys[bookId]?.currentContext;
    if (target != null) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    // A book far enough down has not been built, so there is no context to
    // scroll to. Jumping to the end builds the tail; the book is then there to
    // land on, one frame later. (The book page's index does the same.)
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final built = _keys[bookId]?.currentContext;
      if (built != null) unawaited(Scrollable.ensureVisible(built));
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    final lit = {for (final book in books) bookInitial(book)};

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ColumnHeads(books: books.length),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 36),
                  children: [
                    for (final book in books)
                      _LedgerBook(
                        key: _keyFor(book.id),
                        book: book,
                        books: books,
                      ),
                    // The vocabulary closes the ledger exactly as it closes the
                    // phone's books, minus the phone's gutters: the ledger's
                    // column IS the gutter here.
                    const _IngredientsShelf(gutter: 0),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: kAzIndexGap),
        SizedBox(
          width: kAzIndexWidth,
          child: _AzIndex(
            lit: lit,
            onLetter: (letter) => _show(
              books.firstWhere((book) => bookInitial(book) == letter).id,
            ),
          ),
        ),
      ],
    );
  }
}

/// What the ledger's two columns hold — which is what makes the right edge a
/// column and not a row of loose numbers.
class _ColumnHeads extends StatelessWidget {
  const _ColumnHeads({required this.books});

  final int books;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AnsiColors.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Text('BOOKS · $books', style: ansiLabel()),
          const Spacer(),
          Text('COUNTS · STATS', style: ansiLabel()),
        ],
      ),
    ),
  );
}

/// One book in the ledger: the heading row, its first lines, the remainder, and
/// a hairline to close it. No box, no fill, no band.
class _LedgerBook extends ConsumerWidget {
  const _LedgerBook({required this.book, required this.books, super.key});

  final Book book;

  /// The whole library — what the book menu's reorder moves against, and what
  /// its delete counts before refusing.
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folded = ref.watch(foldedBooksProvider).asData?.value ?? const {};
    final open = !folded.contains(book.id);
    final all = bookRecipesInPageOrder(book);
    final shown = all.take(open ? kLedgerPeek : 0).toList();

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AnsiColors.line)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 15, 0, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeadingRow(book: book, books: books, open: open),
            if (open) ...[
              for (final filed in shown)
                Padding(
                  padding: const EdgeInsets.only(left: kLedgerIndent),
                  child: LibraryRecipeRow.ledger(
                    recipe: filed.recipe,
                    bookId: book.id,
                    sectionId: filed.sectionId,
                  ),
                ),
              if (all.length > shown.length)
                Padding(
                  padding: const EdgeInsets.only(left: kLedgerIndent, top: 2),
                  child: _RemainderRow(book: book, shown: shown.length),
                ),
              // The first-run doors, in place — the same two the phone's empty
              // card offers, because the app can still open on this.
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: kLedgerIndent, top: 6),
                  child: EmptyShelf(book: book),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A book's heading row: the fold's chevron, the name, a dotted leader into the
/// counts column, and the book's own `⋯`.
///
/// Three targets, each doing one thing: the chevron folds (the phone's own
/// per-device state, so a book shut on this desk is shut here tomorrow), the
/// name opens the book's page, and the `⋯` is [BookMenu] — the same menu the
/// card's herb band and the page's header bar hang.
class _HeadingRow extends ConsumerWidget {
  const _HeadingRow({
    required this.book,
    required this.books,
    required this.open,
  });

  final Book book;
  final List<Book> books;
  final bool open;

  /// The widest a book's name is set before it is clipped — as with a recipe
  /// line, the counts are a fact and the name is a label.
  static const double nameMax = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            unawaited(ref.read(foldedBooksProvider.notifier).toggle(book.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
          child: Icon(
            open ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
            size: 14,
            color: AnsiColors.muted,
          ),
        ),
      ),
      Flexible(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.pushOnce(bookRoute(book.id)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: nameMax),
            child: Text(
              book.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ansiSerif(size: 18, weight: FontWeight.w500),
            ),
          ),
        ),
      ),
      const AnsiDottedLeader(),
      Text(
        bookCountLine(book),
        style: ansiMono(size: 10, color: AnsiColors.muted, letterSpacing: 0.7),
      ),
      BookMenu.inline(book: book, books: books),
    ],
  );
}

/// What the fold still holds — `39 more, in 3 sections` — and the `＋` that
/// files a recipe into this book.
///
/// The row itself is the door to the book's page, where the sections get their
/// names back: in the ledger a section is a **count on this row** and nothing
/// else, because a ledger that listed every section would be the tree, and the
/// tree is the phone's shape.
class _RemainderRow extends StatelessWidget {
  const _RemainderRow({required this.book, required this.shown});

  final Book book;
  final int shown;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => context.pushOnce(bookRoute(book.id)),
    child: Row(
      children: [
        const Icon(FLucideIcons.chevronRight, size: 12, color: AnsiColors.herb),
        const SizedBox(width: 7),
        Text(
          bookRemainderLine(book, shown: shown),
          style: ansiMono(
            size: 10.5,
            color: AnsiColors.herb,
            letterSpacing: 0.3,
          ),
        ),
        const Spacer(),
        // The phone's own "this book, no section" door, which is what a
        // remainder row's ＋ has always meant.
        SectionAddMenu(book: book),
      ],
    ),
  );
}

/// Which letter a book files under in the margin: its first, folded off its
/// accents ("Élan" indexes at **E**, where somebody would look for it), and
/// `#` for a name that starts with anything else.
String bookInitial(Book book) {
  final name = foldDiacritics(book.name.trim()).toUpperCase();
  if (name.isEmpty) return '#';
  final first = name[0];
  return first.codeUnitAt(0) >= 0x41 && first.codeUnitAt(0) <= 0x5A
      ? first
      : '#';
}

/// The margin's letters: the bucket for everything that does not start with a
/// letter, then A–Z.
final List<String> kAzLetters = [
  '#',
  for (var c = 0; c < 26; c++) String.fromCharCode(0x41 + c),
];

/// The A–Z index down the right margin.
///
/// Every letter is drawn, lit or not: an index that hid its gaps would be an
/// index you stop trusting, and the gaps are the point — they say the shelf has
/// nothing under D. Only a lit letter is a door.
class _AzIndex extends StatelessWidget {
  const _AzIndex({required this.lit, required this.onLetter});

  final Set<String> lit;
  final ValueChanged<String> onLetter;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The margin says what it is, once, in the same micro-voice as the
        // ledger's column heads.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'A–Z',
            textAlign: TextAlign.right,
            style: ansiMono(size: 8, color: AnsiColors.muted, letterSpacing: 1),
          ),
        ),
        for (final letter in kAzLetters)
          LibraryIndexLetter(
            letter: letter,
            lit: lit.contains(letter),
            onTap: () => onLetter(letter),
          ),
      ],
    ),
  );
}

/// One letter in the A–Z margin.
///
/// Public so a test can read the index's state the way a person does — which
/// letters are lit — rather than by matching on ink.
class LibraryIndexLetter extends StatelessWidget {
  const LibraryIndexLetter({
    required this.letter,
    required this.lit,
    required this.onTap,
    super.key,
  });

  final String letter;

  /// Whether a book on the shelf starts with this letter.
  final bool lit;

  final VoidCallback onTap;

  /// The row a letter sits in — tall enough to hit, short enough that all
  /// twenty-seven are one margin.
  static const double rowHeight = 20;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: lit ? onTap : null,
    child: SizedBox(
      height: rowHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          letter,
          style: ansiMono(
            size: 10,
            // An unlit letter is drawn in the hairline's own ink: present,
            // and plainly not a door.
            color: lit ? AnsiColors.herbDeep : AnsiColors.line,
            weight: lit ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
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
  const _IngredientsShelf({this.gutter = ansiPageGutter});

  /// The inset either side of the row's contents — the phone's own gutter, and
  /// zero in the ledger, whose column already is the gutter. The rule itself
  /// runs edge to edge in both, which is the part that matters.
  final double gutter;

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
            padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 2),
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
