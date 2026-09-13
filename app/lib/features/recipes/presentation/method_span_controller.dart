/// The step card's text controller — it paints the chips (0022 D1).
///
/// A chip is a **styled range over real text**, not a widget in the field. The
/// draft's span table says which characters are chips; `buildTextSpan` gives
/// those runs the herb skin (an ingredient) or the outlined mono skin (a
/// timer), and everything else stays ordinary prose. Caret, selection, IME,
/// autocorrect and backspace therefore behave exactly as in any text field,
/// because nothing exotic lives in `value.text`.
///
/// **Not [WidgetSpan].** Flutter renders inline widgets inside an editable only
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
  MethodSpanController(this._draft, {this.ringsCaretChip = false})
    : super(text: _draft.text);

  MethodDraftStep _draft;

  /// Whether the chip the caret is inside wears a ring — the wide editor's
  /// other half of the lit lines, so the pair reads from either end. Off on
  /// the phone, where the line it points at is a scroll away and a ring would
  /// only mark the word under your own finger.
  ///
  /// Not final: the band can change under a mounted card (a window resized),
  /// and re-making the controller for that would drop the caret.
  bool ringsCaretChip;

  MethodDraftStep get draft => _draft;

  /// True while [sync] is pushing text INTO the field — the host must ignore
  /// the `onChange` it hears in that window.
  ///
  /// Forui registers a managed field's `onChange` as **a plain controller
  /// listener**, so the assignment in [sync] comes straight back to the host
  /// as `editStep(id, text)` — an edit nobody typed. `applyEdit` then diffs
  /// that text against the draft it can see and drops every span overlapping
  /// the changed range, so the sanctioned rename path would destroy what it
  /// renames: the chip goes and its word is left sitting as prose. The loop
  /// is closed here, at the one place that knows it wrote the text itself,
  /// rather than in `applyEdit` — whose rule is right: typing over a chip's
  /// own characters in the sentence really does end it.
  bool get isSyncing => _syncing;
  bool _syncing = false;

  /// Re-seats the controller on [next].
  ///
  /// A no-op when nothing moved — the notifier rebuilds the whole form on
  /// every keystroke, and Forui registers its `onChange` as a plain listener,
  /// so an unconditional [notifyListeners] here would round-trip forever.
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
      // Something outside the field rewrote the text (a sheet, a relabel). Put
      // the caret where the edit left off rather than at the start.
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
    // Mid-keystroke the field's text is ahead of the draft for one frame;
    // painting stale ranges over new characters would flicker a chip onto the
    // wrong word, so fall back to plain prose until sync catches up.
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

  /// The span the caret is sitting in, by the card's own rule: a caret at a
  /// chip's closing edge belongs to the chip when the affinity is upstream.
  /// Null while a selection is open — a drag across a sentence is not a caret
  /// inside one word.
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

/// The herb skin an ingredient chip wears inside the field — the same herb
/// pair `MethodChip` paints as a pill on the recipe page.
const chipTextStyle = TextStyle(
  backgroundColor: AnsiColors.herbSoft,
  color: AnsiColors.herbDeep,
  fontWeight: FontWeight.w600,
);

/// The ring the chip under the caret wears in the wide editor, over whichever
/// skin it already has.
///
/// The board draws it as an inset herb rule with a hairline round the run. A
/// text run carries one background paint, so the rule is what is drawn and the
/// hairline is not — an underline in the herb the chip is already made of,
/// which is the half that reads at a glance anyway.
TextStyle ringedChipStyle(TextStyle skin) => skin.copyWith(
  decoration: TextDecoration.underline,
  decorationColor: AnsiColors.herb,
  decorationThickness: 1.5,
);

/// The timer skin: the paper pill's OUTLINE, drawn as a stroked text
/// background because a [TextStyle] carries one [Paint] and the outline is
/// what distinguishes a timer from an ingredient at a glance.
final timerTextStyle = ansiMonoInherit(size: 14).copyWith(
  color: AnsiColors.ink,
  background: Paint()
    ..color = AnsiColors.line
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1,
);
