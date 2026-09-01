/// A small dialog to change who's eating a planned meal. Resolves to the chosen
/// member-id set, or null if cancelled.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../domain/planning.dart';
import 'week_widgets.dart';

Future<Set<String>?> showEditEatersDialog(
  BuildContext context, {
  required List<Member> members,
  required Set<String> selected,
}) {
  return showFDialog<Set<String>>(
    context: context,
    builder: (context, style, animation) => _EditEatersDialog(
      members: members,
      initial: selected,
      animation: animation,
    ),
  );
}

class _EditEatersDialog extends StatefulWidget {
  const _EditEatersDialog({
    required this.members,
    required this.initial,
    required this.animation,
  });

  final List<Member> members;
  final Set<String> initial;
  final Animation<double> animation;

  @override
  State<_EditEatersDialog> createState() => _EditEatersDialogState();
}

class _EditEatersDialogState extends State<_EditEatersDialog> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return FDialog(
      animation: widget.animation,
      title: Text("Who's eating", style: ansiSerif(size: 20)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, m) in widget.members.indexed)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _selected.contains(m.id)
                      ? _selected.remove(m.id)
                      : _selected.add(m.id);
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      EaterAvatar(
                        member: m,
                        color: memberColor(i),
                        dimmed: !_selected.contains(m.id),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          m.displayName,
                          style: ansiSerif(
                            size: 16,
                            color: _selected.contains(m.id)
                                ? AnsiColors.ink
                                : AnsiColors.muted,
                          ),
                        ),
                      ),
                      if (_selected.contains(m.id))
                        const Icon(
                          FLucideIcons.check,
                          size: 16,
                          color: AnsiColors.herb,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        FButton(
          onPress: () => Navigator.of(context).pop(_selected),
          child: const Text('Save'),
        ),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
