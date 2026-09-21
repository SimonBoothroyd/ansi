/// The editor's shape for a tokenized method. Pure Dart.
///
/// A [MethodStep] is a token stream; the editor's document is the sentence it
/// flattens to plus a side table of `(start, end, refs | timer)` spans
/// ([MethodDraftStep]), so the text field behaves normally. [toDraft] and
/// [toTokens] are inverses with one exception: a blank-labelled ref
/// materialises as its line's name (or, for a collective, the run of its
/// constituents) and re-emits that label.
///
/// Nothing here matches prose against anything (ADR-0004); the only string
/// parsed is one the user selected ([parseSelectedDuration]).
library;

import 'package:meta/meta.dart';

import '../../../core/search/search_query.dart' show searchTokens;
import '../../ingredients/domain/normalize.dart' show matchTextForms;
import 'method_step.dart';
import 'recipe.dart';

/// A marked range in a step's sentence — the chip skin the editor paints, and
/// the token [toTokens] re-emits. Half-open: `[start, end)`.
sealed class DraftSpan {
  const DraftSpan({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;

  /// This span re-anchored over `[start, end)`, carrying its own payload.
  DraftSpan moved(int start, int end);
}

/// An ingredient chip: the lines it points at, and whether it shows an amount.
@immutable
final class RefSpan extends DraftSpan {
  const RefSpan({
    required super.start,
    required super.end,
    required this.refs,
    this.amountRule = ChipAmountRule.showAmount,
    this.portion,
  });

  /// The `line_item_id`s this chip stands for. More than one is a collective.
  final List<String> refs;
  final ChipAmountRule amountRule;
  final StepPortion? portion;

  @override
  RefSpan moved(int start, int end) => RefSpan(
    start: start,
    end: end,
    refs: refs,
    amountRule: amountRule,
    portion: portion,
  );

  RefSpan copyWith({
    List<String>? refs,
    ChipAmountRule? amountRule,
    StepPortion? portion,
  }) => RefSpan(
    start: start,
    end: end,
    refs: refs ?? this.refs,
    amountRule: amountRule ?? this.amountRule,
    portion: portion ?? this.portion,
  );

  @override
  bool operator ==(Object other) =>
      other is RefSpan &&
      other.start == start &&
      other.end == end &&
      other.amountRule == amountRule &&
      other.portion == portion &&
      _sameRefs(other.refs, refs);

  @override
  int get hashCode => Object.hash(start, end, amountRule, portion, refs.length);

  @override
  String toString() => 'RefSpan($start,$end,$refs,$amountRule)';
}

/// A timer chip. The seconds ride here, so the round-trip never re-parses the
/// string [formatTimerRange] printed.
@immutable
final class TimerSpan extends DraftSpan {
  const TimerSpan({
    required super.start,
    required super.end,
    required this.lowSeconds,
    required this.highSeconds,
  });

  final int lowSeconds;
  final int highSeconds;

  @override
  TimerSpan moved(int start, int end) => TimerSpan(
    start: start,
    end: end,
    lowSeconds: lowSeconds,
    highSeconds: highSeconds,
  );

  @override
  bool operator ==(Object other) =>
      other is TimerSpan &&
      other.start == start &&
      other.end == end &&
      other.lowSeconds == lowSeconds &&
      other.highSeconds == highSeconds;

  @override
  int get hashCode => Object.hash(start, end, lowSeconds, highSeconds);

  @override
  String toString() => 'TimerSpan($start,$end,$lowSeconds,$highSeconds)';
}

bool _sameRefs(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One step as the editor holds it: the sentence plus the chip ranges (sorted,
/// non-overlapping, inside [text]). [id] is an editor-session handle, never
/// persisted; see [stableStepKey].
@immutable
class MethodDraftStep {
  const MethodDraftStep({
    required this.id,
    required this.text,
    this.spans = const [],
  });

  final String id;
  final String text;
  final List<DraftSpan> spans;

  MethodDraftStep copyWith({String? text, List<DraftSpan>? spans}) =>
      MethodDraftStep(
        id: id,
        text: text ?? this.text,
        spans: spans ?? this.spans,
      );

  @override
  bool operator ==(Object other) =>
      other is MethodDraftStep &&
      other.id == id &&
      other.text == text &&
      other.spans.length == spans.length &&
      Iterable<int>.generate(
        spans.length,
      ).every((i) => other.spans[i] == spans[i]);

  @override
  int get hashCode => Object.hash(id, text, spans.length);

  @override
  String toString() => 'MethodDraftStep($id, "$text", $spans)';
}

// --- tokens ⇄ (text, spans) --------------------------------------------------

/// Flattens [step] into its sentence, with one span per chip. [lineById] is
/// consulted only to materialise a blank label.
MethodDraftStep toDraft(
  MethodStep step, {
  required String id,
  Map<String, LineItem> lineById = const {},
}) {
  final buffer = StringBuffer();
  final spans = <DraftSpan>[];
  var offset = 0;
  for (final token in step.tokens) {
    switch (token) {
      case MethodText(:final s):
        buffer.write(s);
        offset += s.length;
      case MethodTimer(:final lowSeconds, :final highSeconds):
        final word = formatTimerRange(lowSeconds, highSeconds);
        buffer.write(word);
        spans.add(
          TimerSpan(
            start: offset,
            end: offset + word.length,
            lowSeconds: lowSeconds,
            highSeconds: highSeconds,
          ),
        );
        offset += word.length;
      case MethodRef(
        :final refs,
        :final label,
        :final amountRule,
        :final portion,
      ):
        final word = label.isEmpty ? _materialise(refs, lineById) : label;
        // A blank label whose lines resolve to nothing is dropped.
        if (word.isEmpty) continue;
        buffer.write(word);
        spans.add(
          RefSpan(
            start: offset,
            end: offset + word.length,
            refs: refs,
            amountRule: amountRule,
            portion: portion,
          ),
        );
        offset += word.length;
    }
  }
  return MethodDraftStep(id: id, text: buffer.toString(), spans: spans);
}

String _materialise(List<String> refs, Map<String, LineItem> lineById) {
  final names = <String>[];
  for (final ref in refs) {
    final name = lineById[ref]?.ingredientName.trim() ?? '';
    if (name.isNotEmpty) names.add(name);
  }
  return names.join(', ');
}

/// Collapses a draft back into tokens. The text between spans becomes
/// [MethodText]; every span becomes the token it came from.
MethodStep toTokens(MethodDraftStep draft) {
  final tokens = <MethodToken>[];
  var cursor = 0;
  void flush(int upto) {
    if (upto > cursor) {
      tokens.add(MethodToken.text(s: draft.text.substring(cursor, upto)));
    }
  }

  for (final span in draft.spans) {
    flush(span.start);
    switch (span) {
      case RefSpan(:final refs, :final amountRule, :final portion):
        tokens.add(
          MethodToken.ref(
            refs: refs,
            label: draft.text.substring(span.start, span.end),
            amountRule: amountRule,
            portion: portion,
          ),
        );
      case TimerSpan(:final lowSeconds, :final highSeconds):
        tokens.add(
          MethodToken.timer(lowSeconds: lowSeconds, highSeconds: highSeconds),
        );
    }
    cursor = span.end;
  }
  flush(draft.text.length);
  return MethodStep(tokens: tokens);
}

/// The index of the span [offset] falls strictly inside, or null. Strictly, so
/// a tap at a chip's edge places an ordinary caret beside it.
int? spanAt(MethodDraftStep draft, int offset) {
  for (var i = 0; i < draft.spans.length; i++) {
    final span = draft.spans[i];
    if (offset > span.start && offset < span.end) return i;
  }
  return null;
}

/// The index of the span that ends at [offset], or null.
///
/// iOS snaps a tap's caret to the end of the word it fell in, so a tap on a
/// short chip arrives at `span.end`. Only the caret's affinity tells that apart
/// from "beside the chip", so only a caller that has it should ask this.
int? spanEndingAt(MethodDraftStep draft, int offset) {
  for (var i = 0; i < draft.spans.length; i++) {
    if (draft.spans[i].end == offset) return i;
  }
  return null;
}

// --- editing rules -----------------------------------------------------------

/// Re-anchors [draft]'s spans after the text became [newText], diffing by
/// common prefix and suffix.
///
/// An edit before a span shifts it; an edit after leaves it; an edit that
/// touches its interior or crosses its boundary demotes it to plain text.
MethodDraftStep applyEdit(MethodDraftStep draft, String newText) {
  final old = draft.text;
  if (old == newText) return draft;

  final max = old.length < newText.length ? old.length : newText.length;
  var prefix = 0;
  while (prefix < max && old.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < max - prefix &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          newText.codeUnitAt(newText.length - 1 - suffix)) {
    suffix++;
  }

  final changedEnd = old.length - suffix;
  final delta = newText.length - old.length;
  final spans = <DraftSpan>[];
  for (final span in draft.spans) {
    if (span.end <= prefix) {
      spans.add(span);
    } else if (span.start >= changedEnd) {
      spans.add(span.moved(span.start + delta, span.end + delta));
    }
    // else: demoted — the word survives in newText, the link does not.
  }
  return MethodDraftStep(id: draft.id, text: newText, spans: spans);
}

/// Marks [span]'s range as a chip, **changing no text at all** — the selection
/// → chip path. Any span it overlaps is replaced.
MethodDraftStep annotate(MethodDraftStep draft, DraftSpan span) {
  if (span.start < 0 || span.end > draft.text.length || span.length <= 0) {
    return draft;
  }
  final spans = <DraftSpan>[
    for (final existing in draft.spans)
      if (existing.end <= span.start || existing.start >= span.end) existing,
    span,
  ]..sort((a, b) => a.start.compareTo(b.start));
  return draft.copyWith(spans: spans);
}

/// Splices [word] in at [offset] and chips it — the no-selection door (the
/// card's `＋ ingredient` / `timer` buttons).
MethodDraftStep insertSpan(
  MethodDraftStep draft, {
  required int offset,
  required String word,
  required DraftSpan span,
}) {
  if (word.isEmpty) return draft;
  final at = offset.clamp(0, draft.text.length);
  final text = draft.text.replaceRange(at, at, word);
  final shifted = <DraftSpan>[
    for (final existing in draft.spans)
      if (existing.end <= at)
        existing
      else if (existing.start >= at)
        existing.moved(
          existing.start + word.length,
          existing.end + word.length,
        ),
    // A caret inside a chip demotes it, exactly as typing there would.
  ];
  return annotate(
    MethodDraftStep(id: draft.id, text: text, spans: shifted),
    span.moved(at, at + word.length),
  );
}

/// Drops the span at [index], **keeping its word** — removing a chip never
/// touches the sentence.
MethodDraftStep removeSpan(MethodDraftStep draft, int index) {
  if (index < 0 || index >= draft.spans.length) return draft;
  return draft.copyWith(
    spans: [
      for (final (i, span) in draft.spans.indexed)
        if (i != index) span,
    ],
  );
}

/// Replaces the span at [index] with [span], re-anchored over [word] written in
/// its place. The one door for renaming, re-pointing, re-ruling and re-timing a
/// chip.
MethodDraftStep respan(
  MethodDraftStep draft,
  int index, {
  required DraftSpan span,
  required String word,
}) {
  if (index < 0 || index >= draft.spans.length || word.isEmpty) return draft;
  final old = draft.spans[index];
  final delta = word.length - old.length;
  final text = draft.text.replaceRange(old.start, old.end, word);
  return MethodDraftStep(
    id: draft.id,
    text: text,
    spans: [
      for (final (i, existing) in draft.spans.indexed)
        if (i == index)
          span.moved(old.start, old.start + word.length)
        else if (existing.start >= old.end)
          existing.moved(existing.start + delta, existing.end + delta)
        else
          existing,
    ],
  );
}

/// The word the span at [index] currently reads as.
String spanWord(MethodDraftStep draft, int index) =>
    draft.text.substring(draft.spans[index].start, draft.spans[index].end);

/// The amount rule for a chip the user is creating: the first mention in method
/// order shows the amount, later ones only name it.
///
/// "Earlier" is every span in preceding steps plus the spans of [stepId] ending
/// at or before [offset]. Never applied to an imported chip, whose extractor
/// classification stands.
ChipAmountRule amountRuleFor(
  List<MethodDraftStep> steps, {
  required String lineId,
  required String stepId,
  required int offset,
}) {
  for (final step in steps) {
    final here = step.id == stepId;
    for (final span in step.spans) {
      if (here && span.end > offset) break;
      if (span is RefSpan && span.refs.contains(lineId)) {
        return ChipAmountRule.hideAmount;
      }
    }
    if (here) break;
  }
  return ChipAmountRule.showAmount;
}

/// [name] cased the way a chip at this position should read.
///
/// [previousWord]'s case decides: lowercase lowers every Title-Cased word of
/// [name] (`Olive Oil` reads `olive oil`); a leading capital capitalises only
/// the first letter; ALL CAPS of more than one letter uppercases the whole; no
/// letters leaves [name] as stored. A word with a capital after its first
/// letter stands as written (`BBQ Sauce` reads `BBQ sauce`), and hyphenated
/// parts are judged separately.
///
/// With no [previousWord], a chip opening the step ([textBefore] empty) is
/// capitalised and any other is lowercased. Only case changes; nothing is
/// pluralised.
String chipWord(String name, {String? previousWord, String textBefore = ''}) {
  if (name.isEmpty) return name;
  final letters = [
    for (final c in (previousWord ?? '').split(''))
      if (c.toUpperCase() != c.toLowerCase()) c,
  ];
  if (letters.isEmpty) {
    if (previousWord != null && previousWord.isNotEmpty) return name;
    return textBefore.trim().isEmpty ? _upperFirst(name) : _lowerName(name);
  }
  if (letters.length > 1 && letters.every((c) => c == c.toUpperCase())) {
    return name.toUpperCase();
  }
  final first = letters.first;
  return first == first.toLowerCase() ? _lowerName(name) : _upperFirst(name);
}

/// [name] with the initial of every Title-Cased word lowercased.
String _lowerName(String name) => name
    .split(' ')
    .map((word) => word.split('-').map(_lowerTitleCased).join('-'))
    .join(' ');

/// [s] with its first letter lowercased, only when every later letter is
/// already lowercase. A letter is any character whose cases differ; one whose
/// lowercase has a different length is left as typed.
String _lowerTitleCased(String s) {
  final runes = s.runes.toList();
  var initial = -1;
  for (var i = 0; i < runes.length; i++) {
    final c = String.fromCharCode(runes[i]);
    if (c.toUpperCase() == c.toLowerCase()) continue;
    if (initial < 0) {
      initial = i;
    } else if (c != c.toLowerCase()) {
      return s;
    }
  }
  if (initial < 0) return s;
  final c = String.fromCharCode(runes[initial]);
  final lower = c.toLowerCase();
  if (lower == c || lower.length != c.length) return s;
  return String.fromCharCodes(runes.take(initial)) +
      lower +
      String.fromCharCodes(runes.skip(initial + 1));
}

String _upperFirst(String s) => s[0].toUpperCase() + s.substring(1);

/// One relabelled chip and the word it carried before — the session memory
/// behind *was "sausage" · keep the old word*.
typedef ChipRelabel = ({String stepId, int spanIndex, String oldWord});

/// One line's identity change, as the editor reads it back for this sitting:
/// the name the chips carried, the name they carry now, and which steps moved.
typedef Substitution = ({String oldName, String newName, Set<String> stepIds});

/// Every chip pointing at [lineId] takes [label] as its word, cased by
/// [chipWord], so a chip never names something the recipe does not contain.
///
/// The surrounding text is unchanged, and each returned [ChipRelabel] carries
/// the previous word so it can be put back.
({List<MethodDraftStep> steps, List<ChipRelabel> relabels}) relabelRefs(
  List<MethodDraftStep> steps, {
  required String lineId,
  required String label,
}) {
  if (label.isEmpty) return (steps: steps, relabels: const []);
  final out = <MethodDraftStep>[];
  final relabels = <ChipRelabel>[];
  for (final step in steps) {
    var next = step;
    for (var i = 0; i < step.spans.length; i++) {
      final span = next.spans[i];
      if (span is! RefSpan || !span.refs.contains(lineId)) continue;
      final word = spanWord(next, i);
      final recased = chipWord(label, previousWord: word);
      if (word == recased) continue;
      relabels.add((stepId: step.id, spanIndex: i, oldWord: word));
      next = respan(next, i, span: span, word: recased);
    }
    out.add(next);
  }
  return (steps: out, relabels: relabels);
}

/// The step indexes whose chips point at [lineId] — what *"used in 2 steps"*
/// counts, and what the removal prompt names.
List<int> stepsMentioning(List<MethodDraftStep> steps, String lineId) => [
  for (final (i, step) in steps.indexed)
    if (step.spans.any((s) => s is RefSpan && s.refs.contains(lineId))) i,
];

/// Refs to lines the recipe no longer has become plain words. Run on every
/// save. A collective keeps its surviving members, or its word as text when
/// none survive; adjacent text tokens are merged.
List<MethodStep> pruneDanglingRefs(
  List<MethodStep> steps,
  Set<String> keptLineIds,
) => [
  for (final step in steps)
    MethodStep(
      tokens: _mergeText([
        for (final token in step.tokens)
          if (token is MethodRef)
            if (token.refs.every(keptLineIds.contains))
              token
            else if (token.refs.any(keptLineIds.contains))
              token.copyWith(
                refs: [
                  for (final ref in token.refs)
                    if (keptLineIds.contains(ref)) ref,
                ],
              )
            else
              MethodToken.text(s: token.label)
          else
            token,
      ]),
    ),
];

List<MethodToken> _mergeText(List<MethodToken> tokens) {
  final out = <MethodToken>[];
  for (final token in tokens) {
    if (token is MethodText) {
      if (token.s.isEmpty) continue;
      final last = out.isEmpty ? null : out.last;
      if (last is MethodText) {
        out[out.length - 1] = MethodToken.text(s: last.s + token.s);
        continue;
      }
    }
    out.add(token);
  }
  return out;
}

/// Each step's own prose, byte-identical to what its card shows: converting to
/// plain text changes no sentence, only the links.
List<String> flattenMethod(
  List<MethodStep> steps, {
  Map<String, LineItem> lineById = const {},
}) => [
  for (final step in steps) toDraft(step, id: '', lineById: lineById).text,
];

/// One text token per line — how a legacy plain-text method (or a method typed
/// from scratch) becomes tokens; there is one method shape.
List<MethodStep> methodFromPlainSteps(List<String> steps) => [
  for (final s in steps) MethodStep(tokens: [MethodToken.text(s: s)]),
];

// --- step list operations ----------------------------------------------------

List<MethodDraftStep> addStep(
  List<MethodDraftStep> steps, {
  required String id,
}) => [...steps, MethodDraftStep(id: id, text: '')];

List<MethodDraftStep> removeStep(List<MethodDraftStep> steps, String id) => [
  for (final step in steps)
    if (step.id != id) step,
];

/// Moves the step [id] by [by] places (−1 up, +1 down). Out-of-range is a
/// no-op, so the card's ▲ on the first step simply does nothing.
List<MethodDraftStep> moveStep(List<MethodDraftStep> steps, String id, int by) {
  final from = steps.indexWhere((s) => s.id == id);
  if (from < 0) return steps;
  final to = from + by;
  if (to < 0 || to >= steps.length) return steps;
  final out = [...steps];
  out.insert(to, out.removeAt(from));
  return out;
}

// --- the two pure lookups the sheets need ------------------------------------

/// The seconds a deliberately selected run of text says, or null.
///
/// Runs once at edit time on a user selection (not render-time matching,
/// ADR-0004), and the result is confirmed in a stepper. An unparseable time
/// returns null rather than a guess.
(int low, int high)? parseSelectedDuration(String selection) {
  final s = selection
      .toLowerCase()
      .replaceAll(RegExp('[‐-―]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty) return null;

  const unit =
      '(h|hr|hrs|hour|hours|m|min|mins|minute|minutes|s|sec|secs|second|'
      'seconds)';
  const num = r'(\d+(?:\.\d+)?)';

  final range = RegExp('$num *$unit? *(?:-|to|or) *$num *$unit').firstMatch(s);
  if (range != null) {
    final highUnit = range.group(4)!;
    final low = _seconds(range.group(1)!, range.group(2) ?? highUnit);
    final high = _seconds(range.group(3)!, highUnit);
    if (low <= 0 || high <= 0) return null;
    return low <= high ? (low, high) : (high, low);
  }

  // A single duration, possibly compound: "1 h 30 min", "6 min 30 s".
  final parts = RegExp('$num *$unit').allMatches(s).toList();
  if (parts.isEmpty) return null;
  var total = 0;
  for (final part in parts) {
    total += _seconds(part.group(1)!, part.group(2)!);
  }
  // "1 h 30" — a bare trailing number after an hours part means minutes.
  final tail = RegExp(r'(\d+)\s*$').firstMatch(s);
  if (tail != null &&
      tail.start >= parts.last.end &&
      _seconds('1', parts.last.group(2)!) >= 3600) {
    total += int.parse(tail.group(1)!) * 60;
  }
  if (total <= 0) return null;
  return (total, total);
}

int _seconds(String amount, String unit) {
  final value = double.parse(amount);
  final multiplier = switch (unit) {
    'h' || 'hr' || 'hrs' || 'hour' || 'hours' => 3600,
    's' || 'sec' || 'secs' || 'second' || 'seconds' => 1,
    _ => 60,
  };
  return (value * multiplier).round();
}

/// The lines of this recipe a selection already points at: every query token
/// must word-prefix some word of the line's name, in any order.
///
/// Local to the recipe (ADR-0004). Deliberately not the line picker's matcher,
/// so it cannot drift with the shared ranking; it shares only the tokenizer.
List<LineItem> prematchLines(List<LineItem> lines, String query) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return const [];
  return [
    for (final line in lines)
      if (_matchesAll(searchTokens(line.ingredientName), tokens)) line,
  ];
}

/// Every token word-prefixes some word, in its own spelling or its singular, by
/// the shared tokenizer's folding (accents, plurals).
bool _matchesAll(List<String> words, List<String> tokens) => tokens.every(
  (token) => matchTextForms(
    token,
  ).any((form) => words.any((word) => word.startsWith(form))),
);

/// A key for a step that survives a rebuild, a sync or a reorder: a hash of the
/// step's prose.
///
/// Derived because the `steps` jsonb contract has no `id` field. Two steps with
/// identical prose collide.
String stableStepKey(MethodStep step) {
  // FNV-1a, 32-bit — a hash, not a digest; no dependency, and stable across
  // platforms because it is defined on code units.
  var hash = 0x811c9dc5;
  for (final unit in toDraft(step, id: '').text.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
