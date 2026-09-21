/// A book's contents: its `⋯`, its sections, and the recipe rows under them.
///
/// Shared by the Library card, the ledger and the book page so the menus and
/// count lines cannot drift.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_more_trigger.dart';
import '../../../shared/ansi_tap.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/dotted_leader.dart';
import '../../../shared/format.dart';
import '../../../shared/guarded_navigation.dart';
import '../../../shared/write.dart';
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

/// "New section", from the book `⋯`.
Future<void> promptForNewSection(
  BuildContext context,
  WidgetRef ref,
  String bookId,
) async {
  // The keyboard can unmount the row that opened the prompt, so the write
  // goes through handles captured here (`hostContextOf`), never a `ref` or a
  // `context.mounted` bail after the await.
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

/// The book's `⋯`: [SectionMenu]'s items one level up, reorder included.
///
/// One menu with three triggers: the card's herb band, the book page's
/// header bar, and the ledger's heading row.
class BookMenu extends ConsumerWidget {
  const BookMenu({required this.book, required this.books, super.key})
    : _trigger = _Trigger.band;

  /// The `⋯` as a page header's trailing action, for the book's own page.
  const BookMenu.headerBar({required this.book, required this.books, super.key})
    : _trigger = _Trigger.headerBar;

  /// The bare `⋯`, for a heading row with no room for a button's padding.
  const BookMenu.inline({required this.book, required this.books, super.key})
    : _trigger = _Trigger.inline;

  final Book book;
  final List<Book> books;

  final _Trigger _trigger;

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
                // The keyboard can unmount this row; write through handles
                // that outlive it.
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
      builder: (context, controller, _) => switch (_trigger) {
        _Trigger.headerBar => FHeaderAction(
          icon: const Icon(FLucideIcons.ellipsis),
          onPress: controller.toggle,
        ),
        _Trigger.inline => AnsiMoreTrigger.inline(
          onTap: controller.toggle,
          color: AnsiColors.muted,
        ),
        _Trigger.band => AnsiMoreTrigger(
          onTap: controller.toggle,
          color: AnsiColors.surface,
        ),
      },
    );
  }
}

/// Where a [BookMenu]'s `⋯` is hung.
enum _Trigger { band, headerBar, inline }

/// Deleting a book: refuse with a count and a door, or confirm.
///
/// Never cascades to the recipes. The count is read from the repository at
/// the tap, not from the cached tree.
Future<void> confirmDeleteBook(
  BuildContext context,
  WidgetRef ref,
  Book book,
  List<Book> books,
) async {
  // Read the keep-alive repo, the container and the host before the first
  // await: every branch crosses a dialog, and the row that opened the menu
  // may be gone (`hostContextOf`).
  final repo = ref.read(bookRepositoryProvider);
  final container = ProviderScope.containerOf(context, listen: false);
  final host = hostContextOf(context);

  if (books.length <= 1) {
    // Refuse the last book: `ensureDefaultBook()` would re-mint one on the
    // next launch.
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

/// The first-run shelf: two doors in place, both carrying the book so the
/// recipe files onto this shelf.
class EmptyShelf extends StatelessWidget {
  const EmptyShelf({required this.book, super.key});

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
            style: ansiSerif(size: AnsiType.small, color: AnsiColors.muted),
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

/// What a book says it holds: `42 recipes · 3 sections`.
///
/// An empty shelf says "no recipes yet", never `0 recipes`, and a book with
/// no sections omits that half.
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

/// What a section says it holds: `4 recipes`, or `no recipes yet`.
String sectionCountLine(int count) =>
    count == 0 ? 'no recipes yet' : '$count ${plural(count, 'recipe')}';

/// A section label's style: italic serif, herb-deep for a typed name and
/// muted for the synthetic `Unsectioned` bucket.
TextStyle ansiSectionLabel({required bool named}) => ansiSerif(
  size: AnsiType.small,
  color: named ? AnsiColors.herbDeep : AnsiColors.muted,
  weight: FontWeight.w400,
).copyWith(fontStyle: FontStyle.italic);

/// A recipe row's second line: `serves 4 · 520 kcal · 28 g protein`.
///
/// A recipe with incomplete macros prints the serves and stops: no dash, no
/// badge. [RecipeSummary.macros] is already per-serving.
String recipeStatsLine(RecipeSummary recipe) {
  final serves = 'serves ${formatQuantity(recipe.servingsBase)}';
  final perServing = recipe.macros?.perServing;
  if (perServing == null) return serves;
  return '$serves · ${formatKcal(perServing.kcal)} kcal · '
      '${formatGrams(perServing.protein)} g protein';
}

/// One section (or the synthetic Unsectioned bucket, when [section] is null)
/// and its recipe rows.
class BookSectionBlock extends ConsumerWidget {
  const BookSectionBlock({
    required this.book,
    this.section,
    this.unsectioned = const [],
    super.key,
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
                  style: ansiSectionLabel(named: section != null),
                ),
              ),
              // `Unsectioned` gets the `＋` too: it files into the book alone.
              SectionAddMenu(book: book, section: section),
              if (section != null) SectionMenu(book: book, section: section),
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
              LibraryRecipeRow(
                recipe: r,
                bookId: book.id,
                sectionId: section?.id,
              ),
        ],
      ),
    );
  }
}

