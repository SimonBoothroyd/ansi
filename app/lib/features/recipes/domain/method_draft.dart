/// The editor's shape for a tokenized method — PURE DART (invariant 2).
///
/// A [MethodStep] is a token stream; the editor needs a **sentence**. The two
/// are the same thing seen from either end, because a [MethodRef]'s `label`
/// already IS the word standing at that position: the stream
/// `text("Halve the ") · ref(label:"fennel bulb") · text(" lengthwise…")`
/// flattens to exactly the sentence a human would type, with one range marked.
///
/// So the editor's document is a plain [String] plus a side table of
/// `(start, end, refs | timer)` — [MethodDraftStep] — and caret, selection,
/// IME, autocorrect and backspace all behave normally because nothing exotic
/// lives in the text. [toDraft] and [toTokens] are inverses (see the ONE
/// deliberate exception below), pinned by a byte-equality round-trip over the
/// sausage-sliders gold.
///
/// **The one lossy conversion.** A ref whose `label` is blank has no
/// characters of its own. A single-ref one materialises as its line's name; a
/// blank-labelled COLLECTIVE (plan 0020 **J1** — the chip that IS its
/// constituents) materialises as the run the fold already renders, "kale,
/// avocado, garlic". Both then round-trip stably, but the re-emitted token
/// carries the materialised label rather than the blank one. Named and pinned
/// by a test.
///
/// Nothing here matches text against anything (ADR-0004): a chip arrives from
/// the extractor or from a deliberate pick, and the only string this file
/// parses is one the user explicitly selected ([parseSelectedDuration]).
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

/// One step as the editor holds it: the sentence a human sees, plus the ranges
/// that are chips (sorted, non-overlapping, inside [text]).
///
/// [id] is the editor's own handle on the step — minted on load, carried
/// through reorder, and what every card widget is keyed by. It is **not**
/// persisted; see [stableStepKey] for why.
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

/// Flattens [step] into the sentence it reads as, with one span per chip.
///
/// [lineById] is consulted **only** to materialise a blank label (the lossy
/// conversion named in the library doc); a labelled chip never looks a line up,
/// so opening the editor re-matches, re-fetches and re-tokenizes nothing.
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
        // A blank label whose lines all resolve to nothing has no characters
        // to occupy and no name to show; it is dropped rather than given an
        // invented word.
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

/// The index of the span [offset] falls **strictly inside**, or null.
///
/// Strictly, so that a tap at either edge of a chip places an ordinary caret
/// beside it rather than opening a sheet — the boundaries are where a user
/// goes to type around a chip.
int? spanAt(MethodDraftStep draft, int offset) {
  for (var i = 0; i < draft.spans.length; i++) {
    final span = draft.spans[i];
    if (offset > span.start && offset < span.end) return i;
  }
  return null;
}

// --- editing rules -----------------------------------------------------------

/// Re-anchors [draft]'s spans after the text became [newText].
///
/// The diff is the cheap one — the common prefix and common suffix of the two
/// strings — which is exact for a keystroke and good enough for a paste, and
/// is a pure function of two strings.
///
/// - an edit entirely **before** a span shifts it;
/// - an edit entirely **after** it leaves it alone;
/// - an edit that touches a span's **interior**, or deletes across its
///   boundary, **demotes** it: the span goes, the text stays. That is the only
///   honest reading of "I retyped this word", and it means no state exists
///   where a chip covers characters the user did not mean.
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

/// Replaces the span at [index] with [span], re-anchored over [word] written
/// in its place. The one door for renaming a chip's word, re-pointing its
/// refs, flipping its amount rule, and re-timing a timer.
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

/// The D9 rule for a chip the user is **creating**: the first time a step
/// calls for something the chip shows the amount; after that it just names it.
///
/// "Earlier" is method order — every span in every preceding step, plus the
/// spans of [stepId] that end at or before [offset].
///
/// It is **never** applied to an imported chip. §4.6 records the positional
/// heuristic as brittle for imports (recipes reorder, and a first mention is
/// often the incidental one), so the extractor's own classification stands and
/// the chip sheet's switch is the only thing that overrides it.
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

/// One chip whose word D3 replaced, and what it used to read — the session
/// memory behind *was "sausage" · keep the old word*.
typedef ChipRelabel = ({String stepId, int spanIndex, String oldWord});

/// One line's identity change, as the editor reads it back for this sitting:
/// what the chips used to name, what they name now, and which steps moved.
typedef Substitution = ({String oldName, String newName, Set<String> stepIds});

