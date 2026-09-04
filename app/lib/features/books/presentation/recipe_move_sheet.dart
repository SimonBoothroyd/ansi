/// "Move to…" — re-filing ONE recipe, from the Library.
///
/// The act already existed in bulk: the delete refusal's door is
/// `moveBookContents`, every recipe in a book re-filed and announced before it
/// acts. This is that sentence in the singular — and it belongs here rather
/// than in the editor, because re-shelving is a LIBRARY act and the editor is
/// the one screen where the shelves are not visible.
///
/// Unlike the bulk move, a single recipe can land IN a section: nothing is
/// being re-filed under a label from another shelf, because the person is
/// picking the label. Crossing into a book without choosing one of its
/// sections still means unsectioned, for the reason it always has — a section
/// belongs to the book it was named in.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../domain/book.dart';

/// A shelf a recipe can be moved to, and how to say it out loud.
typedef FilingTarget = ({String bookId, String? sectionId, String label});

/// Offers every shelf in [books] as the new home for [title], with the shelf
/// it is on now marked and unselectable. Resolves to the chosen target, or
/// null if the sheet was dismissed.
Future<FilingTarget?> showRecipeMoveSheet(
  BuildContext context, {
  required String title,
  required List<Book> books,
  required String? currentBookId,
  required String? currentSectionId,
}) {
  return showAnsiSheet<FilingTarget>(
    context: context,
    // The root navigator, not the tab shell's branch navigator: a sheet that
    // stops at the branch bounds leaves the nav bar lit and tappable beside it.
    builder: (_) => _RecipeMoveSheet(
      title: title,
      books: books,
      currentBookId: currentBookId,
      currentSectionId: currentSectionId,
    ),
  );
}

class _RecipeMoveSheet extends StatefulWidget {
  const _RecipeMoveSheet({
    required this.title,
    required this.books,
    required this.currentBookId,
    required this.currentSectionId,
  });

  final String title;
  final List<Book> books;
  final String? currentBookId;
  final String? currentSectionId;

  @override
  State<_RecipeMoveSheet> createState() => _RecipeMoveSheetState();
}

class _RecipeMoveSheetState extends State<_RecipeMoveSheet> {
  FilingTarget? _target;

  bool _isHere(String bookId, String? sectionId) =>
      bookId == widget.currentBookId && sectionId == widget.currentSectionId;

  @override
  Widget build(BuildContext context) {
    final target = _target;
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
                  'Move to…',
                  textAlign: TextAlign.center,
                  style: ansiSerif(size: 20),
                ),
              ),
              const SizedBox(width: 22),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '“${widget.title}”',
            textAlign: TextAlign.center,
            style: ansiMono(size: 11, color: AnsiColors.muted),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final book in widget.books) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(
                        book.name,
                        style: ansiSerif(size: 15, color: AnsiColors.herbDeep),
                      ),
                    ),
                    // Every shelf inside the book, the bucket first: a book
                    // with no sections still has exactly one place to land.
                    _ShelfRow(
                      label: 'Unsectioned',
                      selected:
                          target?.bookId == book.id &&
                          target?.sectionId == null,
                      here: _isHere(book.id, null),
                      onTap: () => setState(
                        () => _target = (
                          bookId: book.id,
                          sectionId: null,
                          label: '${book.name} · Unsectioned',
                        ),
                      ),
                    ),
                    for (final section in book.sections)
                      _ShelfRow(
                        label: section.name,
                        selected: target?.sectionId == section.id,
                        here: _isHere(book.id, section.id),
                        onTap: () => setState(
                          () => _target = (
                            bookId: book.id,
                            sectionId: section.id,
                            label: '${book.name} · ${section.name}',
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Honest, one sentence, before the tap — the bulk move's grammar in
          // the singular.
          Text(
            target == null
                ? 'Pick a shelf.'
                : '“${widget.title}” moves to ${target.label}.',
            textAlign: TextAlign.center,
            style: ansiSans(size: 13, color: AnsiColors.muted),
          ),
          const SizedBox(height: 12),
          FButton(
            onPress: target == null
                ? null
                : () => Navigator.of(context).pop(target),
            child: const Text('Move'),
          ),
        ],
      ),
    );
  }
}

/// One shelf. The one the recipe is already on says so and cannot be picked —
/// a "move" that moves nothing is a tap that lies about what it did.
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.label,
    required this.selected,
    required this.here,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool here;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: here ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AnsiColors.surface,
          border: Border.all(
            color: selected ? AnsiColors.herb : AnsiColors.line,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: ansiSerif(
                  size: 15,
                  color: here ? AnsiColors.muted : AnsiColors.ink,
                ),
              ),
            ),
            if (here)
              Text(
                'here now',
                style: ansiMono(size: 10, color: AnsiColors.muted),
              ),
            if (selected)
              const Icon(FLucideIcons.check, size: 16, color: AnsiColors.herb),
          ],
        ),
      ),
    );
  }
}
