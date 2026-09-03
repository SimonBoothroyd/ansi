/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/session.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_error_state.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/sync_health_row.dart';
import '../../../shared/write.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/presentation/ingredient_list_view.dart'
    show kIngredientsRoute;
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/format.dart';
import '../data/book_providers.dart';
import '../domain/book.dart';
import '../domain/library_search.dart';
import 'book_pick_sheet.dart';
import 'book_reorder_sheet.dart';
import 'book_view_models.dart';
import 'text_prompt.dart';

class LibraryView extends HookConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    // The field owns its controller (a hook, so it survives every rebuild) and
    // the body branches on WHAT THE FIELD SAYS, never on a query stored
    // elsewhere that could outlive the text that produced it — plan 0020 J4,
    // and the ingredients manager is the working example.
    final field = useTextEditingController();
    final typed = useValueListenable(field).text;
    final searching = typed.trim().isNotEmpty;

    return FScaffold(
      // A tab root sits INSIDE the shell's scaffold, which already shrinks
      // the branch area for the keyboard; a second scaffold subtracting the
      // same inset squeezes the content twice (Android showed a list a few
      // lines tall after the sign-in keyboard).
      resizeToAvoidBottomInset: false,
      childPad: false,
      header: FHeader.nested(
        title: Text('Library', style: ansiHeaderTitle()),
        // D1: `⋯` then `＋`. The plus keeps the rightmost, thumb-reachable
        // slot it already owns, so the muscle memory that exists ("plus, top
        // right, new recipe") gets shorter rather than relocated.
        suffixes: [
          _OverflowMenu(books: library.asData?.value ?? const []),
          const _AddMenu(),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pinned under the header, not a sheet: the Library is where you
          // already are (D2).
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: AnsiSearchField(hint: 'Search recipes', controller: field),
          ),
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
                _ => ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 28),
                  children: [
                    for (final b in books) _BookCard(book: b, books: books),
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
                : '${hits.length} ${hits.length == 1 ? 'recipe' : 'recipes'}',
            style: ansiLabel(),
          ),
        ),
        for (final hit in hits)
          _RecipeRow(recipe: hit.recipe, filing: hit.filing),
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

/// The herb dot on `⋯` while the vocabulary holds stubs (D8). A shape, not a
/// string, so tests name it rather than hunting for a `DecoratedBox`.
const kStubDotKey = Key('library-stub-dot');

/// `＋` — the two doors that make a recipe, and nothing else (D1).
///
/// A plus on a library of recipes promises exactly one thing: type it, or
/// import it. Everything that changes the *shape* of the library lives in
/// [_OverflowMenu] next door.
class _AddMenu extends StatelessWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      // `menuBuilder`, not `menu`: the items need the controller so each can
      // dismiss the menu before it navigates. Picking an item is always the
      // end of the menu's business.
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.cookingPot),
              title: const Text('New recipe'),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce('/recipes/new');
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.download),
              title: const Text('Import a recipe'),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce('/import');
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FHeaderAction(
        icon: const Icon(FLucideIcons.plus),
        onPress: controller.toggle,
      ),
    );
  }
}

