/// One book on a page of its own — the tree the Library's card holds, given a
/// URL (design board: **Book**).
///
/// It is a pushed page, so the tab bar is gone and back returns to the Library:
/// the bar being absent is what says you have left the tab loop. Nothing here
/// folds — the page *is* the book already open — and every control the card
/// offered comes along unchanged, because they are the same widgets
/// (`book_rows.dart`): the section `＋`, the section `⋯`, the row's `⋯`, and the
/// book's own menu, which on this page is the header bar's trailing action.
///
/// At [AnsiLayout.expanded] the sections become an index down the left and the
/// recipes keep the measure beside it. The index is an **index, not a filter**:
/// tapping a name scrolls the one list to that section, so a reader always has
/// the whole book in its own order — a filter would answer a question nobody
/// asked, and hide the section above the one they wanted.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/guarded_navigation.dart';
import '../domain/book.dart';
import 'book_rows.dart';
import 'book_view_models.dart';

/// The route a shelf tile opens, and the one a link can be pasted at.
String bookRoute(String bookId) => '/books/$bookId';

/// How wide the section index is drawn at [AnsiLayout.expanded].
///
/// Fixed, like every other size in the app: a section name is a few words and a
/// count is two digits, so the column that holds them does not need to be
/// derived from the window.
const double kSectionIndexWidth = 200;

class BookPageView extends ConsumerWidget {
  const BookPageView({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    return library.when(
      loading: () => const FScaffold(
        header: _BackOnly(),
        child: Center(child: FCircularProgress()),
      ),
      error: (e, st) => FScaffold(
        header: const _BackOnly(),
        child: AnsiErrorState(
          what: 'this book',
          error: e,
          stackTrace: st,
          onRetry: () => ref.invalidate(libraryProvider),
        ),
      ),
      // The Library aggregate is one watched query the app already keeps live,
      // so the page reads the book out of it rather than adding a second query
      // for one row. A book deleted from its own page simply stops being in it.
      data: (books) {
        final book = books.where((b) => b.id == bookId).firstOrNull;
        if (book == null) {
          return FScaffold(
            header: const _BackOnly(),
            child: Center(
              child: Text('Book not found', style: ansiSerif(size: 20)),
            ),
          );
        }
        return _BookBody(book: book, books: books);
      },
    );
  }
}

/// Back and nothing else — what a page with no book to name can offer.
class _BackOnly extends StatelessWidget {
  const _BackOnly();

  @override
  Widget build(BuildContext context) =>
      const FHeader.nested(prefixes: [_BackAction()]);
}

/// The page's own back control: pops to whatever opened it, and falls back to
/// the Library on a cold deep link, where there is genuinely nothing beneath.
class _BackAction extends StatelessWidget {
  const _BackAction();

  @override
  Widget build(BuildContext context) => FHeaderAction.back(
    onPress: () => context.canPop() ? context.pop() : context.goOnce('/'),
  );
}

class _BookBody extends StatelessWidget {
  const _BookBody({required this.book, required this.books});

  final Book book;

  /// The whole library — what the book menu's reorder moves against, and what
  /// its delete counts before refusing.
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final wide = AnsiLayout.of(context) == AnsiLayout.expanded;
    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        prefixes: const [_BackAction()],
        suffixes: [BookMenu.headerBar(book: book, books: books)],
      ),
      child: wide ? _Panes(book: book) : _OneColumn(book: book),
    );
  }
}

/// The book's name and what it holds. No herb band: on the shelf the band is
/// what makes a tile a book, and here the page is the book, so the name is the
/// page's title.
class _BookHero extends StatelessWidget {
  const _BookHero({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(book.name, style: ansiSerif(size: 28, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        bookCountLine(book),
        style: ansiMono(size: 11, color: AnsiColors.muted, letterSpacing: 0.8),
      ),
    ],
  );
}

/// The sections a book offers, in the order it keeps them, with the synthetic
/// Unsectioned bucket last — the Library card's own order.
///
/// An entry's `id` is null for that bucket, exactly as [BookSectionBlock]'s
/// section is.
List<({String? id, String name, int count})> bookIndexEntries(Book book) => [
  for (final section in book.sections)
    (id: section.id, name: section.name, count: section.recipes.length),
  if (book.unsectioned.isNotEmpty)
    (id: null, name: 'Unsectioned', count: book.unsectioned.length),
];

/// The sections as the phone draws them: the hero, then one block each.
class _OneColumn extends StatelessWidget {
  const _OneColumn({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.only(bottom: 32),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
        child: _BookHero(book: book),
      ),
      ..._sections(book),
    ],
  );
}

