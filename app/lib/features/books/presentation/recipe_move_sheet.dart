/// "Move to…": re-filing one recipe, from the Library.
///
/// Unlike the bulk `moveBookContents`, a single recipe can land in a section,
/// because the person picks it. A book chosen without a section means
/// unsectioned.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_select_row.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../domain/book.dart';

/// A shelf a recipe can be moved to, and its spoken label.
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
    // The root navigator: a sheet on the branch navigator leaves the nav bar
    // tappable beside it.
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
    return AnsiSheetShell(
      title: 'Move to…',
      subtitle: '“${widget.title}”',
      children: [
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
                      style: ansiSerif(
                        size: AnsiType.small,
                        color: AnsiColors.herbDeep,
                      ),
                    ),
                  ),
                  // The bucket first: a book with no sections still has one
                  // place to land.
                  AnsiSelectRow(
                    label: 'Unsectioned',
                    selected:
                        target?.bookId == book.id && target?.sectionId == null,
                    note: _isHere(book.id, null) ? 'here now' : null,
                    enabled: !_isHere(book.id, null),
                    onTap: () => setState(
                      () => _target = (
                        bookId: book.id,
                        sectionId: null,
                        label: '${book.name} · Unsectioned',
                      ),
                    ),
                  ),
                  for (final section in book.sections)
                    AnsiSelectRow(
                      label: section.name,
                      selected: target?.sectionId == section.id,
                      note: _isHere(book.id, section.id) ? 'here now' : null,
                      enabled: !_isHere(book.id, section.id),
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
        // One sentence saying what the tap will do.
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
    );
  }
}
