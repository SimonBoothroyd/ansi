/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
///
/// **Two bodies over one screen.** On a phone and a portrait tablet the books
/// are cards that fold open onto their sections, which is the only honest shape
/// for one column. At [AnsiLayout.expanded] they are a **ledger** instead: one
/// column of books at [kLedgerWidth], centred, with a [kAzIndexWidth] A–Z index
/// down the right margin. A book is a heading row — its name, a dotted leader,
/// its count line in a column of numbers, its `⋯` — over **every section it
/// keeps and every recipe under each**, each set as one line into the same
/// column. No tile, no grid, no dark band: the owner refused those on sight
/// ("corporate"), and what replaced them states every fact once and sets it in
/// a column on bare paper.
///
/// **The ledger is open.** A laptop has the room, so the wide Library shows the
/// whole shelf rather than a peek and a count of the rest: no fold row saying
/// `39 more, in 3 sections`, and no second screen to go to for the section
/// names — the owner's call, *"one Library screen showing everything is the
/// better flavour"*. It is long and it scrolls, which is what a desk does.
/// `/books/:id` still exists and is still deep-linkable; nothing here links to
/// it.
///
/// **What the width does not change.** The fold is the phone's own, per book
/// and per device, read from the same store — folded is the exception, open the
/// default; the search field, the one ranked column of results, the
/// `＋ new book` door and the Ingredients shelf are the same objects; and every
/// row, menu and section widget is shared with the card and with the book page.
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

/// How far a book's sections are set in from its heading row.
const double kLedgerIndent = 24;

/// How far a recipe line is set in — one step further, so the three levels the
/// ledger holds are readable as three without a rule or a box drawn round any
/// of them.
const double kLedgerRecipeIndent = 44;

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

/// The books as a ledger at [AnsiLayout.expanded]: one column of heading rows
/// and their lines, with the A–Z index in the margin beside it.
///
/// The index is a **jump**, not a sort and not a filter: the books stay in the
/// household's own order — what `Move up` and `Move down` write — and a lit
/// letter scrolls to the first book that starts with it. That is what lets the
/// shape hold at twenty-five books without becoming a grid.
///
/// **One sliver list, however long the shelf is.** The whole ledger is
/// flattened to [_LedgerRow]s and handed to a single [SliverList], so
/// twenty-five books and a few hundred recipes build only the lines in the
/// window. A widget per book holding its own sections would be one enormous
/// sliver child, laid out in full the moment its book came on screen; a nested
/// [ListView] per book would shrink-wrap, which is that cost again with a
/// scroll position nobody asked for.
///
/// A [StatefulWidget] for the same reason the book page's panes are: it owns a
/// scroll position, which belongs to the widget that owns the controller and
/// dies with it.
class _Ledger extends ConsumerStatefulWidget {
  const _Ledger({required this.books});

  final List<Book> books;

  @override
  ConsumerState<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends ConsumerState<_Ledger> {
  final _scroll = ScrollController();

  /// One key per book, so the index can scroll to it. Kept across rebuilds — a
  /// fresh key would rebuild the book and lose the row states inside it.
  final _keys = <String, GlobalKey>{};

  /// The flattened ledger as the last build computed it — held because a seek
  /// has to know where a book falls in a list it cannot see yet, and read
  /// nowhere else.
  List<_LedgerRow> _rows = const [];

  /// How many frames a seek may spend landing on a book that is not built.
  static const int _seekFrames = 12;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  /// Scrolls the ledger until [bookId]'s heading row is at the top.
  ///
  /// A book far enough down the lazy list has not been built, so there is no
  /// context to reveal. The seek then reads where the row falls in the flat
  /// list, jumps to the offset that is in proportion to it and asks again on
  /// the next frame: every jump builds a new window and refines the list's own
  /// extent, so the row is a few frames away at most. It gives up after
  /// [_seekFrames], or as soon as a jump would not move — a margin that cannot
  /// find a book is better than one that scrolls for ever.
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
    // The fold is read here, once, rather than in every line: the flat list is
    // what the fold changes — a shut book contributes its heading row alone.
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

  /// One line of the ledger, built as it comes into the window.
  Widget _line(BuildContext context, int index) {
    final row = _rows[index];
    final next = index + 1 < _rows.length ? _rows[index + 1] : null;
    // A hairline closes a book under its last line, wherever that falls — the
    // rule the phone's card gets for free from its border.
    final closes =
        row is! _ShelfRow &&
        (next == null || next is _BookHeadRow || next is _ShelfRow);

    return _LedgerSlot(
      // The heading row is what the A–Z margin scrolls to, so it is the line
      // that carries the book's key.
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
        // The first-run doors, in place — the same two the phone's empty card
        // offers, because the app can still open on this.
        _EmptyBookRow(:final book) => Padding(
          padding: const EdgeInsets.only(left: kLedgerIndent, top: 6),
          child: EmptyShelf(book: book),
        ),
        // The vocabulary closes the ledger exactly as it closes the phone's
        // books, minus the phone's gutters: the ledger's column IS the gutter.
        _ShelfRow() => const _IngredientsShelf(gutter: 0),
      },
    );
  }
}

/// One line of the open ledger: a book's heading row, a section's, a recipe
/// under one, the two doors an empty book offers, or the vocabulary shelf that
/// closes the column.
///
/// The ledger is a list of these rather than a list of books, so that every
/// line — not every book — is what the sliver list builds lazily.
sealed class _LedgerRow {
  const _LedgerRow();
}

class _BookHeadRow extends _LedgerRow {
  const _BookHeadRow({required this.book, required this.open});

  final Book book;

  /// Whether the fold is letting the book's own lines through.
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

/// The whole shelf as one flat list of lines: every book's heading row, and
/// under an open one every section in the book's own order with `Unsectioned`
/// last and every recipe under each.
///
/// This is the ledger's whole claim in one function — the wide Library lists
/// **everything**, so nothing here counts, truncates or defers to another page.
/// A folded book contributes its heading row alone, which is what the fold has
/// always meant, and the vocabulary shelf is the last line, as it is the last
/// row on the phone.
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
    // The phone's own rule for a bare shelf: no sections and nothing unfiled.
    if (book.sections.isEmpty && book.unsectioned.isEmpty) {
      rows.add(_EmptyBookRow(book: book));
    }
  }
  return rows..add(const _ShelfRow());
}

/// Where a line sits in the column, and the hairline that closes a book.
///
/// The border is on the **last line of a book** rather than on a box round the
/// book, because there is no box: a book is a heading and the lines under it,
/// and the rule under the last of them is what says the next heading is a new
/// one.
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

/// A book's heading row: the fold's chevron, the name, a dotted leader into the
/// counts column, and the book's own `⋯`.
///
/// Two targets, each doing one thing: the chevron folds (the phone's own
/// per-device state, so a book shut on this desk is shut here tomorrow) and the
/// `⋯` is [BookMenu] — the same menu the card's herb band and the page's header
/// bar hang. **The name is not a door.** It was the way to `/books/:id` while
/// the ledger showed three lines and a count; the ledger now shows the book, so
/// there is nothing behind the name to go to.
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
      // Capped rather than [Flexible]: a flexible name would divide the row's
      // free space with the leader and leave the counts short of the column
      // they are ruled to.
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: nameMax),
        child: Text(
          book.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ansiSerif(size: 18, weight: FontWeight.w500),
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
  Widget build(BuildContext context) => AnsiTap(
    onTap: lit ? onTap : null,
    // The margin's twenty-seven rows ARE the geometry: grown to the pointer's
    // 32 they would be a column, not a margin. The row is 20 and stays 20;
    // the ground and the ring fill it.
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
