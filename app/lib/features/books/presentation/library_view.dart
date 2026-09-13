/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
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
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_more_trigger.dart';
import '../../../shared/ansi_search_field.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
import '../../account/presentation/account_view.dart';
import '../../ingredients/data/ingredient_providers.dart';
import '../../ingredients/presentation/ingredient_list_view.dart'
    show kIngredientsRoute;
import '../../ingredients/presentation/macros_format.dart';
import '../../recipes/data/recipe_providers.dart';
import '../../recipes/domain/recipe.dart';
import '../data/book_providers.dart';
import '../domain/book.dart';
import '../domain/library_search.dart';
import 'book_pick_sheet.dart';
import 'book_view_models.dart';
import 'recipe_move_sheet.dart';
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
          // One household door, not two: once the chrome is beside the content
          // Account is the sidebar's footer item, and that is the only door
          // there is.
          if (!AnsiShell.of(context).beside)
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
                _ => ListView(
                  padding: const EdgeInsets.only(top: 4, bottom: 28),
                  children: [
                    for (final b in books) _BookCard(book: b, books: books),
                    // E7: the dashed row the v2 board drew and the build
                    // missed. It closes the books.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: DashedAction(
                        icon: FLucideIcons.bookPlus,
                        label: 'new book',
                        onTap: () => unawaited(promptForNewBook(context, ref)),
                      ),
                    ),
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

/// "New section", from the book `⋯` — its one door since 0028 E3 retired the
/// card's dashed twin. The invitation D5 was protecting ("name it anything")
/// lives in the prompt's own hint, which is where a person actually reads it.
Future<void> promptForNewSection(
  BuildContext context,
  WidgetRef ref,
  String bookId,
) async {
  // The prompt's keyboard shrinks the Library under it, so the card row that
  // opened it can be unmounted by the time Add is tapped: the write goes
  // through handles that outlive the row (`hostContextOf`), never a `ref`
  // after the await and never a `context.mounted` bail that drops the name.
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);
  final name = await promptForText(
    context,
    title: 'New section',
    hint: 'Name it anything',
    confirm: 'Add',
    clean: NameKind.title,
  );
  if (name == null || name.trim().isEmpty) return;
  await container.write(
    host,
    'add that section',
    () => container.read(bookRepositoryProvider).createSection(bookId, name),
  );
}

/// The book header's `⋯` — [_SectionMenu]'s menu one level up (D4).
///
/// Same [FPopoverMenu], same items in the same order, so nothing new is
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
                // The prompt's keyboard can unmount this header row; the
                // write continues through handles that outlive it.
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final host = hostContextOf(context);
                final name = await promptForText(
                  context,
                  title: 'Rename book',
                  hint: 'Book name',
                  initial: book.name,
                  confirm: 'Rename',
                  clean: NameKind.title,
                );
                if (name == null || name.trim().isEmpty) return;
                await container.write(
                  host,
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
      builder: (context, controller, _) =>
          AnsiMoreTrigger(onTap: controller.toggle, color: AnsiColors.surface),
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
  // The container and the host context outlive the header row that opened
  // the menu (`hostContextOf`): every dialog after the first await opens
  // from the host, and the write goes through the container — never a `ref`
  // after an await, never a `context.mounted` bail that drops a confirmed
  // delete or move.
  final repo = ref.read(bookRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);

  if (books.length <= 1) {
    // Separate on purpose: `ensureDefaultBook()` would re-mint a book on the
    // next launch, and a book that reappears after you delete it is worse than
    // being told no.
    await refuseAnsi(
      host.context,
      title: 'Can’t delete “${book.name}”',
      body: 'This is your only book — every recipe needs a shelf.',
    );
    return;
  }

  final held = await repo.countRecipesIn(book.id);

  if (held > 0) {
    final move = await refuseAnsi(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      host.context,
      title: 'Can’t delete “${book.name}” yet',
      body:
          'It holds $held ${plural(held, 'recipe')}. Move '
          '${plural(held, 'it', plural: 'them')} to another book first, or '
          'delete ${plural(held, 'it', plural: 'them')}.',
      door: 'Move them to…',
    );
    if (!move) return;
    final target = await showBookPickSheet(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      host.context,
      moving: held,
      from: book,
      candidates: [
        for (final b in books)
          if (b.id != book.id) b,
      ],
    );
    if (target == null) return;
    await container.write(
      host,
      'move those recipes',
      () => repo.moveBookContents(fromBookId: book.id, toBookId: target.id),
    );
    return;
  }

  final confirmed = await askAnsi(
    // The host outlives the row — see [hostContextOf].
    // ignore: use_build_context_synchronously
    host.context,
    title: 'Delete “${book.name}”?',
    body: 'The shelf is empty, so nothing goes with it.',
    confirm: 'Delete',
  );
  if (!confirmed) return;
  await container.write(
    host,
    'delete “${book.name}”',
    () => repo.deleteBook(book.id),
  );
}

