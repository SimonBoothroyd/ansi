/// The grammar of a book's contents — its `⋯`, its sections, and the recipe
/// rows filed under them.
///
/// Three surfaces draw the same book: the Library's card on a phone, the
/// ledger's heading row and lines on a desk, and the book page either of them
/// opens. They share these widgets rather than each keeping a copy of the menu,
/// the count line and the row, so an item added to a menu here is offered at
/// every door and none of them can drift.
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

/// The book header's `⋯` — [SectionMenu]'s menu one level up (D4).
///
/// Same [FPopoverMenu], same items in the same order, so nothing new is
/// learned. Reorder is deliberately the sections' clunky Move up / Move down:
/// books do not get drag-and-drop while sections still lack it.
///
/// The menu is one object with three triggers, because a book is offered from
/// three places: the card's herb band, where the glyph is drawn in the surface
/// ink over the fill; the book page's own header bar, where it is the
/// scaffold's trailing action beside the back chevron; and the ledger's heading
/// row, where it is the bare glyph at the end of the counts column. Only the
/// trigger differs — the items, their order and what each one writes are the
/// same, which is the whole reason there is one widget.
class BookMenu extends ConsumerWidget {
  const BookMenu({required this.book, required this.books, super.key})
    : _trigger = _Trigger.band;

  /// The `⋯` as a page header's trailing action, for the book's own page.
  const BookMenu.headerBar({required this.book, required this.books, super.key})
    : _trigger = _Trigger.headerBar;

  /// The bare `⋯`, for a heading row that ends in a column of numbers and has
  /// no room for a button's own padding.
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

/// Where a [BookMenu]'s `⋯` is hung — the only thing that differs between the
/// three doors onto one menu.
enum _Trigger { band, headerBar, inline }

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

/// What a section says it holds — `4 recipes`, or `no recipes yet` on one
/// nobody has filed into.
///
/// [bookCountLine]'s grammar one level down, and for the same reason: a zero
/// that renders looks like a bug. It is the fact that lets a section label sit
/// in the ledger's own counts column beside the book's.
String sectionCountLine(int count) =>
    count == 0 ? 'no recipes yet' : '$count ${plural(count, 'recipe')}';

/// The voice a section label wears wherever it is drawn — italic Spectral,
/// herb-deep for a name somebody typed and muted for the synthetic
/// `Unsectioned` bucket, which is a bucket and not a name.
///
/// One style from one place, because three surfaces set it: the phone's block,
/// the book page's, and the ledger's heading line. A section that read as a
/// different kind of thing on a desk would be the tree relabelled.
TextStyle ansiSectionLabel({required bool named}) => ansiSerif(
  size: 14,
  color: named ? AnsiColors.herbDeep : AnsiColors.muted,
  weight: FontWeight.w400,
).copyWith(fontStyle: FontStyle.italic);

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
              // E2: the two doors that make a recipe, on the row that knows
              // where the recipe goes. `Unsectioned` gets one too — it has no
              // `⋯`, and it is the door for "this book, no section".
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

/// One section as a **ledger heading line**: its name in the same italic the
/// card's block sets, a dotted leader into the counts column, what it holds,
/// and the two controls the phone's label carries — the `＋` that files a
/// recipe into this section and the section's own `⋯`.
///
/// [BookSectionBlock] is a *block*: a hairline, a label, and the rows inside
/// it. This is one line, because the ledger lists every section of every book
/// in one long list and each recipe under it is a line of its own — so a block
/// would be a shrink-wrapped list inside a list. Same label, same menus, same
/// order; only the container is gone.
///
/// [section] is null for the synthetic `Unsectioned` bucket, which comes last
/// and carries no `⋯`: there is nothing to rename, reorder or delete about a
/// bucket, exactly as on the card.
class BookSectionLine extends StatelessWidget {
  const BookSectionLine({
    required this.book,
    required this.count,
    this.section,
    super.key,
  });

  final Book book;
  final BookSection? section;

  /// How many recipes are filed under it — the fact that puts this label in the
  /// same right-hand column as the book's own count line.
  final int count;

  /// The widest a section name is set before it gives way, as a book's name and
  /// a recipe's title are: the count is a fact, the name is a label.
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

/// The `＋` on a section label — the header menu's wording, on a row that knows
/// its book and its section.
///
/// The header `＋` could only ever promise "a recipe, somewhere"; this one
/// carries `?book=&section=` so the editor opens already filed. `section` is
/// null on the synthetic Unsectioned bucket, which files into the book alone.
class SectionAddMenu extends StatelessWidget {
  const SectionAddMenu({required this.book, this.section, super.key});

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
      builder: (context, controller, _) => AnsiTap(
        onTap: controller.toggle,
        semanticsLabel: 'File a recipe here',
        color: AnsiColors.herb,
        // The touch target the glyph does not have on its own, on a row
        // whose other control is a `⋯` of the same weight.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: const Icon(FLucideIcons.plus, size: 15),
      ),
    );
  }
}

class SectionMenu extends ConsumerWidget {
  const SectionMenu({required this.book, required this.section, super.key})
    : _inline = false;

  /// The bare `⋯`, for the ledger's section line — which ends in a column of
  /// numbers, a `＋` and this, and has no room for a button's own padding. The
  /// menu and its items are the phone's, exactly as [BookMenu.inline] is.
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
///
/// **[LibraryRecipeRow.ledger] is the same row set as one line**, for the
/// Library's wide body: the title, a dotted leader, and [recipeStatsLine] in
/// the ledger's own right-hand column, with the ★ and the `⋯` after it. It
/// does not *drop* the second line — it sets it — which is the difference
/// between this and the tile that was refused for listing bare titles. Same
/// menu, same star rule, same single tap onto the recipe.
class LibraryRecipeRow extends StatelessWidget {
  const LibraryRecipeRow({
    required this.recipe,
    this.filing,
    this.bookId,
    this.sectionId,
    super.key,
  }) : _ledger = false;

  /// The one-line form, for the ledger.
  ///
  /// No [filing]: a ledger line is drawn under the book it is filed in, so the
  /// line that says where it lives would be repeating the heading above it.
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

  /// The widest a title is set before it gives way — the leader may shrink to a
  /// stub, but the stats are a whole fact and are never half-printed.
  static const double titleMax = 460;

  String get _title => recipe.title.isEmpty ? 'Untitled recipe' : recipe.title;

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
      child: _ledger ? _line() : _stack(filing),
    );
  }

  /// The phone's row: the title over its own second line, the ★ and the `⋯`.
  Widget _stack(Filing? filing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_title, style: ansiSerif(size: 17)),
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

  /// The ledger's line: the same facts, set across one line into the column of
  /// numbers the whole body is ruled to.
  ///
  /// The title is the cell that gives way — capped at [titleMax] and clipped —
  /// because a stats line half-printed is a wrong number, and a title clipped
  /// is a title you still recognise.
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
            style: ansiSerif(size: 15, weight: FontWeight.w400),
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
