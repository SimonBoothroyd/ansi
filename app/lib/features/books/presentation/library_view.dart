/// The Library — the app's home screen. Books hold user-named sections, each
/// listing the recipes filed under it (design board: "Books · your own
/// sections, not presets").
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/sync/session.dart';
import '../../../core/theme/mise_theme.dart';
import '../../../core/theme/mise_tokens.dart';
import '../../../shared/dashed_border_box.dart';
import '../../../shared/mise_bottom_nav.dart';
import '../../recipes/domain/recipe.dart';
import '../../recipes/presentation/format.dart';
import '../data/book_providers.dart';
import '../domain/book.dart';
import 'book_view_models.dart';
import 'text_prompt.dart';

class LibraryView extends ConsumerWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryProvider);
    final repo = ref.read(bookRepositoryProvider);

    return FScaffold(
      footer: const MiseBottomNav(current: MiseTab.library),
      header: FHeader.nested(
        title: Text('Library', style: miseHeaderTitle()),
        suffixes: [
          FPopoverMenu(
            menu: [
              FItemGroup(
                children: [
                  FItem(
                    prefix: const Icon(FLucideIcons.cookingPot),
                    title: const Text('New recipe'),
                    onPress: () => context.push('/recipes/new'),
                  ),
                  FItem(
                    prefix: const Icon(FLucideIcons.bookPlus),
                    title: const Text('New book'),
                    onPress: () async {
                      final name = await promptForText(
                        context,
                        title: 'New book',
                        hint: 'e.g. Our Cookbook',
                        confirm: 'Create',
                      );
                      if (name != null && name.trim().isNotEmpty) {
                        await repo.createBook(name);
                      }
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
                      if (await _confirmSignOut(context)) {
                        await ref
                            .read(sessionControllerProvider.notifier)
                            .signOut();
                      }
                    },
                  ),
                ],
              ),
            ],
            builder: (context, controller, _) => FHeaderAction(
              icon: const Icon(FLucideIcons.plus),
              onPress: controller.toggle,
            ),
          ),
        ],
      ),
      child: library.when(
        loading: () => const Center(child: FCircularProgress()),
        error: (e, _) {
          debugPrint('library load failed: $e');
          return Center(
            child: Text(
              'Could not load the library.',
              textAlign: TextAlign.center,
              style: miseMono(size: 13, color: MiseColors.muted),
            ),
          );
        },
        data: (books) => books.isEmpty
            ? const _EmptyState()
            : ListView(
                padding: const EdgeInsets.only(top: 4, bottom: 28),
                children: [for (final b in books) _BookCard(book: b)],
              ),
      ),
    );
  }
}

/// Asks before signing out: sign-out disconnects sync and clears this device's
/// local copy of the household data (it stays on the server).
Future<bool> _confirmSignOut(BuildContext context) async {
  final confirmed = await showFDialog<bool>(
    context: context,
    builder: (context, style, animation) => FDialog(
      animation: animation,
      title: Text('Sign out?', style: miseSerif(size: 20)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'This removes the synced data from this device. It stays in your '
          'household and comes back when you sign in again.',
          style: miseSans(size: 13, color: MiseColors.muted),
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
  const _BookCard({required this.book});

  final Book book;

  int get _recipeCount =>
      book.unsectioned.length +
      book.sections.fold(0, (n, s) => n + s.recipes.length);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookRepositoryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: MiseColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Herb header: book name + recipe count.
                  Container(
                    color: MiseColors.herb,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.name,
                          style: miseSerif(
                            size: 19,
                            color: MiseColors.surface,
                            weight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_recipeCount '
                          '${_recipeCount == 1 ? 'recipe' : 'recipes'}',
                          style: miseMono(
                            size: 10,
                            color: MiseColors.surface,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final section in book.sections)
                    _SectionBlock(book: book, section: section),
                  if (book.unsectioned.isNotEmpty)
                    _SectionBlock(book: book, unsectioned: book.unsectioned),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AddSectionButton(
            onTap: () async {
              final name = await promptForText(
                context,
                title: 'New section',
                hint: 'Name it anything',
                confirm: 'Add',
              );
              if (name != null && name.trim().isNotEmpty) {
                await repo.createSection(book.id, name);
              }
            },
          ),
        ],
      ),
    );
  }
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
        border: Border(top: BorderSide(color: MiseColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _label,
                  style: miseSerif(
                    size: 14,
                    color: section == null
                        ? MiseColors.muted
                        : MiseColors.herbDeep,
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
                style: miseMono(size: 11, color: MiseColors.muted),
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
  Future<void> _move(WidgetRef ref, int delta) {
    final ids = book.sections.map((s) => s.id).toList();
    final from = ids.indexOf(section.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= ids.length) return Future.value();
    ids
      ..removeAt(from)
      ..insert(to, section.id);
    return ref.read(bookRepositoryProvider).reorderSections(book.id, ids);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(bookRepositoryProvider);
    return FPopoverMenu(
      menu: [
        FItemGroup(
          children: [
            FItem(
              prefix: const Icon(FLucideIcons.pencil),
              title: const Text('Rename'),
              onPress: () async {
                final name = await promptForText(
                  context,
                  title: 'Rename section',
                  hint: 'Section name',
                  initial: section.name,
                  confirm: 'Rename',
                );
                if (name != null && name.trim().isNotEmpty) {
                  await repo.renameSection(section.id, name);
                }
              },
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowUp),
              title: const Text('Move up'),
              onPress: () => _move(ref, -1),
            ),
            FItem(
              prefix: const Icon(FLucideIcons.arrowDown),
              title: const Text('Move down'),
              onPress: () => _move(ref, 1),
            ),
            FItem(
              prefix: const Icon(FLucideIcons.trash2),
              title: const Text('Delete'),
              onPress: () => repo.deleteSection(section.id),
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

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.recipe});

  final RecipeSummary recipe;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/recipes/${recipe.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                recipe.title.isEmpty ? 'Untitled recipe' : recipe.title,
                style: miseSerif(size: 17),
              ),
            ),
            Text(
              'serves ${formatQuantity(recipe.servingsBase)}',
              style: miseMono(size: 11, color: MiseColors.muted),
            ),
            const SizedBox(width: 8),
            const Icon(
              FLucideIcons.chevronRight,
              size: 16,
              color: MiseColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSectionButton extends StatelessWidget {
  const _AddSectionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: DashedBorderBox(
        // A real icon, not a "＋" glyph — the bundled fonts lack U+FF0B, so
        // the string form renders as tofu.
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(FLucideIcons.plus, size: 12, color: MiseColors.herb),
            const SizedBox(width: 5),
            Text(
              'new section — name it anything',
              style: miseMono(
                size: 11,
                color: MiseColors.herb,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FLucideIcons.library, size: 44, color: MiseColors.herb),
          const SizedBox(height: 14),
          Text('No books yet', style: miseSerif(size: 22)),
          const SizedBox(height: 6),
          Text(
            'Add one with the + above.',
            style: miseMono(size: 12, color: MiseColors.muted),
          ),
        ],
      ),
    );
  }
}
