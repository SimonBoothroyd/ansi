/// The step card's text controller — it paints the chips (0022 D1).
///
/// A chip is a **styled range over real text**, not a widget in the field. The
/// draft's span table says which characters are chips; `buildTextSpan` gives
/// those runs the herb skin (an ingredient) or the outlined mono skin (a
/// timer), and everything else stays ordinary prose. Caret, selection, IME,
/// autocorrect and backspace therefore behave exactly as in any text field,
/// because nothing exotic lives in `value.text`.
///
/// **Not `WidgetSpan`.** Flutter renders inline widgets inside an editable only
/// when each span owns exactly one U+FFFC character; a mismatch is a framework
/// assertion, the placeholder leaks into every string read back, and backspace
/// across a span differs by platform. The real pills live in the card's
/// "Reads as" preview, which is the shipped `MethodStepText`.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../domain/method_draft.dart';

class MethodSpanController extends TextEditingController {
  MethodSpanController(this._draft) : super(text: _draft.text);

  MethodDraftStep _draft;

  MethodDraftStep get draft => _draft;

  /// Re-seats the controller on [next].
  ///
  /// A no-op when nothing moved — the notifier rebuilds the whole form on
  /// every keystroke, and Forui registers its `onChange` as a plain listener,
  /// so an unconditional `notifyListeners` here would round-trip forever.
  void sync(MethodDraftStep next) {
    if (next == _draft) return;
    final textChanged = next.text != _draft.text;
    _draft = next;
    if (!textChanged) {
      // Only the spans moved (a chip was made, renamed or removed): repaint.
      notifyListeners();
      return;
    }
    // The text was changed from outside the field (a sheet, a relabel). Put
    // the caret where the edit left off rather than at the start.
    final offset = _carryCaret(next.text);
    value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  int _carryCaret(String text) {
    final current = selection.baseOffset;
    if (current < 0) return text.length;
    return current.clamp(0, text.length);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    // The signature is TextEditingController's, not ours.
    // ignore: always_put_required_named_parameters_first
    required bool withComposing,
  }) {
    // Mid-keystroke the field's text is ahead of the draft for one frame;
    // painting stale ranges over new characters would flicker a chip onto the
    // wrong word, so fall back to plain prose until sync catches up.
    if (text != _draft.text || _draft.spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final span in _draft.spans) {
      if (span.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, span.start)));
      }
      children.add(
        TextSpan(
          text: text.substring(span.start, span.end),
          style: switch (span) {
            RefSpan() => chipTextStyle,
            TimerSpan() => timerTextStyle,
          },
        ),
      );
      cursor = span.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }
}

/// The herb skin an ingredient chip wears inside the field — the same herb
/// pair `MethodChip` paints as a pill on the recipe page.
const chipTextStyle = TextStyle(
  backgroundColor: AnsiColors.herbSoft,
  color: AnsiColors.herbDeep,
  fontWeight: FontWeight.w600,
);

/// The timer skin: the paper pill's OUTLINE, drawn as a stroked text
/// background because a `TextStyle` carries one `Paint` and the outline is
/// what distinguishes a timer from an ingredient at a glance.
final timerTextStyle = ansiMonoInherit(size: 14).copyWith(
  color: AnsiColors.ink,
  background: Paint()
    ..color = AnsiColors.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1,
);
