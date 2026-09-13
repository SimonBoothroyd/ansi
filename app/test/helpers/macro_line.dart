/// Finders for the dense macro lines, which are rich text now.
///
/// `197 🔥 · 2P 20F 3C` is a [Text.rich] with the unit glyphs as widget spans,
/// so `find.text` cannot see it. These read the line back as it is SPOKEN —
/// each glyph replaced by the word it carries as its semantic label — which is
/// both what a screen reader hears and what a test wants to assert.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dense macro line that says exactly [text] — `60 kcal · 1P 0F 15C /100 g`.
Finder macroText(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.textSpan != null && spokenText(w.textSpan!) == text,
  description: 'macro line "$text"',
);

/// A dense macro line with [text] somewhere in it.
Finder macroTextContaining(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text && w.textSpan != null && spokenText(w.textSpan!).contains(text),
  description: 'macro line containing "$text"',
);

/// The word an icon stands in for, however it is wrapped — a unit glyph sits
/// inside a paint-only [Transform] so it can be centred on the digits.
String? _iconLabel(Widget widget) => switch (widget) {
  Icon(:final semanticLabel) => semanticLabel,
  SingleChildRenderObjectWidget(child: final child?) => _iconLabel(child),
  _ => null,
};

/// One span tree, flattened: its text, with every icon read out as the word
/// it stands in for.
String spokenText(InlineSpan span) {
  final buffer = StringBuffer();
  span.visitChildren((child) {
    switch (child) {
      case TextSpan(:final text?):
        buffer.write(text);
      case WidgetSpan(:final child):
        buffer.write(_iconLabel(child) ?? '');
      default:
        break;
    }
    return true;
  });
  return buffer.toString();
}
