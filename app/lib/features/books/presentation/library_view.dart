/// The Library, the app's home screen: books, their sections and recipes.
///
/// Two bodies. Below [AnsiLayout.expanded] books are cards that fold open.
/// At expanded they are an open ledger: one centred column ([kLedgerWidth])
/// listing every section and recipe, with an A–Z index in the margin. Fold
/// state, search, rows and menus are shared by both.
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
import '../../../shared/ansi_scroll.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/dotted_leader.dart';
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
import 'book_rows.dart';
import 'book_view_models.dart';
import 'text_prompt.dart';

class LibraryView extends HookConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // The body branches on the field's text, never on a stored query that
    // could outlive it.
    final field = useTextEditingController();
    final typed = useValueListenable(field).text;
    final searching = typed.trim().isNotEmpty;
    // The one band this screen reads.
    final ledger = AnsiLayout.of(context) == AnsiLayout.expanded;

    final body = library.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, st) => AnsiErrorState(
        what: 'the library',
        error: e,
        stackTrace: st,
        onRetry: () => ref.invalidate(libraryProvider),
      ),
      // A live query replaces the tree; clearing it restores the folds.
      data: (books) => switch (books) {
        // Results keep the measure and the ledger's left edge.
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
            const _NewBookDoor(),
            const _IngredientsShelf(),
          ],
        ),
      },
    );

    return FScaffold(
      // A tab root sits inside the shell's scaffold, which already shrinks
      // for the keyboard; a second inset would squeeze the content twice.
      resizeToAvoidBottomInset: false,
      childPad: false,
      // No screen name: the lit tab says where you are. The ledger has no
      // header; its field heads the ledger column ([_LedgerHead]). The
      // household door hides once the sidebar carries Account.
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

/// Flat rows that say where each recipe lives, or [_NoHits].
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.books, required this.query});

  final List<Book> books;
  final String query;

  @override
  Widget build(BuildContext context) {
    final hits = searchLibrary(books, query);
    if (hits.isEmpty) return _NoHits(query: query.trim());
    // The list is either all spellings or all guesses, never mixed.
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

/// Nothing matched: echoes the query as typed and offers two doors.
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
          style: ansiSerif(size: AnsiType.heading),
        ),
        const SizedBox(height: 18),
        DashedAction(
          icon: FLucideIcons.plus,
          label: 'new recipe called “$query”',
          // The typed query becomes the new recipe's title.
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

  /// The whole library: what reorder moves against and the last-book delete
  /// refusal counts.
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
                  // Header: name and count line, then the fold chevron.
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
                                  size: AnsiType.heading,
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
                    // No add-a-section row: `New section` is in the `⋯`.
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

/// The door that makes a book, under the last of them.
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

/// The widest the ledger's column is drawn: the longest heading line a book
/// makes. Below it the column is fluid.
const double kLedgerWidth = 900;

/// The A–Z index down the right margin, and the clear paper before it.
const double kAzIndexWidth = 34;
const double kAzIndexGap = 40;

/// The width of the search field at the head of the ledger.
const double kLedgerFieldWidth = 300;

/// How far a book's sections are set in from its heading row.
const double kLedgerIndent = 24;

/// How far a recipe line is set in, one step past its section.
const double kLedgerRecipeIndent = 44;

/// The ledger's frame: the head strip, then the body, in one centred column.
///
/// The strip sits outside the body so the field never scrolls away or
/// vanishes when a query empties the tree.
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

/// The head strip: the search field and the new-book link.
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

/// `＋ new book` as a link, where the phone draws a [DashedAction].
class _NewBookLink extends ConsumerWidget {
  const _NewBookLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) => AnsiTap(
    onTap: () => unawaited(promptForNewBook(context, ref)),
    color: AnsiColors.herb,
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: Padding(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.bookPlus, size: 13),
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

/// The books as a ledger, with the A–Z index in the margin.
///
/// The index jumps; it neither sorts nor filters. The ledger is flattened to
/// [_LedgerRow]s in a single [SliverList] so only the lines in the window are
/// built, however long the shelf.
class _Ledger extends ConsumerStatefulWidget {
  const _Ledger({required this.books});

  final List<Book> books;

  @override
  ConsumerState<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends ConsumerState<_Ledger> {
  final _scroll = ScrollController();

  /// One key per book for the index to scroll to. Kept across rebuilds so
  /// the rows inside keep their state.
  final _keys = <String, GlobalKey>{};

  /// The flattened ledger from the last build, for seeking an unbuilt book.
  List<_LedgerRow> _rows = const [];

  /// How many frames a seek may spend landing on a book that is not built.
  static const int _seekFrames = 12;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Scrolls until [bookId]'s heading row is at the top.
  ///
  /// An unbuilt book has no context to reveal, so the seek jumps to the row's
  /// proportional offset and retries next frame, up to [_seekFrames] or until
  /// a jump would not move.
  void _show(String bookId, {int frame = 0}) {
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
    if (!mounted || !_scroll.hasClients || frame >= _seekFrames) return;
    final at = _rows.indexWhere(
      (row) => row is _BookHeadRow && row.book.id == bookId,
    );
    if (at < 0) return;
    final position = _scroll.position;
    final estimate = (position.maxScrollExtent * at / _rows.length).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (estimate == position.pixels) return;
    _scroll.jumpTo(estimate);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _show(bookId, frame: frame + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    // A folded book contributes its heading row alone.
    final folded = ref.watch(foldedBooksProvider).asData?.value ?? const {};
    _rows = _ledgerRows(books, folded);
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
                child: CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverPadding(
                      padding: ansiScrollPadding(
                        context,
                        const EdgeInsets.only(bottom: 36),
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          _line,
                          childCount: _rows.length,
                        ),
                      ),
                    ),
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

  /// One line of the ledger.
  Widget _line(BuildContext context, int index) {
    final row = _rows[index];
    final next = index + 1 < _rows.length ? _rows[index + 1] : null;
    // A hairline closes a book under its last line.
    final closes =
        row is! _ShelfRow &&
        (next == null || next is _BookHeadRow || next is _ShelfRow);

    return _LedgerSlot(
      // The heading row carries the key the A–Z margin scrolls to.
      key: row is _BookHeadRow ? _keyFor(row.book.id) : null,
      closes: closes,
      child: switch (row) {
        _BookHeadRow(:final book, :final open) => Padding(
          padding: EdgeInsets.only(top: 15, bottom: open ? 4 : 0),
          child: _HeadingRow(book: book, books: widget.books, open: open),
        ),
        _SectionRow(:final book, :final section, :final count) => Padding(
          padding: const EdgeInsets.only(
            left: kLedgerIndent,
            top: 9,
            bottom: 1,
          ),
          child: BookSectionLine(book: book, section: section, count: count),
        ),
        _RecipeLineRow(:final book, :final recipe, :final sectionId) => Padding(
          padding: const EdgeInsets.only(left: kLedgerRecipeIndent),
          child: LibraryRecipeRow.ledger(
            recipe: recipe,
            bookId: book.id,
            sectionId: sectionId,
          ),
        ),
        // The same two first-run doors the phone's empty card offers.
        _EmptyBookRow(:final book) => Padding(
          padding: const EdgeInsets.only(left: kLedgerIndent, top: 6),
          child: EmptyShelf(book: book),
        ),
        // No gutter: the ledger's column already is one.
        _ShelfRow() => const _IngredientsShelf(gutter: 0),
      },
    );
  }
}

/// One line of the ledger: a book heading, a section, a recipe, an empty
/// book's doors, or the closing vocabulary shelf.
sealed class _LedgerRow {
  const _LedgerRow();
}

class _BookHeadRow extends _LedgerRow {
  const _BookHeadRow({required this.book, required this.open});

  final Book book;

  /// Whether the book is unfolded.
  final bool open;
}

class _SectionRow extends _LedgerRow {
  const _SectionRow({required this.book, required this.count, this.section});

  final Book book;

  /// Null for the synthetic `Unsectioned` bucket, which comes last.
  final BookSection? section;

  final int count;
}

class _RecipeLineRow extends _LedgerRow {
  const _RecipeLineRow({
    required this.book,
    required this.recipe,
    required this.sectionId,
  });

  final Book book;
  final RecipeSummary recipe;
  final String? sectionId;
}

class _EmptyBookRow extends _LedgerRow {
  const _EmptyBookRow({required this.book});

  final Book book;
}

class _ShelfRow extends _LedgerRow {
  const _ShelfRow();
}

/// The whole shelf as one flat list: each book's heading row and, when open,
/// its sections in order (`Unsectioned` last) with their recipes. The
/// vocabulary shelf is the last row.
List<_LedgerRow> _ledgerRows(List<Book> books, Set<String> folded) {
  final rows = <_LedgerRow>[];
  for (final book in books) {
    final open = !folded.contains(book.id);
    rows.add(_BookHeadRow(book: book, open: open));
    if (!open) continue;
    for (final section in book.sections) {
      rows.add(
        _SectionRow(
          book: book,
          section: section,
          count: section.recipes.length,
        ),
      );
      for (final recipe in section.recipes) {
        rows.add(
          _RecipeLineRow(book: book, recipe: recipe, sectionId: section.id),
        );
      }
    }
    if (book.unsectioned.isNotEmpty) {
      rows.add(_SectionRow(book: book, count: book.unsectioned.length));
      for (final recipe in book.unsectioned) {
        rows.add(_RecipeLineRow(book: book, recipe: recipe, sectionId: null));
      }
    }
    // A bare shelf: no sections and nothing unfiled.
    if (book.sections.isEmpty && book.unsectioned.isEmpty) {
      rows.add(_EmptyBookRow(book: book));
    }
  }
  return rows..add(const _ShelfRow());
}

/// Where a line sits in the column, and the hairline under a book's last
/// line.
class _LedgerSlot extends StatelessWidget {
  const _LedgerSlot({required this.closes, required this.child, super.key});

  final bool closes;
  final Widget child;

  @override
  Widget build(BuildContext context) => closes
      ? DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AnsiColors.line)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: child,
          ),
        )
      : child;
}

/// The heads of the ledger's two columns.
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

/// A book's heading row: fold chevron, name, dotted leader, counts, and the
/// book's [BookMenu]. The name is not a door.
class _HeadingRow extends ConsumerWidget {
  const _HeadingRow({
    required this.book,
    required this.books,
    required this.open,
  });

  final Book book;
  final List<Book> books;
  final bool open;

  /// The widest a book's name is set before it is clipped.
  static const double nameMax = 460;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: [
      AnsiTap(
        onTap: () =>
            unawaited(ref.read(foldedBooksProvider.notifier).toggle(book.id)),
        semanticsLabel: open ? 'Fold the book' : 'Unfold the book',
        color: AnsiColors.muted,
        padding: const EdgeInsets.fromLTRB(0, 6, 8, 6),
        child: Icon(
          open ? FLucideIcons.chevronDown : FLucideIcons.chevronRight,
          size: 14,
        ),
      ),
      // Capped, not [Flexible]: a flexible name would share free space with
      // the leader and leave the counts short of their column.
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: nameMax),
        child: Text(
          book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ansiSerif(size: AnsiType.heading, weight: FontWeight.w500),
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

/// The letter a book files under: its first, accents folded, or `#`.
String bookInitial(Book book) {
  final name = foldDiacritics(book.name.trim()).toUpperCase();
  if (name.isEmpty) return '#';
  final first = name[0];
  return first.codeUnitAt(0) >= 0x41 && first.codeUnitAt(0) <= 0x5A
      ? first
      : '#';
}

/// The margin's letters: `#`, then A–Z.
final List<String> kAzLetters = [
  '#',
  for (var c = 0; c < 26; c++) String.fromCharCode(0x41 + c),
];

/// The A–Z index. Every letter is drawn; only a lit one is a door.
class _AzIndex extends StatelessWidget {
  const _AzIndex({required this.lit, required this.onLetter});

  final Set<String> lit;
  final ValueChanged<String> onLetter;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The margin's label, in the column heads' voice.
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

/// One letter in the A–Z margin. Public so a test can read which are lit.
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

  /// The height of a letter's row.
  static const double rowHeight = 20;

  @override
  Widget build(BuildContext context) => AnsiTap(
    onTap: lit ? onTap : null,
    // Twenty-seven rows must fit one margin, so the row stays 20, below the
    // pointer minimum.
    minTarget: false,
    radius: 4,
    child: SizedBox(
      height: rowHeight,
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          letter,
          style: ansiMono(
            size: 10,
            // An unlit letter takes the hairline's ink.
            color: lit ? AnsiColors.herbDeep : AnsiColors.line,
            weight: lit ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );
}

/// The vocabulary as a shelf after the books: a rule, a micro-label, a count
/// line and a `›`. A place you go, so no card, fold, `⋯` or reorder.
class _IngredientsShelf extends ConsumerWidget {
  const _IngredientsShelf({this.gutter = ansiPageGutter});

  /// The inset either side of the row's contents; zero in the ledger. The
  /// rule runs edge to edge in both.
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = ref.watch(vocabularyCountProvider).asData?.value;
    final stubs = ref.watch(stubCountProvider).asData?.value ?? 0;
    // The count is absent, not zero, until it has loaded.
    final line = [
      if (total != null && total > 0) '$total ${plural(total, 'ingredient')}',
      if (stubs > 0) '$stubs ${plural(stubs, 'stub')}',
    ].join(' · ');

    return Padding(
      // The rule runs edge to edge while the books are inset.
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
                // Not the nav's `library` icon: this is a door out of it.
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

/// No books at all. Nearly unreachable: `ensureDefaultBook` runs at
/// bootstrap.
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
            Text('No books yet', style: ansiSerif(size: AnsiType.heading)),
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
