/// The step card's text controller, which paints the chips.
///
/// A chip is a styled range over real text, not a widget: the draft's span
/// table says which characters are chips and `buildTextSpan` skins them, so
/// caret, selection, IME and backspace behave as in any field. Not
/// [WidgetSpan]: an editable renders inline widgets only when each span owns
/// exactly one U+FFFC, the placeholder leaks into strings read back, and
/// backspace across a span differs by platform.
library;

import 'package:flutter/widgets.dart';

import '../../../core/theme/ansi_theme.dart';
import '../../../core/theme/ansi_tokens.dart';
import '../domain/method_draft.dart';

class MethodSpanController extends TextEditingController {
  MethodSpanController(this._draft, {this.ringsCaretChip = false})
    : super(text: _draft.text);

  MethodDraftStep _draft;

  /// Whether the chip under the caret wears a ring (the wide editor). Not
  /// final: the layout can change under a mounted card, and re-making the
  /// controller would drop the caret.
  bool ringsCaretChip;

  MethodDraftStep get draft => _draft;

  /// True while [sync] is pushing text into the field; the host must ignore the
  /// `onChange` it hears then.
  ///
  /// Forui registers `onChange` as a plain controller listener, so [sync]'s
  /// assignment comes back to the host as an edit nobody typed, and `applyEdit`
  /// would drop every span that edit overlaps, including a chip being renamed.
  bool get isSyncing => _syncing;
  bool _syncing = false;

  /// Re-seats the controller on [next]. A no-op when nothing moved: the form
  /// rebuilds on every keystroke, and an unconditional [notifyListeners] would
  /// loop through Forui's `onChange`.
  void sync(MethodDraftStep next) {
    if (next == _draft) return;
    final textChanged = next.text != _draft.text;
    _draft = next;
    _syncing = true;
    try {
      if (!textChanged) {
        // Only the spans moved (a chip was made, renamed or removed): repaint.
        notifyListeners();
        return;
      }
      // Text rewritten from outside the field: keep the caret where the edit
      // left off.
      final offset = _carryCaret(next.text);
      value = TextEditingValue(
        text: next.text,
        selection: TextSelection.collapsed(offset: offset),
      );
    } finally {
      _syncing = false;
    }
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
    // Mid-keystroke the text is a frame ahead of the draft; paint plain prose
    // until sync catches up rather than stale ranges.
    if (text != _draft.text || _draft.spans.isEmpty) {
      return TextSpan(text: text, style: style);
    }
    final ringed = ringsCaretChip ? _caretSpan() : null;
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final (i, span) in _draft.spans.indexed) {
      if (span.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, span.start)));
      }
      final skin = switch (span) {
        RefSpan() => chipTextStyle,
        TimerSpan() => timerTextStyle,
      };
      children.add(
        TextSpan(
          text: text.substring(span.start, span.end),
          style: i == ringed ? ringedChipStyle(skin) : skin,
        ),
      );
      cursor = span.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    return TextSpan(style: style, children: children);
  }

  /// The span the caret sits in. A caret at a chip's closing edge belongs to
  /// the chip when the affinity is upstream. Null while a selection is open.
  int? _caretSpan() {
    final selection = this.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final offset = selection.baseOffset;
    return spanAt(_draft, offset) ??
        (selection.affinity == TextAffinity.upstream
            ? spanEndingAt(_draft, offset)
            : null);
  }
}

/// An ingredient chip's skin inside the field, in `MethodChip`'s herb pair.
const chipTextStyle = TextStyle(
  backgroundColor: AnsiColors.herbSoft,
  color: AnsiColors.herbDeep,
  fontWeight: FontWeight.w600,
);

/// The ring on the chip under the caret: a herb underline over its skin. A text
/// run carries one background paint, so no outline is drawn.
TextStyle ringedChipStyle(TextStyle skin) => skin.copyWith(
  decoration: TextDecoration.underline,
  decorationColor: AnsiColors.herb,
  decorationThickness: 1.5,
);

/// The timer skin: an outline drawn as a stroked text background, since a
/// [TextStyle] carries one [Paint].
final timerTextStyle = ansiMonoInherit(size: 14).copyWith(
  color: AnsiColors.ink,
  background: Paint()
    ..color = AnsiColors.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1,
);
