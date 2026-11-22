/// Where a method uses an ingredient, in the recipe's own words. Pure Dart.
///
/// Read off the chips, which name their lines by id: nothing matches text
/// (ADR-0004), so a line no chip names has no use to quote.
library;

import 'method_step.dart';
import 'recipe.dart';

/// One step's use of an ingredient: the step's number, and the words around
/// the ingredient's `word`. An end that was cut says so with an ellipsis.
typedef StepUse = ({int step, String before, String word, String after});

/// The fewest words that say what is done with an ingredient. A shorter run
/// between two chips (`, ` · ` and `) is a list, and is quoted with the rest
/// of it.
const _clauseWords = 3;

/// The first use in each step of any of [lineIds], in method order.
///
/// A quote is the sentence the chip sits in, cut back to the ingredient's own
/// clause: `…and scatter with coriander.` from a sentence that squeezes a
/// lime first. A list is never cut, since `, garlic` alone says nothing.
List<StepUse> stepUsesOf(
  List<MethodStep> steps,
  Set<String> lineIds, {
  required Map<String, LineItem> lineById,
}) => [
  for (final (i, step) in steps.indexed)
    if (_quote(foldMethod(step, lineById: lineById), lineIds) case (
      :final before,
      :final word,
      :final after,
    ))
      (step: i + 1, before: before, word: word, after: after),
];

({String before, String word, String after})? _quote(
  List<MethodSpan> spans,
  Set<String> lineIds,
) {
  final at = spans.indexWhere(
    (s) => s is MethodChipSpan && s.lineIds.any(lineIds.contains),
  );
  if (at < 0) return null;

  var before = '';
  var cutBefore = false;
  var clause = '';
  for (var i = at - 1; i >= 0; i--) {
    final span = spans[i];
    if (span is MethodChipSpan && _wordCount(clause) >= _clauseWords) {
      cutBefore = true;
      break;
    }
    final text = _textOf(span);
    final ends = span is MethodTextSpan ? _sentenceEnd.allMatches(text) : null;
    if (ends != null && ends.isNotEmpty) {
      before = '${text.substring(ends.last.end)}$before';
      break;
    }
    before = '$text$before';
    clause = span is MethodChipSpan ? '' : '$text$clause';
  }

  final afterWords = StringBuffer();
  for (var i = at + 1; i < spans.length; i++) {
    final span = spans[i];
    final text = _textOf(span);
    final end = span is MethodTextSpan ? _sentenceEnd.firstMatch(text) : null;
    if (end != null) {
      afterWords.write(text.substring(0, end.start + 1));
      break;
    }
    afterWords.write(text);
  }
  var after = afterWords.toString();
  // The next ingredient's own clause is not this one's: cut at this word.
  final next = StringBuffer();
  for (var i = at + 1; i < spans.length; i++) {
    final span = spans[i];
    if (span is MethodChipSpan) {
      final between = next.toString();
      if (_wordCount(between) >= _clauseWords &&
          !_sentenceEnd.hasMatch(between)) {
        after = '…';
        break;
      }
      next.clear();
      continue;
    }
    next.write(_textOf(span));
    if (_sentenceEnd.hasMatch(next.toString())) break;
  }

  return (
    before: cutBefore ? '…${before.trimLeft()}' : before.trimLeft(),
    word: _textOf(spans[at]),
    after: after.trimRight(),
  );
}

/// A mark that ends a sentence: not the point in `1.5`.
final _sentenceEnd = RegExp(r'[.!?](?=\s|$)');

int _wordCount(String text) => RegExp('[A-Za-zÀ-ÿ]+').allMatches(text).length;

String _textOf(MethodSpan span) => switch (span) {
  MethodTextSpan(:final text) => text,
  MethodTimerSpan(:final text) => text,
  MethodAmountSpan(:final text) => text,
  MethodChipSpan(:final label, :final constituents) =>
    label.isNotEmpty ? label : constituents.join(', '),
};