/// `⋯` — change the shape of the library, plus the one account action (D1).
///
/// Ingredients sits at the top with its stub badge: that is where the shipped
/// "Ingredients manager · v1" board frame always said the door was, and the
/// code only ever put it under `＋` because `＋` was the only menu there was.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({required this.books});

  /// The library as currently loaded — "Reorder books" is offered only when
  /// there is an order to change.
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stubsAsync = ref.watch(stubCountProvider);
    final stubs = stubsAsync.asData?.value ?? 0;

    return FPopoverMenu(
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.carrot),
              title: const Text('Ingredients'),
              suffix: const _StubCountBadge(),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce(kIngredientsRoute);
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.bookPlus),
              title: const Text('New book'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(promptForNewBook(context, ref));
              },
            ),
            if (books.length >= 2)
              FItem(
                prefix: const Icon(FLucideIcons.arrowUpDown),
                title: const Text('Reorder books'),
                onPress: () {
                  unawaited(controller.hide());
                  unawaited(showBookReorderSheet(context));
                },
              ),
          ],
        ),
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.logOut),
              title: const Text('Sign out'),
              onPress: () async {
                unawaited(controller.hide());
                if (await _confirmSignOut(context)) {
                  await ref.read(sessionControllerProvider.notifier).signOut();
                }
              },
            ),
          ],
        ),
        // The menu's footer: where this device stands with the server. Below
        // the divider because it is a fact, not an action — until it isn't, at
        // which point the row itself becomes the way on.
        FItemGroup(children: const [SyncHealthRow()]),
      ],
      builder: (context, controller, _) => Stack(
        clipBehavior: Clip.none,
        children: [
          FHeaderAction(
            icon: const Icon(FLucideIcons.ellipsis),
            onPress: controller.toggle,
          ),
          // D8: the badge climbs one level, so the door advertises itself
          // without being opened. Absent — not grey — at zero, the same rule
          // the badge inside the menu already documents.
          //
          // Drawn on an ERRORED count too (D6): a dot cannot say "unknown", but
          // hiding it would answer "nothing to flesh out" on a question the app
          // could not answer. It points at the door; the badge inside says so.
          if (stubs > 0 || stubsAsync.hasError)
            const Positioned(
              key: kStubDotKey,
              top: 2,
              right: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AnsiColors.herb,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 6),
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks before signing out: sign-out disconnects sync and clears this device's
/// local copy of the household data (it stays on the server).
Future<bool> _confirmSignOut(BuildContext context) async {
  final confirmed = await showAnsiDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text('Sign out?', style: ansiSerif(size: 20)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'This removes the synced data from this device. It stays in your '
          'household and comes back when you sign in again.',
          style: ansiSans(size: 13, color: AnsiColors.muted),
        ),
      ),
      actions: [
        FButton(
          onPress: () => Navigator.of(context).pop(true),
          child: const Text('Sign out'),
        ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
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
                        _BookMenu(book: book, books: books),
                      ],
                    ),
                  ),
                  if (expanded) ...[
                    for (final section in book.sections)
                      _SectionBlock(book: book, section: section),
                    if (book.unsectioned.isNotEmpty)
                      _SectionBlock(book: book, unsectioned: book.unsectioned),
                    if (_isEmpty) _EmptyShelf(book: book),
                    // D5: the dashed row is the LAST ROW OF THE CARD, not a
                    // button floating in the gap under every book. It now reads
                    // as part of *this* book, and the noise scales with what is
                    // open rather than with how many books exist.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: _AddSectionButton(
                        onTap: () => unawaited(
                          promptForNewSection(context, ref, book.id),
                        ),
                      ),
                    ),
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