/// The blocks a book's body is made of, shared by both layouts: every section
/// in order, Unsectioned last, and the first-run doors when the shelf is bare.
List<Widget> _sections(Book book, {Map<String?, Key>? keys}) => [
  for (final section in book.sections)
    BookSectionBlock(key: keys?[section.id], book: book, section: section),
  if (book.unsectioned.isNotEmpty)
    BookSectionBlock(
      key: keys?[null],
      book: book,
      unsectioned: book.unsectioned,
    ),
  if (book.sections.isEmpty && book.unsectioned.isEmpty) EmptyShelf(book: book),
];

/// The index beside the recipes, at [AnsiLayout.expanded].
///
/// The list is one scrollable holding the whole book; the index scrolls it and
/// lights whichever section is at the top of it. That is why this is a
/// [StatefulWidget] and not a notifier: it is scroll position, which belongs to
/// the widget that owns the controller and dies with it.
class _Panes extends StatefulWidget {
  const _Panes({required this.book});

  final Book book;

  @override
  State<_Panes> createState() => _PanesState();
}

class _PanesState extends State<_Panes> {
  final _scroll = ScrollController();

  /// The list itself — what a section's offset is measured against, so "has
  /// this label passed the top?" is asked in the list's own coordinates.
  final _listKey = GlobalKey();

  /// One key per section block, so the index can scroll to it. Keyed by section
  /// id (null for Unsectioned) and kept across rebuilds — a fresh key would
  /// rebuild the block and lose the row states inside it.
  final _keys = <String?, GlobalKey>{};

  /// The section the list is showing, or null before the first scroll — then
  /// the first entry is lit, which is what is on screen.
  String? _lit;
  bool _litIsSet = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_readScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_readScroll)
      ..dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String? id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Lights the last section whose label has passed the top of the list.
  ///
  /// A section scrolled far above the viewport can be unbuilt, and then it has
  /// no context to measure — which is harmless here: the one at the top is by
  /// definition built, so it is still the last match.
  void _readScroll() {
    final list = _listKey.currentContext?.findRenderObject();
    if (list is! RenderBox) return;
    String? lit;
    var found = false;
    for (final entry in bookIndexEntries(widget.book)) {
      final block = _keys[entry.id]?.currentContext?.findRenderObject();
      if (block is! RenderBox) continue;
      if (block.localToGlobal(Offset.zero, ancestor: list).dy <= 8) {
        lit = entry.id;
        found = true;
      }
    }
    if (!found || (_litIsSet && lit == _lit)) return;
    setState(() {
      _lit = lit;
      _litIsSet = true;
    });
  }

  /// Scrolls the list until [id]'s label is at the top.
  void _show(String? id) {
    final target = _keys[id]?.currentContext;
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
    // A section far enough down the list has not been built, so there is no
    // context to scroll to. Jumping to the end builds the tail; the section is
    // then there to land on, one frame later.
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final built = _keys[id]?.currentContext;
      if (built != null) unawaited(Scrollable.ensureVisible(built));
    });
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final entries = bookIndexEntries(book);
    final lit = _litIsSet ? _lit : entries.firstOrNull?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
          child: _BookHero(book: book),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: kSectionIndexWidth,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 12, 24),
                  children: [
                    for (final entry in entries)
                      _IndexRow(
                        name: entry.name,
                        count: entry.count,
                        lit: entry.id == lit,
                        quiet: entry.id == null,
                        onTap: () => _show(entry.id),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: ansiMeasureWidth(context),
                    ),
                    child: ListView(
                      key: _listKey,
                      controller: _scroll,
                      padding: const EdgeInsets.only(bottom: 32),
                      children: _sections(
                        book,
                        keys: {
                          for (final entry in entries)
                            entry.id: _keyFor(entry.id),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One name in the index: what it is called, what it holds, and whether the
/// list is showing it. Unsectioned is [quiet] — it is a bucket, not a name
/// somebody typed.
class _IndexRow extends StatelessWidget {
  const _IndexRow({
    required this.name,
    required this.count,
    required this.lit,
    required this.quiet,
    required this.onTap,
  });

  final String name;
  final int count;
  final bool lit;
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = quiet
        ? AnsiColors.muted
        : (lit ? AnsiColors.herbDeep : AnsiColors.ink);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: lit ? AnsiColors.herbSoft : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ansiSerif(
                  size: 14,
                  color: ink,
                  weight: lit ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('$count', style: ansiMono(size: 10, color: AnsiColors.muted)),
          ],
        ),
      ),
    );
  }
}