/// The first-run shelf: the app opens on this, so it offers the two doors in
/// place rather than sending you to find a menu. Both doors carry the book,
/// exactly as the section `＋` does — a recipe started from an empty shelf
/// files onto that shelf, not onto whichever book sorts first.
class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.book});

  final Book book;

  String _route(String path) =>
      Uri(path: path, queryParameters: {'book': book.id}).toString();

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
                  onTap: () => context.pushOnce(_route('/recipes/new')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DashedAction(
                  icon: FLucideIcons.download,
                  label: 'import one',
                  onTap: () => context.pushOnce(_route('/import')),
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
/// never `0 recipes`, and a book with no sections omits that half entirely — a
/// zero that renders looks like a bug.
String bookCountLine(Book book) {
  final recipes =
      book.unsectioned.length +
      book.sections.fold<int>(0, (n, s) => n + s.recipes.length);
  final sections = book.sections.length;
  return [
    if (recipes == 0)
      'no recipes yet'
    else
      '$recipes ${plural(recipes, 'recipe')}',
    if (sections > 0) '$sections ${plural(sections, 'section')}',
  ].join(' · ');
}

/// What a recipe row says under its title — `serves 4 · 520 kcal · 28 g
/// protein`, or `serves 2` on its own.
///
/// **Honest numbers, or silence** (invariant 3). A recipe whose macros are
/// incomplete prints the serves and stops: no `—`, no `incomplete` badge, no
/// nag. The badge belongs where a person is *choosing* what to cook — the
/// picker row wears one and says which lines it is waiting on — and a browsing
/// row that nagged on every stub is the exact thing this line's ancestor was
/// refused for. Silence here costs nothing: the recipe page says why.
///
/// `kcal` and `protein` are the two the recipe page's per-serving panel leads
/// with, so the two surfaces agree about what matters; carb and fat stay on the
/// page. [RecipeSummary.macros] is already per-serving and already computed in
/// the same watch the library reads, so this line costs no query.
String recipeStatsLine(RecipeSummary recipe) {
  final serves = 'serves ${formatQuantity(recipe.servingsBase)}';
  final perServing = recipe.macros?.perServing;
  if (perServing == null) return serves;
  return '$serves · ${formatKcal(perServing.kcal)} kcal · '
      '${formatGrams(perServing.protein)} g protein';
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
              // E2: the two doors that make a recipe, on the row that knows
              // where the recipe goes. `Unsectioned` gets one too — it has no
              // `⋯`, and it is the door for "this book, no section".
              _SectionAddMenu(book: book, section: section),
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
            for (final r in _recipes)
              _RecipeRow(recipe: r, bookId: book.id, sectionId: section?.id),
        ],
      ),
    );
  }
}

/// The `＋` on a section label — the header menu's wording, on a row that knows
/// its book and its section.
///
/// The header `＋` could only ever promise "a recipe, somewhere"; this one
/// carries `?book=&section=` so the editor opens already filed. `section` is
/// null on the synthetic Unsectioned bucket, which files into the book alone.
class _SectionAddMenu extends StatelessWidget {
  const _SectionAddMenu({required this.book, this.section});

  final Book book;
  final BookSection? section;

  /// `/recipes/new` and `/import` take the same two parameters, so the door
  /// that opens is the only thing that differs between the items.
  String _route(String path) => Uri(
    path: path,
    queryParameters: {
      'book': book.id,
      if (section != null) 'section': section!.id,
    },
  ).toString();

  @override
  Widget build(BuildContext context) {
    return FPopoverMenu(
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.cookingPot),
              title: const Text('New recipe'),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce(_route('/recipes/new'));
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.download),
              title: const Text('Import a recipe'),
              onPress: () {
                unawaited(controller.hide());
                context.pushOnce(_route('/import'));
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.toggle,
        child: const Padding(
          // The touch target the glyph does not have on its own, on a row
          // whose other control is a `⋯` of the same weight.
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(FLucideIcons.plus, size: 15, color: AnsiColors.herb),
        ),
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
                // As for the book rename: the keyboard can unmount this row.
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final host = hostContextOf(context);
                final name = await promptForText(
                  context,
                  title: 'Rename section',
                  hint: 'Section name',
                  initial: section.name,
                  confirm: 'Rename',
                  clean: NameKind.title,
                );
                if (name == null || name.trim().isEmpty) return;
                await container.write(
                  host,
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
      builder: (context, controller, _) =>
          AnsiMoreTrigger(onTap: controller.toggle),
    );
  }
}