/// "＋ new section — name it anything", from the card's dashed row and from the
/// book `⋯` alike (D5's deliberate redundancy — the ingredients manager offers
/// add-new from both its header and its footer for the same reason).
Future<void> promptForNewSection(
  BuildContext context,
  WidgetRef ref,
  String bookId,
) async {
  final name = await promptForText(
    context,
    title: 'New section',
    hint: 'Name it anything',
    confirm: 'Add',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  await ref.write(
    context,
    'add that section',
    () => ref.read(bookRepositoryProvider).createSection(bookId, name),
  );
}

/// The book header's `⋯` — [_SectionMenu]'s menu one level up (D4).
///
/// Same `FPopoverMenu`, same items in the same order, so nothing new is
/// learned. Reorder is deliberately the sections' clunky Move up / Move down:
/// books do not get drag-and-drop while sections still lack it.
class _BookMenu extends ConsumerWidget {
  const _BookMenu({required this.book, required this.books});

  final Book book;
  final List<Book> books;

  Future<void> _move(BuildContext context, WidgetRef ref, int delta) async {
    final ids = books.map((b) => b.id).toList();
    final from = ids.indexOf(book.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= ids.length) return;
    ids
      ..removeAt(from)
      ..insert(to, book.id);
    await ref.write(
      context,
      'reorder the books',
      () => ref.read(bookRepositoryProvider).reorderBooks(ids),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookRepositoryProvider);
    return FPopoverMenu(
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.pencil),
              title: const Text('Rename'),
              onPress: () async {
                unawaited(controller.hide());
                final name = await promptForText(
                  context,
                  title: 'Rename book',
                  hint: 'Book name',
                  initial: book.name,
                  confirm: 'Rename',
                );
                if (name == null || name.trim().isEmpty || !context.mounted) {
                  return;
                }
                await ref.write(
                  context,
                  'rename that book',
                  () => repo.renameBook(book.id, name),
                );
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.plus),
              title: const Text('New section'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(promptForNewSection(context, ref, book.id));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowUp),
              title: const Text('Move up'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_move(context, ref, -1));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowDown),
              title: const Text('Move down'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_move(context, ref, 1));
              },
            ),
          ],
        ),
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.trash2),
              title: const Text('Delete book'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(confirmDeleteBook(context, ref, book, books));
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        variant: FButtonVariant.ghost,
        onPress: controller.toggle,
        child: const Icon(
          FLucideIcons.ellipsis,
          size: 18,
          color: AnsiColors.surface,
        ),
      ),
    );
  }
}

/// Deleting a book: refuse with a count and a door, or confirm (D4).
///
/// The 8.5/8.6 ruling verbatim — "it holds 42 recipes" is something a person
/// can act on, "failed" is not. A book is a shelf, not a container, so this
/// never cascades to the recipes; and the count is read from the REPOSITORY at
/// the moment of the tap, like `usedIn`, never from the cached tree.
Future<void> confirmDeleteBook(
  BuildContext context,
  WidgetRef ref,
  Book book,
  List<Book> books,
) async {
  // Keep-alive, read before the first await: every branch below crosses a
  // dialog, and a throwaway notifier would be disposed before its callback ran.
  final repo = ref.read(bookRepositoryProvider);

  if (books.length <= 1) {
    // Separate on purpose: `ensureDefaultBook()` would re-mint a book on the
    // next launch, and a book that reappears after you delete it is worse than
    // being told no.
    if (!context.mounted) return;
    await _refuse(
      context,
      title: 'Can’t delete “${book.name}”',
      body: 'This is your only book — every recipe needs a shelf.',
    );
    return;
  }

  final held = await repo.countRecipesIn(book.id);
  if (!context.mounted) return;

  if (held > 0) {
    final move = await _refuse(
      context,
      title: 'Can’t delete “${book.name}” yet',
      body:
          'It holds $held ${held == 1 ? 'recipe' : 'recipes'}. Move '
          '${held == 1 ? 'it' : 'them'} to another book first, or delete '
          '${held == 1 ? 'it' : 'them'}.',
      door: 'Move them to…',
    );
    if (!move || !context.mounted) return;
    final target = await showBookPickSheet(
      context,
      moving: held,
      from: book,
      candidates: [
        for (final b in books)
          if (b.id != book.id) b,
      ],
    );
    if (target == null || !context.mounted) return;
    await ref.write(
      context,
      'move those recipes',
      () => repo.moveBookContents(fromBookId: book.id, toBookId: target.id),
    );
    return;
  }

  if (!context.mounted) return;
  final confirmed = await showAnsiDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text('Delete “${book.name}”?', style: ansiSerif(size: 20)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'The shelf is empty, so nothing goes with it.',
          style: ansiSans(size: 13, color: AnsiColors.muted),
        ),
      ),
      actions: [
        FButton(
          onPress: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false) || !context.mounted) return;
  await ref.write(
    context,
    'delete “${book.name}”',
    () => repo.deleteBook(book.id),
  );
}

