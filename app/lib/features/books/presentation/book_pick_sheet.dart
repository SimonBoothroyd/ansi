/// "Move them to…": the door the delete refusal opens.
///
/// The sheet says what the move will do first, because it also un-files every
/// recipe: sections belong to the book they were named in.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../core/words.dart';
import '../../../shared/ansi_modals.dart';
import '../../../shared/ansi_select_row.dart';
import '../../../shared/ansi_sheet_shell.dart';
import '../domain/book.dart';

/// Offers [candidates] as the new home for [moving] recipes currently in
/// [from]. Resolves to the chosen book, or null if the sheet was dismissed.
Future<Book?> showBookPickSheet(
  BuildContext context, {
  required int moving,
  required Book from,
  required List<Book> candidates,
}) {
  return showAnsiSheet<Book>(
    context: context,
    // The root navigator: a sheet on the branch navigator leaves the nav bar
    // tappable beside it.
    builder: (_) =>
        _BookPickSheet(moving: moving, from: from, candidates: candidates),
  );
}

class _BookPickSheet extends StatefulWidget {
  const _BookPickSheet({
    required this.moving,
    required this.from,
    required this.candidates,
  });

  final int moving;
  final Book from;
  final List<Book> candidates;

  @override
  State<_BookPickSheet> createState() => _BookPickSheetState();
}

class _BookPickSheetState extends State<_BookPickSheet> {
  Book? _target;

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return AnsiSheetShell(
      title: 'Move them to…',
      subtitle:
          '${widget.moving} ${plural(widget.moving, 'recipe')} '
          'from “${widget.from.name}”',
      children: [
        const SizedBox(height: 14),
        for (final book in widget.candidates)
          AnsiSelectRow(
            label: book.name,
            selected: book.id == _target?.id,
            onTap: () => setState(() => _target = book),
          ),
        const SizedBox(height: 6),
        // One sentence saying what the tap will do.
        Text(
          target == null
              ? 'Pick a shelf. Their sections stay behind.'
              : '${widget.moving} ${plural(widget.moving, 'recipe')} will '
                    'move to “${target.name}”, unsectioned.',
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