/// One recipe: the title on its own line, then [recipeStatsLine] under it, with
/// the ★ and the `⋯` in the corner.
///
/// The star REPORTS ONLY (D6). [RecipeSummary.favorite] has existed since 0011
/// and the picker has a Favorites tab, so a library that cannot show a star
/// makes the recipe page's star feel like it went nowhere — but toggling stays
/// on the recipe page, and this row keeps its single tap target. Absent when
/// false, never a hollow outline on every line: the stub badge's rule.
///
/// **The macro badge this row once refused is now its second line, and the
/// refusal is superseded.** What was refused was a *badge on every row* — "on
/// honest numbers most rows would show a number nobody asked for, or an
/// `incomplete` nag". A second line that simply says less when it knows less is
/// a different object: it never nags, and it buys the title the whole first
/// line back, which is what the number was costing. See [recipeStatsLine].
///
/// Still refused: a "keeps 4 d" chip — shelf life is a *planning* fact, which
/// is why the picker row carries it and a browsing row doesn't.
///
/// No `›`: the whole row was already the door, and the chevron was competing
/// with the `⋯` for the same corner.
///
/// [filing] is set only on a search result, where the tree that would have said
/// where this lives is not on screen.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    this.filing,
    this.bookId,
    this.sectionId,
  });

  final RecipeSummary recipe;
  final Filing? filing;

  /// Where this row is filed, when the tree knows — the shelf "Move to…"
  /// marks as `here now` and refuses to move to. A search result carries the
  /// filing's NAMES but not its ids, so both are null there and every shelf
  /// is offered.
  final String? bookId;
  final String? sectionId;

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
                  const SizedBox(height: 2),
                  Text(
                    recipeStatsLine(recipe),
                    style: ansiMono(size: 10, color: AnsiColors.muted),
                  ),
                ],
              ),
            ),
            if (recipe.favorite) ...[
              const Icon(FLucideIcons.star, size: 13, color: AnsiColors.aging),
              const SizedBox(width: 6),
            ],
            _RecipeRowMenu(
              recipe: recipe,
              bookId: bookId,
              sectionId: sectionId,
            ),
          ],
        ),
      ),
    );
  }
}

/// The recipe row's own `⋯`, rather than a long-press nobody finds.
///
/// The ★ only REPORTS on the row and the toggle lives in here, one deliberate
/// tap away — so the row's own tap means exactly one thing, open the recipe.
class _RecipeRowMenu extends ConsumerWidget {
  const _RecipeRowMenu({
    required this.recipe,
    required this.bookId,
    required this.sectionId,
  });

  final RecipeSummary recipe;
  final String? bookId;
  final String? sectionId;

  Future<void> _move(BuildContext context, WidgetRef ref) async {
    // The row can be unmounted under the sheet (a fold, or a sync landing), so
    // the write goes through handles captured before the await.
    final container = ProviderScope.containerOf(context, listen: false);
    final host = hostContextOf(context);
    final books = ref.read(libraryProvider).asData?.value ?? const [];
    if (books.isEmpty) return;

    final target = await showRecipeMoveSheet(
      // The host outlives the row — see [hostContextOf].
      // ignore: use_build_context_synchronously
      host.context,
      title: recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
      books: books,
      currentBookId: bookId,
      currentSectionId: sectionId,
    );
    if (target == null) return;
    await container.write(
      host,
      'move that recipe',
      () => container
          .read(recipeRepositoryProvider)
          .setFiling(recipe.id, target.bookId, target.sectionId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FPopoverMenu(
      menuBuilder: (_, controller, _) => [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.arrowRight),
              title: const Text('Move to…'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(_move(context, ref));
              },
            ),
            FItem(
              prefix: Icon(
                recipe.favorite ? FLucideIcons.starOff : FLucideIcons.star,
              ),
              title: Text(recipe.favorite ? 'Unfavorite' : 'Favorite'),
              onPress: () {
                unawaited(controller.hide());
                unawaited(
                  ref.write(
                    context,
                    recipe.favorite ? 'unfavourite it' : 'favourite it',
                    () => ref
                        .read(recipeRepositoryProvider)
                        .setFavorite(recipe.id, !recipe.favorite),
                  ),
                );
              },
            ),
          ],
        ),
      ],
      builder: (context, controller, _) => AnsiMoreTrigger.inline(
        onTap: controller.toggle,
        color: AnsiColors.muted,
      ),
    );
  }
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
