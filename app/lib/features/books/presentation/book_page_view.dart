/// One book on a page of its own, at `/books/:id`.
///
/// Nothing in the app links here; the page exists so the URL works. It
/// shares every control with the Library card (`book_rows.dart`). At
/// [AnsiLayout.expanded] the sections become an index down the left that
/// scrolls the one list; it does not filter.
library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_back.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_layout.dart';
import '../../../shared/ansi_scroll.dart';
import '../domain/book.dart';
import 'book_rows.dart';
import 'book_view_models.dart';

/// How wide the section index is drawn at [AnsiLayout.expanded].
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
      // Read the book out of the Library aggregate the app already watches.
      // A book deleted from its own page stops being in it.
      data: (books) {
        final book = books.where((b) => b.id == bookId).firstOrNull;
        if (book == null) {
          return FScaffold(
            header: const _BackOnly(),
            child: Center(
              child: Text(
                'Book not found',
                style: ansiSerif(size: AnsiType.heading),
              ),
            ),
          );
        }
        return _BookBody(book: book, books: books);
      },
    );
  }
}

/// Back and nothing else, for a page with no book to name.
class _BackOnly extends StatelessWidget {
  const _BackOnly();

  @override
  Widget build(BuildContext context) =>
      const FHeader.nested(prefixes: [_BackAction()]);
}

/// The page's back control: pops, or falls back to the Library on a cold
/// deep link (`shared/ansi_back.dart`).
class _BackAction extends StatelessWidget {
  const _BackAction();

  @override
  Widget build(BuildContext context) =>
      FHeaderAction.back(onPress: () => ansiBack(context));
}

class _BookBody extends StatelessWidget {
  const _BookBody({required this.book, required this.books});

  final Book book;

  /// The whole library: what the book menu's reorder and delete read.
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

/// The book's name and what it holds, as the page's title.
class _BookHero extends StatelessWidget {
  const _BookHero({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        book.name,
        style: ansiSerif(size: AnsiType.title, weight: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        bookCountLine(book),
        style: ansiMono(size: 11, color: AnsiColors.muted, letterSpacing: 0.8),
      ),
    ],
  );
}

/// A book's sections in order, with the synthetic Unsectioned bucket last.
/// That bucket's `id` is null, as [BookSectionBlock]'s section is.
List<({String? id, String name, int count})> bookIndexEntries(Book book) => [
  for (final section in book.sections)
    (id: section.id, name: section.name, count: section.recipes.length),
  if (book.unsectioned.isNotEmpty)
    (id: null, name: 'Unsectioned', count: book.unsectioned.length),
];

/// The phone's layout: the hero, then one block per section.
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

/// The body's blocks, shared by both layouts: every section in order,
/// Unsectioned last, or the first-run doors when the shelf is bare.
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

/// The index beside the recipes, at [AnsiLayout.expanded]. The index scrolls
/// the one list and lights the section at its top.
class _Panes extends StatefulWidget {
  const _Panes({required this.book});

  final Book book;

  @override
  State<_Panes> createState() => _PanesState();
}

class _PanesState extends State<_Panes> {
  final _scroll = ScrollController();

  /// One key per section block (null for Unsectioned) for the index to
  /// scroll to. Kept across rebuilds so the rows inside keep their state.
  final _keys = <String?, GlobalKey>{};

  /// The section the list is showing; null before the first scroll, when the
  /// first entry is lit.
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

  /// Lights the last section that has reached the top of the list.
  ///
  /// Uses [RenderAbstractViewport.getOffsetToReveal] rather than painted
  /// positions, because a sliver child's paint transform is in the list's
  /// layout space and never moves. An unbuilt section above the viewport is
  /// skipped harmlessly.
  void _readScroll() {
    if (!_scroll.hasClients) return;
    final offset = _scroll.offset;
    String? lit;
    var found = false;
    for (final entry in bookIndexEntries(widget.book)) {
      final block = _keys[entry.id]?.currentContext?.findRenderObject();
      if (block == null) continue;
      final viewport = RenderAbstractViewport.maybeOf(block);
      if (viewport == null) continue;
      if (viewport.getOffsetToReveal(block, 0).offset <= offset + 8) {
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
    // A section far down the list is not built, so there is no context to
    // scroll to. Jumping to the end builds the tail for the next frame.
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
                      controller: _scroll,
                      padding: ansiScrollPadding(
                        context,
                        const EdgeInsets.only(bottom: 32),
                      ),
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

/// One name in the index: name, count, and whether it is lit. Unsectioned
/// is [quiet].
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
                  size: AnsiType.small,
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
