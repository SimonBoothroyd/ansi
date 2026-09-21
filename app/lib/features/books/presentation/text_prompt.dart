/// A small single-field prompt dialog used across the Library (name a book,
/// add or rename a section). Resolves to the entered text, or null if closed.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/theme/ansi_theme.dart';
import '../../../shared/ansi_modals.dart';

/// Prompts for one line of text.
///
/// [clean] is the kind of name being typed; confirming is where a book or
/// section name gets [cleanName]ed. Without it the text is returned verbatim.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirm,
  String initial = '',
  NameKind? clean,
}) {
  return showAnsiDialog<String>(
    context: context,
    builder: (context, style, animation) => _TextPromptDialog(
      title: title,
      hint: hint,
      confirm: confirm,
      initial: initial,
      clean: clean,
      animation: animation,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.confirm,
    required this.initial,
    required this.clean,
    required this.animation,
  });

  final String title;
  final String hint;
  final String confirm;
  final String initial;
  final NameKind? clean;
  final Animation<double> animation;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late String _value = widget.initial;

  void _submit() {
    final kind = widget.clean;
    Navigator.of(context).pop(kind == null ? _value : cleanName(_value, kind));
  }

  @override
  Widget build(BuildContext context) {
    return FDialog(
      animation: widget.animation,
      title: Text(widget.title, style: ansiSerif(size: AnsiType.heading)),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: FTextField(
          autofocus: true,
          hint: widget.hint,
          control: FTextFieldControl.managed(
            initial: TextEditingValue(text: widget.initial),
            onChange: (v) => _value = v.text,
          ),
          onSubmit: (_) => _submit(),
        ),
      ),
      actions: [
        FButton(onPress: _submit, child: Text(widget.confirm)),
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