/// One section as a ledger heading line: name, dotted leader, count, the
/// `＋` and the section's `⋯`.
///
/// A line rather than a [BookSectionBlock] because the ledger is one flat
/// list. [section] is null for the `Unsectioned` bucket, which has no `⋯`.
class BookSectionLine extends StatelessWidget {
  const BookSectionLine({
    required this.book,
    required this.count,
    this.section,
    super.key,
  });

  final Book book;
  final BookSection? section;

  /// How many recipes are filed under it.
  final int count;

  /// The widest a section name is set before it is clipped.
  static const double nameMax = 400;

  @override
  Widget build(BuildContext context) {
    final section = this.section;
    return Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: nameMax),
          child: Text(
            section?.name ?? 'Unsectioned',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ansiSectionLabel(named: section != null),
          ),
        ),
        const AnsiDottedLeader(),
        Text(
          sectionCountLine(count),
          style: ansiMono(size: 9.5, color: AnsiColors.muted),
        ),
        SectionAddMenu(book: book, section: section),
        if (section != null) SectionMenu.inline(book: book, section: section),
      ],
    );
  }
}

/// The `＋` on a section label. Carries `?book=&section=` so the editor opens
/// already filed; `section` is null on the `Unsectioned` bucket.
class SectionAddMenu extends StatelessWidget {
  const SectionAddMenu({required this.book, this.section, super.key});

  final Book book;
  final BookSection? section;

  /// `/recipes/new` and `/import` take the same two parameters.
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
      builder: (context, controller, _) => AnsiTap(
        onTap: controller.toggle,
        semanticsLabel: 'File a recipe here',
        color: AnsiColors.herb,
        // The touch target the glyph lacks on its own.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: const Icon(FLucideIcons.plus, size: 15),
      ),
    );
  }
}

class SectionMenu extends ConsumerWidget {
  const SectionMenu({required this.book, required this.section, super.key})
    : _inline = false;

  /// The bare `⋯`, for the ledger's section line.
  const SectionMenu.inline({
    required this.book,
    required this.section,
    super.key,
  }) : _inline = true;

  final Book book;
  final BookSection section;

  final bool _inline;

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
      builder: (context, controller, _) => _inline
          ? AnsiMoreTrigger.inline(
              onTap: controller.toggle,
              color: AnsiColors.muted,
            )
          : AnsiMoreTrigger(onTap: controller.toggle),
    );
  }
}

/// One recipe: the title, [recipeStatsLine] under it, and the ★ and `⋯`.
///
/// The star reports only; toggling lives in the `⋯`, so the row's tap only
/// opens the recipe. It is absent when false. [filing] is set only on a
/// search result. [LibraryRecipeRow.ledger] sets the same facts on one line.
class LibraryRecipeRow extends StatelessWidget {
  const LibraryRecipeRow({
    required this.recipe,
    this.filing,
    this.bookId,
    this.sectionId,
    super.key,
  }) : _ledger = false;

  /// The one-line form, for the ledger. No [filing]: the heading above
  /// already says where it lives.
  const LibraryRecipeRow.ledger({
    required this.recipe,
    this.bookId,
    this.sectionId,
    super.key,
  }) : filing = null,
       _ledger = true;

  final RecipeSummary recipe;
  final Filing? filing;

  /// Drawn as one ledger line rather than the phone's two-line row.
  final bool _ledger;

  /// The widest a title is set before it is clipped; the stats never are.
  static const double titleMax = 460;

  String get _title => recipe.title.isEmpty ? 'Untitled recipe' : recipe.title;

  /// Where this row is filed: the shelf "Move to…" marks as `here now`. Null
  /// on a search result, which carries names but not ids.
  final String? bookId;
  final String? sectionId;

  @override
  Widget build(BuildContext context) {
    final filing = this.filing;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushOnce('/recipes/${recipe.id}'),
      child: _ledger ? _line() : _stack(filing),
    );
  }

  /// The phone's two-line row.
  Widget _stack(Filing? filing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: ansiSerif(size: AnsiType.row)),
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
        _RecipeRowMenu(recipe: recipe, bookId: bookId, sectionId: sectionId),
      ],
    ),
  );

  /// The ledger's line. The title is capped at [titleMax] and clipped; the
  /// stats are never half-printed.
  Widget _line() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: titleMax),
          child: Text(
            _title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ansiSerif(size: AnsiType.small, weight: FontWeight.w400),
          ),
        ),
        const AnsiDottedLeader(),
        Text(
          recipeStatsLine(recipe),
          style: ansiMono(size: 10, color: AnsiColors.muted),
        ),
        if (recipe.favorite) ...[
          const SizedBox(width: 7),
          const Icon(FLucideIcons.star, size: 12, color: AnsiColors.aging),
        ],
        _RecipeRowMenu(recipe: recipe, bookId: bookId, sectionId: sectionId),
      ],
    ),
  );
}

/// The recipe row's `⋯`, which holds the ★ toggle.
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
    // The row can be unmounted under the sheet, so capture the handles
    // before the await.
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
