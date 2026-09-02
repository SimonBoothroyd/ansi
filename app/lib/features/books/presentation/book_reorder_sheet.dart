/// "Reorder books" — the whole shelf's order in one place (Library v2 / D1).
///
/// Deliberately the same clunky Move up / Move down the sections already ship
/// (tracker `books/ui`, 2026-08-26): books do not get drag-and-drop while
/// sections still lack it. When Forui exposes a drag handle, both convert in
/// one slice. The book `⋯` offers the same two moves one book at a time; this
/// is that operation surfaced once, for the list.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../data/book_providers.dart';
import 'book_view_models.dart';

Future<void> showBookReorderSheet(BuildContext context) {
  return showFSheet<void>(
    context: context,
    // The root navigator, not the tab shell's branch navigator: a sheet that
    // stops at the branch bounds leaves the nav bar lit and tappable beside it.
    useRootNavigator: true,
    side: FLayout.btt,
    mainAxisMaxRatio: null,
    useSafeArea: true,
    builder: (_) => const _BookReorderSheet(),
  );
}

class _BookReorderSheet extends ConsumerWidget {
  const _BookReorderSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(libraryProvider).asData?.value ?? const [];

    // Persist the whole order rather than a swap: `reorderBooks` writes
    // contiguous positions, so a list that arrived with gaps comes out clean.
    Future<void> move(int from, int delta) {
      final to = from + delta;
      if (to < 0 || to >= books.length) return Future.value();
      final ids = books.map((b) => b.id).toList();
      final id = ids.removeAt(from);
      ids.insert(to, id);
      return ref.read(bookRepositoryProvider).reorderBooks(ids);
    }

    return Container(
      decoration: const BoxDecoration(
        color: AnsiColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AnsiColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(FLucideIcons.x, size: 22),
              ),
              Expanded(
                child: Text(
                  'Reorder books',
                  textAlign: TextAlign.center,
                  style: ansiSerif(size: 20),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
          const SizedBox(height: 16),
          for (final (i, book) in books.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(book.name, style: ansiSerif(size: 17))),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: i == 0 ? null : () => move(i, -1),
                    child: const Icon(FLucideIcons.arrowUp, size: 18),
                  ),
                  FButton.icon(
                    variant: FButtonVariant.ghost,
                    onPress: i == books.length - 1 ? null : () => move(i, 1),
                    child: const Icon(FLucideIcons.arrowDown, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
