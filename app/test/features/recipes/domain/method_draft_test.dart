/// Pins the editor's method model: a step round-trips to text + marked ranges
/// and back, byte-identically, and every editing rule is a pure function.
///
/// The specimen is the **sausage-sliders gold** — the real extraction the eval
/// harness pins — with its by-index refs remapped to line ids exactly as the
/// import commit does. If the round-trip survives that, it survives an import.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/recipes/domain/method_draft.dart';
import 'package:ansi/features/recipes/domain/method_step.dart';
import 'package:ansi/features/recipes/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

const _goldPath = '../evals/datasets/extraction/gold/sausage-sliders.json';

/// The gold's steps as the app stores them: refs remapped from the flattened
/// line index to `line-<i>`, which is what commit does with real ids.
({List<MethodStep> steps, Map<String, LineItem> lineById}) _gold() {
  final json =
      jsonDecode(File(_goldPath).readAsStringSync()) as Map<String, Object?>;

  final lineById = <String, LineItem>{};
  var index = 0;
  for (final group in json['groups']! as List<Object?>) {
    for (final line in (group! as Map)['line_items'] as List<Object?>) {
      final l = line! as Map;
      lineById['line-$index'] = LineItem(
        id: 'line-$index',
        ingredientId: 'ing-$index',
        ingredientName: l['ingredient_text'] as String,
        unit: unitById(l['unit'] as String? ?? '') ?? g,
        quantity: (l['qty'] as num?)?.toDouble(),
      );
      index++;
    }
  }

  final steps = [
    for (final step in json['steps']! as List<Object?>)
      MethodStep(
        tokens: [
          for (final token in (step! as Map)['tokens'] as List<Object?>)
            _token(token! as Map),
        ],
      ),
  ];
  return (steps: steps, lineById: lineById);
}

MethodToken _token(Map<Object?, Object?> t) => switch (t['t']) {
  'text' => MethodToken.text(s: t['s']! as String),
  'timer' => MethodToken.timer(
    lowSeconds: (t['low_seconds']! as num).toInt(),
    highSeconds: (t['high_seconds']! as num).toInt(),
  ),
  _ => MethodToken.ref(
    refs: [for (final i in t['refs']! as List<Object?>) 'line-$i'],
    label: t['label']! as String,
    amountRule: switch (t['mention']) {
      'rementioned' => ChipAmountRule.hideAmount,
      'fraction' => ChipAmountRule.partial,
      _ => ChipAmountRule.showAmount,
    },
  ),
};

LineItem _li(String id, String name, {double? qty, Unit unit = g}) => LineItem(
  id: id,
  ingredientId: 'ing-$id',
  ingredientName: name,
  unit: unit,
  quantity: qty,
);

/// `Halve the |fennel| and roast for |25–30 min| with the |olive oil|.` — one
/// hand-built step with two chips and a timer, the shape most rules are
/// argued over.
MethodDraftStep _draft() => toDraft(
  const MethodStep(
    tokens: [
      MethodText(s: 'Halve the '),
      MethodRef(refs: ['a'], label: 'fennel'),
      MethodText(s: ' and roast for '),
      MethodTimer(lowSeconds: 1500, highSeconds: 1800),
      MethodText(s: ' with the '),
      MethodRef(refs: ['b'], label: 'olive oil'),
      MethodText(s: '.'),
    ],
  ),
  id: 's1',
);