/// A refusal that names why. Returns true when the reader took the [door] —
/// a refusal without one is a wall in front of the one action that clears it.
Future<bool> _refuse(
  BuildContext context, {
  required String title,
  required String body,
  String? door,
}) async {
  final took = await showAnsiDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text(title, style: ansiSerif(size: 20)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(body, style: ansiSans(size: 13, color: AnsiColors.muted)),
      ),
      actions: [
        if (door != null)
          FButton(
            onPress: () => Navigator.of(context).pop(true),
            child: Text(door),
          ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(false),
          child: Text(door == null ? 'OK' : 'Cancel'),
        ),
      ],
    ),
  );
  return took ?? false;
}

/// The first-run shelf (D7·2): the app opens on this, so it offers the two
/// doors in place rather than sending you to find a menu.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Nothing on this shelf yet',
            style: ansiSerif(size: 15, color: AnsiColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DashedAction(
                  icon: FLucideIcons.plus,
                  label: 'new recipe',
                  onTap: () => context.pushOnce('/recipes/new'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DashedAction(
                  icon: FLucideIcons.download,
                  label: 'import one',
                  onTap: () => context.pushOnce('/import'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What a book says it holds — `42 recipes · 3 sections`.
///
/// A fold that hides how much it hides is a fold you stop trusting, so the
/// line reads the same open or shut. An empty shelf says **"no recipes yet"**,
/// never `0 recipes`, and a book with no sections omits that half entirely:
/// the `_StubCountBadge` rule — a zero that renders looks like a bug.
String bookCountLine(Book book) {
  final recipes =
      book.unsectioned.length +
      book.sections.fold(0, (n, s) => n + s.recipes.length);
  final sections = book.sections.length;
  return [
    if (recipes == 0)
      'no recipes yet'
    else
      '$recipes ${recipes == 1 ? 'recipe' : 'recipes'}',
    if (sections > 0) '$sections ${sections == 1 ? 'section' : 'sections'}',
  ].join(' · ');
}

/// One section (or the synthetic Unsectioned bucket, when [section] is null)
/// and its recipe rows.
class _SectionBlock extends ConsumerWidget {
  const _SectionBlock({
    required this.book,
    this.section,
    this.unsectioned = const [],
  });

  final Book book;
  final BookSection? section;
  final List<RecipeSummary> unsectioned;

  List<RecipeSummary> get _recipes => section?.recipes ?? unsectioned;
  String get _label => section?.name ?? 'Unsectioned';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = this.section;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _label,
                  style: ansiSerif(
                    size: 14,
                    color: section == null
                        ? AnsiColors.muted
                        : AnsiColors.herbDeep,
                    weight: FontWeight.w400,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
              if (section != null) _SectionMenu(book: book, section: section),
            ],
          ),
          if (_recipes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No recipes yet',
                style: ansiMono(size: 11, color: AnsiColors.muted),
              ),
            )
          else
            for (final r in _recipes) _RecipeRow(recipe: r),
        ],
      ),
    );
  }
}

class _SectionMenu extends ConsumerWidget {
  const _SectionMenu({required this.book, required this.section});

  final Book book;
  final BookSection section;

  /// Moves [section] by [delta] positions within [book] and persists the order.
  Future<void> _move(BuildContext context, WidgetRef ref, int delta) async {
    final ids = book.sections.map((s) => s.id).toList();
    final from = ids.indexOf(section.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= ids.length) return;
    ids
      ..removeAt(from)
      ..insert(to, section.id);
    await ref.write(
      context,
      'reorder the sections',
      () => ref.read(bookRepositoryProvider).reorderSections(book.id, ids),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookRepositoryProvider);
    return FPopoverMenu(
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.pencil),
              title: const Text('Rename'),
              onPress: () async {
                unawaited(controller.hide());
                final name = await promptForText(
                  context,
                  title: 'Rename section',
                  hint: 'Section name',
                  initial: section.name,
                  confirm: 'Rename',
                );
                if (name == null || name.trim().isEmpty || !context.mounted) {
                  return;
                }
                await ref.write(
                  context,
                  'rename that section',
                  () => repo.renameSection(section.id, name),
                );
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowUp),
              title: const Text('Move up'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_move(context, ref, -1));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowDown),
              title: const Text('Move down'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_move(context, ref, 1));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.trash2),
              title: const Text('Delete'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(
                  ref.write(
                    context,
                    'delete that section',
                    () => repo.deleteSection(section.id),
                  ),
                );
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => FButton.icon(
        variant: FButtonVariant.ghost,
        onPress: controller.toggle,
        child: const Icon(FLucideIcons.ellipsis, size: 18),
      ),
    );
  }
}

