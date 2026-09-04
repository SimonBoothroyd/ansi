/// "Move them to…" — the door the delete refusal opens.
///
/// Without it the refusal is a wall in front of the one action that would
/// clear it. Picking a target says what it will do before it does it, because
/// the move also un-files every recipe: sections belong to the book they were
/// named in, so nothing may be silently re-filed under a label from another
/// shelf.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../../../shared/ansi_modals.dart';
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
    // The root navigator, not the tab shell's branch navigator: a sheet that
    // stops at the branch bounds leaves the nav bar lit and tappable beside it.
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

  String get _plural => widget.moving == 1 ? 'recipe' : 'recipes';

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return AnsiSheetShell(
      title: 'Move them to…',
      subtitle: '${widget.moving} $_plural from “${widget.from.name}”',
      children: [
        const SizedBox(height: 14),
        for (final book in widget.candidates)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _target = book),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AnsiColors.surface,
                border: Border.all(
                  color: book.id == _target?.id
                      ? AnsiColors.herb
                      : AnsiColors.line,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(book.name, style: ansiSerif(size: 17))),
                  if (book.id == _target?.id)
                    const Icon(
                      FLucideIcons.check,
                      size: 16,
                      color: AnsiColors.herb,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 6),
        // Honest, one sentence, before the tap — never a silent data shuffle.
        Text(
          target == null
              ? 'Pick a shelf. Their sections stay behind.'
              : '${widget.moving} $_plural will move to '
                    '“${target.name}”, unsectioned.',
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