/// D3: every chip pointing at [lineId] takes [label] as its word.
///
/// The invariant it upholds: **a chip never names something the recipe does
/// not contain.** A chip is a pointer with a display label; prose is authored,
/// but a *label* is data about the pointee, so when the pointee's identity
/// changes the printed word is retired — visibly, and revertibly.
///
/// It rewrites nothing else: the text around each chip is byte-identical, and
/// the returned [ChipRelabel]s carry what every changed chip used to say, so
/// one tap can put it back.
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
      if (word == label) continue;
      relabels.add((stepId: step.id, spanIndex: i, oldWord: word));
      next = respan(next, i, span: span, word: label);
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

/// Refs to lines the recipe no longer has become plain words.
///
/// Run on every save, so the property **a saved method never refs a line the
/// recipe does not have** holds however the editor got there. A collective
/// that loses one member keeps the rest; one that loses all of them keeps its
/// word as text. Adjacent text tokens are merged, which is what a chip
/// demoting between two prose runs leaves behind.
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

/// D5: each step's own prose, byte-identical to what its card was showing —
/// converting to plain text changes no sentence, only the links.
List<String> flattenMethod(
  List<MethodStep> steps, {
  Map<String, LineItem> lineById = const {},
}) => [
  for (final step in steps) toDraft(step, id: '', lineById: lineById).text,
];

/// One text token per line — how a legacy plain-text method (or a method typed
/// from scratch) enters the tokenized world (D8: one method shape).
List<MethodStep> methodFromPlainSteps(List<String> steps) => [
  for (final s in steps) MethodStep(tokens: [MethodToken.text(s: s)]),
];

// --- step list operations (D7) -----------------------------------------------

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

/// The seconds a **deliberately selected** run of text says, or null.
///
/// This is not render-time matching (ADR-0004). Nothing scans prose on its
/// own: this runs once, at edit time, on a string the user pointed at and
/// asked us to read, and its output is shown in a stepper for confirmation
/// before a single token is written. A failure returns null and opens the
/// stepper **empty** rather than guessing — "until golden", "overnight" and
/// "a while" are times, and none of them is a number.
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

/// The lines of THIS recipe a selection already points at — word-prefix over
/// at most a few dozen rows, so *"olive oil"* selected in a step arrives at
/// the picker with the olive-oil line already found.
///
/// Deterministic and local (ADR-0004): it never leaves the recipe, never
/// touches the household vocabulary, and never guesses. Every query token must
/// be the prefix of some word in the line's name — order-free, so "oil olive"
/// finds it too, and "oli" finds nothing but what starts that way.
///
/// It is deliberately NOT the line picker's own matcher: that one is a shared
/// search rule with its own lane, and this is a fixed word-prefix over ≤30
/// rows that must not drift when the shared *ranking* changes. It does share
/// the *tokenizer*, because "jalapeno" and "jalapeño" are one word everywhere
/// else in the app and there is no reason for them to be two here.
List<LineItem> prematchLines(List<LineItem> lines, String query) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return const [];
  return [
    for (final line in lines)
      if (_matchesAll(searchTokens(line.ingredientName), tokens)) line,
  ];
}

/// Every token word-prefixes some word, in the token's own spelling or its
/// singular — the shared tokenizer's rule, so an accent typed or not typed
/// ("jalapeno" for *Jalapeño Peppers*) and a plural ("tomatoes" for *Tomato*)
/// fold here exactly as they do in every other search box. Only the
/// *tokenizing* is shared: the ranking above is still this file's own.
bool _matchesAll(List<String> words, List<String> tokens) => tokens.every(
  (token) => matchTextForms(
    token,
  ).any((form) => words.any((word) => word.startsWith(form))),
);

/// A key for a step that survives a rebuild, a sync or a resume — what cook
/// mode needs to keep saying "you are on step 4" (D8).
///
/// **It is derived, not stored.** [MethodStep] has no `id` field and does not
/// get one: the `steps` jsonb is the frozen §4.6 contract, and adding a field
/// would put a new key into every row the import commit writes. So the key is
/// a hash of the step's own prose, which is stable across a reorder (the
/// sentence moves with its step) and across a rebuild.
///
/// The corner cut, tracked: two steps with byte-identical prose collide.
String stableStepKey(MethodStep step) {
  // FNV-1a, 32-bit — a hash, not a digest; no dependency, and stable across
  // platforms because it is defined on code units.
  var hash = 0x811c9dc5;
  for (final unit in toDraft(step, id: '').text.codeUnits) {
    hash = (hash ^ unit) * 0x01000193 & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