/// One recipe: title · (★ when favourited) · serves N · ›.
///
/// The star REPORTS ONLY (D6). `RecipeSummary.favorite` has existed since 0011
/// and the picker has a Favorites tab, so a library that cannot show a star
/// makes the recipe page's star feel like it went nowhere — but toggling stays
/// on the recipe page, and this row keeps its single tap target. Absent when
/// false, never a hollow outline on every line: the stub badge's rule.
///
/// Refused here on purpose: a "keeps 4 d" chip (shelf life is a *planning*
/// fact, which is why the picker row carries it and a browsing row doesn't)
/// and a macro badge (on honest numbers most rows would show a number nobody
/// asked for, or an `incomplete` nag).
///
/// [filing] is set only on a search result, where the tree that would have said
/// where this lives is not on screen.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.recipe, this.filing});

  final RecipeSummary recipe;
  final Filing? filing;

  @override
  Widget build(BuildContext context) {
    final filing = this.filing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushOnce('/recipes/${recipe.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                    style: ansiSerif(size: 17),
                  ),
                  if (filing != null)
                    Text(
                      '${filing.book} · ${filing.section ?? 'Unsectioned'}',
                      style: ansiMono(size: 10, color: AnsiColors.muted),
                    ),
                ],
              ),
            ),
            if (recipe.favorite) ...[
              const Icon(FLucideIcons.star, size: 13, color: AnsiColors.aging),
              const SizedBox(width: 6),
            ],
            Text(
              'serves ${formatQuantity(recipe.servingsBase)}',
              style: ansiMono(size: 11, color: AnsiColors.muted),
            ),
            const SizedBox(width: 8),
            const Icon(
              FLucideIcons.chevronRight,
              size: 16,
              color: AnsiColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Not presets" — the promise the original board frame was built to make, and
/// the reason the copy is an invitation rather than a label.
class _AddSectionButton extends StatelessWidget {
  const _AddSectionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DashedAction(
    icon: FLucideIcons.plus,
    label: 'new section — name it anything',
    onTap: onTap,
  );
}

/// No books at all (D7·1) — nearly unreachable, since `ensureDefaultBook()`
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
  final name = await promptForText(
    context,
    title: 'New book',
    hint: 'e.g. Our Cookbook',
    confirm: 'Create',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  await ref.write(
    context,
    'create that book',
    () => ref.read(bookRepositoryProvider).createBook(name),
  );
}

/// How many vocab rows still read `stub`, on the Library menu's Ingredients
/// item (plan 0020 D8). Absent — not a `0` — when there is nothing to flesh
/// out: a badge that always shows a number stops meaning anything.
class _StubCountBadge extends ConsumerWidget {
  const _StubCountBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stubCountProvider);
    // Load-bearing emptiness (D6): a `?? 0` here rendered an errored stream as
    // "nothing to flesh out" on the one honest work-queue the app has. The
    // count and the not-knowing are different facts, so they look different.
    if (async.hasError) {
      return FBadge(
        variant: FBadgeVariant.secondary,
        child: Text(
          'stubs unknown',
          style: ansiMono(size: 10, color: AnsiColors.aging),
        ),
      );
    }
    final count = async.asData?.value ?? 0;
    if (count == 0) return const SizedBox.shrink();
    return FBadge(
      variant: FBadgeVariant.secondary,
      child: Text(
        '$count stub${count == 1 ? '' : 's'}',
        style: ansiMono(size: 10, color: AnsiColors.muted),
      ),
    );
  }
}