void main() {
  group('a step round-trips to text + marked ranges', () {
    test("the gold's real steps survive byte-identically", () {
      final gold = _gold();
      for (final (i, step) in gold.steps.indexed) {
        final draft = toDraft(step, id: 's$i', lineById: gold.lineById);
        expect(
          toTokens(draft),
          step,
          reason: 'step $i did not survive tokens → (text, spans) → tokens',
        );
      }
    });

    test('the flattened text is the sentence, chips included', () {
      final gold = _gold();
      final draft = toDraft(gold.steps[1], id: 's', lineById: gold.lineById);
      expect(draft.text, startsWith('MAKE THE ROASTED FENNEL: Halve the '));
      expect(draft.text, contains('fennel bulb lengthwise'));
      // The timer occupies formatTimerRange's own output, never a re-parse.
      expect(draft.text, contains('25–30 min'));
      expect(
        draft.spans.whereType<TimerSpan>().single,
        isA<TimerSpan>()
            .having((s) => s.lowSeconds, 'low', 1500)
            .having((s) => s.highSeconds, 'high', 1800),
      );
    });

    test('every span lands exactly over its own word', () {
      final gold = _gold();
      final draft = toDraft(gold.steps[3], id: 's', lineById: gold.lineById);
      final words = [
        for (var i = 0; i < draft.spans.length; i++) spanWord(draft, i),
      ];
      expect(
        words,
        containsAll(<String>['buns', 'garlic butter', 'everything spice']),
      );
    });

    test('a leading chip, a trailing chip and two adjacent ones', () {
      const step = MethodStep(
        tokens: [
          MethodRef(refs: ['a'], label: 'Onions'),
          MethodRef(refs: ['b'], label: ' and garlic'),
          MethodText(s: ' go in the '),
          MethodRef(refs: ['c'], label: 'pan'),
        ],
      );
      final draft = toDraft(step, id: 's');
      expect(draft.text, 'Onions and garlic go in the pan');
      expect(draft.spans.first.start, 0);
      expect(draft.spans.last.end, draft.text.length);
      expect(toTokens(draft), step);
    });

    test('an empty step is an empty draft, and comes back empty', () {
      const step = MethodStep();
      final draft = toDraft(step, id: 's');
      expect(draft.text, isEmpty);
      expect(toTokens(draft), step);
    });

    test(
      'a BLANK-LABELLED collective materialises as its constituent run — the '
      'one deliberate conversion',
      () {
        const step = MethodStep(
          tokens: [
            MethodText(s: 'Blitz the '),
            MethodRef(refs: ['a', 'b', 'c'], label: ''),
            MethodText(s: ' together.'),
          ],
        );
        final lines = {
          'a': _li('a', 'kale'),
          'b': _li('b', 'avocado'),
          'c': _li('c', 'garlic'),
        };
        final draft = toDraft(step, id: 's', lineById: lines);
        expect(draft.text, 'Blitz the kale, avocado, garlic together.');
        // Lossy, deliberately: the re-emitted token carries the materialised
        // label rather than the blank one. Everything else survives.
        final ref = toTokens(draft).tokens[1] as MethodRef;
        expect(ref.label, 'kale, avocado, garlic');
        expect(ref.refs, ['a', 'b', 'c']);
        // And from there it is a fixpoint.
        expect(toTokens(toDraft(toTokens(draft), id: 's')), toTokens(draft));
      },
    );
  });

  group('spanAt', () {
    test('is null outside, null on either boundary, and the index inside', () {
      final draft = _draft();
      final fennel = draft.spans[0];
      expect(spanAt(draft, 0), isNull);
      expect(spanAt(draft, fennel.start), isNull);
      expect(spanAt(draft, fennel.end), isNull);
      expect(spanAt(draft, fennel.start + 1), 0);
      expect(spanAt(draft, fennel.end - 1), 0);
      expect(spanAt(draft, draft.spans[1].start + 2), 1);
    });
  });

  group('editing rules', () {
    test('an edit before a chip shifts it; the text is the new text', () {
      final draft = _draft();
      final before = draft.spans[0];
      final edited = applyEdit(draft, draft.text.replaceFirst('Halve', 'Cut'));
      expect(edited.spans, hasLength(3));
      expect(edited.spans[0].start, before.start - 2);
      expect(spanWord(edited, 0), 'fennel');
    });

    test('an edit after a chip leaves it alone', () {
      final draft = _draft();
      final edited = applyEdit(draft, '${draft.text} Season.');
      expect(edited.spans, equals(draft.spans));
    });

    test('typing INSIDE a chip demotes it — the word stays, the link goes', () {
      final draft = _draft();
      final span = draft.spans[0];
      final edited = applyEdit(
        draft,
        draft.text.replaceRange(span.start + 3, span.start + 3, 'n'),
      );
      expect(edited.spans, hasLength(2));
      expect(edited.text, contains('fennnel'));
      expect(toTokens(edited).tokens.whereType<MethodRef>(), hasLength(1));
    });

    test('typing at a chip’s far edge lands OUTSIDE it, not inside', () {
      // The accepted cost of half-open ranges: the caret at `end` is beside
      // the chip, not in it, so the new letter is prose and the link lives.
      final draft = _draft();
      final at = draft.spans[0].end;
      final edited = applyEdit(draft, draft.text.replaceRange(at, at, 's'));
      expect(spanWord(edited, 0), 'fennel');
      expect(edited.text, contains('fennels and roast'));
    });

    test('deleting across a chip boundary demotes it', () {
      final draft = _draft();
      final span = draft.spans[0];
      final edited = applyEdit(
        draft,
        draft.text.replaceRange(span.end - 1, span.end + 1, ''),
      );
      expect(edited.spans.whereType<RefSpan>(), hasLength(1));
    });

    test('an edit BETWEEN two chips keeps both and moves only the later', () {
      final draft = _draft();
      final gap = draft.spans[0].end;
      final edited = applyEdit(draft, draft.text.replaceRange(gap, gap, ' XX'));
      expect(edited.spans, hasLength(3));
      expect(edited.spans[0], draft.spans[0]);
      expect(edited.spans[2].start, draft.spans[2].start + 3);
    });

    test('backspacing the character right after a chip keeps it', () {
      final draft = _draft();
      final at = draft.spans[0].end;
      final edited = applyEdit(draft, draft.text.replaceRange(at, at + 1, ''));
      expect(edited.spans[0], draft.spans[0]);
    });

    test('pasting over a whole chip demotes it', () {
      final draft = _draft();
      final span = draft.spans[2];
      final edited = applyEdit(
        draft,
        draft.text.replaceRange(span.start, span.end, 'melted butter'),
      );
      expect(edited.spans.whereType<RefSpan>(), hasLength(1));
      expect(edited.text, contains('melted butter'));
    });
  });

  group('annotate — selection → chip', () {
    test('changes NO text and marks exactly the selection', () {
      const plain = MethodDraftStep(id: 's', text: 'Warm the olive oil gently');
      final chipped = annotate(
        plain,
        const RefSpan(start: 9, end: 18, refs: ['oil']),
      );
      expect(chipped.text, plain.text); // byte equality — nothing is rewritten
      expect(spanWord(chipped, 0), 'olive oil');
      final ref = toTokens(chipped).tokens[1] as MethodRef;
      expect(ref.label, 'olive oil');
      expect(ref.refs, ['oil']);
    });

    test('replaces a span it overlaps rather than nesting one', () {
      final draft = _draft();
      final over = draft.spans[0];
      final result = annotate(
        draft,
        RefSpan(start: over.start, end: over.end + 4, refs: const ['z']),
      );
      expect(result.spans, hasLength(3));
      expect((result.spans[0] as RefSpan).refs, ['z']);
    });

    test('an empty or out-of-range selection is refused', () {
      final draft = _draft();
      expect(
        annotate(draft, const RefSpan(start: 3, end: 3, refs: ['a'])),
        draft,
      );
      expect(
        annotate(draft, const RefSpan(start: 0, end: 9999, refs: ['a'])),
        draft,
      );
    });
  });

  group('insert, remove and respan', () {
    test('insertSpan splices the word in and shifts what follows', () {
      final draft = _draft();
      final at = draft.spans[0].end;
      final result = insertSpan(
        draft,
        offset: at,
        word: ' butter',
        span: const RefSpan(start: 0, end: 0, refs: ['c']),
      );
      expect(result.text, contains('fennel butter and roast'));
      expect(spanWord(result, 1), ' butter');
      expect(result.spans, hasLength(4));
    });

    test('removeSpan keeps the word and drops only the link', () {
      final draft = _draft();
      final result = removeSpan(draft, 0);
      expect(result.text, draft.text);
      expect(result.spans, hasLength(2));
      expect(toTokens(result).tokens.whereType<MethodRef>(), hasLength(1));
    });

    test('respan renames the word, keeps the ref, and shifts the rest', () {
      final draft = _draft();
      final span = draft.spans[0] as RefSpan;
      final result = respan(draft, 0, span: span, word: 'fennel bulb');
      expect(result.text, startsWith('Halve the fennel bulb and roast'));
      expect((result.spans[0] as RefSpan).refs, ['a']);
      expect(spanWord(result, 2), 'olive oil');
    });

    test('respan re-points a chip without touching the sentence', () {
      final draft = _draft();
      final span = draft.spans[0] as RefSpan;
      final result = respan(
        draft,
        0,
        span: span.copyWith(refs: ['z']),
        word: spanWord(draft, 0),
      );
      expect(result.text, draft.text);
      expect((result.spans[0] as RefSpan).refs, ['z']);
    });

    test('respan re-times a timer through formatTimerRange', () {
      final draft = _draft();
      final result = respan(
        draft,
        1,
        span: const TimerSpan(
          start: 0,
          end: 0,
          lowSeconds: 600,
          highSeconds: 600,
        ),
        word: formatTimerRange(600, 600),
      );
      expect(result.text, contains('roast for 10 min with'));
      expect((result.spans[1] as TimerSpan).lowSeconds, 600);
    });
  });

  group('amountRuleFor — D9, and only for a chip being made', () {
    final steps = [
      toDraft(
        const MethodStep(
          tokens: [
            MethodText(s: 'Warm the '),
            MethodRef(refs: ['oil'], label: 'oil'),
          ],
        ),
        id: 's1',
      ),
      const MethodDraftStep(id: 's2', text: 'Add the oil and the salt'),
    ];

    test('the first chip pointing at a line shows the amount', () {
      expect(
        amountRuleFor(steps, lineId: 'salt', stepId: 's2', offset: 20),
        ChipAmountRule.showAmount,
      );
    });

    test('a later one just names it', () {
      expect(
        amountRuleFor(steps, lineId: 'oil', stepId: 's2', offset: 8),
        ChipAmountRule.hideAmount,
      );
    });

    test('an earlier chip in the SAME step counts', () {
      final one = [
        toDraft(
          const MethodStep(
            tokens: [
              MethodRef(refs: ['oil'], label: 'oil'),
              MethodText(s: ' then more oil'),
            ],
          ),
          id: 's1',
        ),
      ];
      expect(
        amountRuleFor(one, lineId: 'oil', stepId: 's1', offset: 14),
        ChipAmountRule.hideAmount,
      );
    });

    test("an imported chip's own rule is never re-derived", () {
      final gold = _gold();
      // The gold's step 5 re-mentions the fennel; the extractor said so, and
      // nothing here recomputes it.
      final rules = [
        for (final step in gold.steps)
          for (final token in step.tokens)
            if (token is MethodRef) token.amountRule,
      ];
      expect(rules, contains(ChipAmountRule.hideAmount));
      for (final (i, step) in gold.steps.indexed) {
        final draft = toDraft(step, id: 's$i', lineById: gold.lineById);
        expect(toTokens(draft), step);
      }
    });
  });

  group('relabelRefs — D3', () {
    test('only the chips pointing at the line move; prose is untouched', () {
      final steps = [
        toDraft(
          const MethodStep(
            tokens: [
              MethodText(s: 'Brown the '),
              MethodRef(refs: ['l1'], label: 'sausage'),
              MethodText(s: ', casings removed.'),
            ],
          ),
          id: 's1',
        ),
        toDraft(
          const MethodStep(
            tokens: [
              MethodText(s: 'Toss the '),
              MethodRef(refs: ['l2'], label: 'fennel'),
              MethodText(s: ' in.'),
            ],
          ),
          id: 's2',
        ),
      ];
      final result = relabelRefs(steps, lineId: 'l1', label: 'meatballs');
      expect(result.steps[0].text, 'Brown the meatballs, casings removed.');
      expect(result.steps[1].text, steps[1].text);
      expect(result.relabels, [
        (stepId: 's1', spanIndex: 0, oldWord: 'sausage'),
      ]);
      // The ref survives the relabel — that is the whole point of D6.
      expect((result.steps[0].spans[0] as RefSpan).refs, ['l1']);
    });

    test('the changed-step set is exact when a step has two of them', () {
      final steps = [
        toDraft(
          const MethodStep(
            tokens: [
              MethodRef(refs: ['l1'], label: 'sausage'),
              MethodText(s: ' with more '),
              MethodRef(refs: ['l1'], label: 'sausage'),
            ],
          ),
          id: 's1',
        ),
      ];
      final result = relabelRefs(steps, lineId: 'l1', label: 'meatballs');
      expect(result.steps[0].text, 'meatballs with more meatballs');
      expect(result.relabels, hasLength(2));
      expect(stepsMentioning(result.steps, 'l1'), [0]);
    });
  });

  group('pruneDanglingRefs — no saved step refs an absent line', () {
    test('a removed line leaves its word as plain text', () {
      final steps = [toTokens(_draft())];
      final pruned = pruneDanglingRefs(steps, {'b'});
      expect(pruned.single.tokens.whereType<MethodRef>(), hasLength(1));
      // The sentence is byte-identical to what the card was showing.
      expect(
        toDraft(pruned.single, id: 's').text,
        toDraft(steps.single, id: 's').text,
      );
    });

    test('a collective loses one member and keeps the rest', () {
      const steps = [
        MethodStep(
          tokens: [
            MethodText(s: 'Blitz the '),
            MethodRef(refs: ['a', 'b', 'c'], label: 'greens'),
          ],
        ),
      ];
      final pruned = pruneDanglingRefs(steps, {'a', 'c'});
      expect((pruned.single.tokens[1] as MethodRef).refs, ['a', 'c']);
    });

    test('the property: nothing survives that points at an absent line', () {
      final gold = _gold();
      final pruned = pruneDanglingRefs(gold.steps, {'line-0', 'line-5'});
      for (final step in pruned) {
        for (final token in step.tokens) {
          if (token is MethodRef) {
            expect(token.refs, everyElement(isIn(['line-0', 'line-5'])));
          }
        }
      }
    });
  });

  group('flattenMethod — D5', () {
    test('the prose equals what the cards were showing', () {
      final gold = _gold();
      final flat = flattenMethod(gold.steps, lineById: gold.lineById);
      for (final (i, step) in gold.steps.indexed) {
        expect(flat[i], toDraft(step, id: 's$i', lineById: gold.lineById).text);
      }
      expect(flat[0], 'Preheat the oven to 375°F.');
    });

    test('a plain method enters the tokenized world as one text token', () {
      final steps = methodFromPlainSteps(['Dice the onion.', 'Simmer.']);
      expect(steps, hasLength(2));
      expect(flattenMethod(steps), ['Dice the onion.', 'Simmer.']);
    });
  });

  group('step list operations — D7', () {
    final steps = [
      const MethodDraftStep(id: 'a', text: 'one'),
      const MethodDraftStep(id: 'b', text: 'two'),
      const MethodDraftStep(id: 'c', text: 'three'),
    ];

    test('moveStep moves by one and clamps at the ends', () {
      expect(moveStep(steps, 'c', -1).map((s) => s.id), ['a', 'c', 'b']);
      expect(moveStep(steps, 'a', -1), steps);
      expect(moveStep(steps, 'c', 1), steps);
      expect(moveStep(steps, 'a', 1).map((s) => s.id), ['b', 'a', 'c']);
    });

    test('addStep appends a blank one; removeStep drops it', () {
      final added = addStep(steps, id: 'd');
      expect(added, hasLength(4));
      expect(added.last.text, isEmpty);
      expect(removeStep(added, 'b').map((s) => s.id), ['a', 'c', 'd']);
    });
  });

  group('parseSelectedDuration — the selection only', () {
    test('reads the forms a recipe actually prints', () {
      expect(parseSelectedDuration('25 to 30 minutes'), (1500, 1800));
      expect(parseSelectedDuration('25–30 min'), (1500, 1800));
      expect(parseSelectedDuration('15-20 mins'), (900, 1200));
      expect(parseSelectedDuration('10 mins'), (600, 600));
      expect(parseSelectedDuration('2 hours'), (7200, 7200));
      expect(parseSelectedDuration('1 h 30'), (5400, 5400));
      expect(parseSelectedDuration('1 hour 30 minutes'), (5400, 5400));
      expect(parseSelectedDuration('6 min 30 s'), (390, 390));
      expect(parseSelectedDuration('90 seconds'), (90, 90));
    });

    test('finds the time inside the sentence the user selected', () {
      expect(
        parseSelectedDuration('Roast for 25 to 30 minutes, turning once'),
        (1500, 1800),
      );
    });

    test('returns NULL rather than guessing', () {
      expect(parseSelectedDuration('until golden'), isNull);
      expect(parseSelectedDuration('overnight'), isNull);
      expect(parseSelectedDuration('a while'), isNull);
      expect(parseSelectedDuration(''), isNull);
      expect(parseSelectedDuration('Preheat the oven to 375°F'), isNull);
      expect(parseSelectedDuration('8'), isNull);
    });

    test('a reversed range comes back in order', () {
      expect(parseSelectedDuration('30 to 25 min'), (1500, 1800));
    });
  });

  group('prematchLines — this recipe only, no fuzz', () {
    final gold = _gold();
    final lines = gold.lineById.values.toList();

    test('one clear match is one row', () {
      final hits = prematchLines(lines, 'fennel');
      expect(hits.map((l) => l.ingredientName), ['fennel bulb']);
    });

    test('several matches all come back, in recipe order', () {
      final hits = prematchLines(lines, 'olive');
      expect(hits, hasLength(3));
      expect(hits.every((l) => l.ingredientName == 'olive oil'), isTrue);
    });

    test('a mid-name word matches, and order does not matter', () {
      expect(prematchLines(lines, 'buns'), hasLength(1));
      expect(prematchLines(lines, 'buns pretzel'), hasLength(1));
    });

    test('nothing is guessed at', () {
      expect(prematchLines(lines, 'fennl'), isEmpty);
      expect(prematchLines(lines, 'chicken'), isEmpty);
      expect(prematchLines(lines, '   '), isEmpty);
    });
  });

  group('stableStepKey', () {
    test('is derived from the prose, so it survives a reorder', () {
      final gold = _gold();
      final keys = gold.steps.map(stableStepKey).toList();
      expect(keys.toSet(), hasLength(gold.steps.length));
      expect(gold.steps.reversed.map(stableStepKey), keys.reversed);
    });

    test('the wire format carries no id — the key is not stored', () {
      const step = MethodStep(tokens: [MethodText(s: 'Preheat.')]);
      expect(step.toJson().keys, ['tokens']);
    });
  });

  group('the wire format is untouched by the D9 rename', () {
    test('a ref still reads and writes "mention"', () {
      const ref = MethodRef(
        refs: ['a'],
        label: 'salt',
        amountRule: ChipAmountRule.hideAmount,
      );
      expect(ref.toJson()['mention'], 'rementioned');
      final back = MethodToken.fromJson({
        't': 'ref',
        'refs': ['a'],
        'label': 'salt',
        'mention': 'fraction',
      });
      expect((back as MethodRef).amountRule, ChipAmountRule.partial);
    });
  });
}
