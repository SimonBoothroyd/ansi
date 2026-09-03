import 'package:ansi/features/import/domain/line_resolution.dart';
import 'package:ansi/features/import/domain/method_draft_bridge.dart';
import 'package:ansi/features/import/domain/preview_recipe.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/recipes/domain/method_draft.dart';
import 'package:flutter_test/flutter_test.dart';

ReconLine _line(String text, {double? qty, String? unit}) => ReconLine(
  raw: RawLineItem(ingredientText: text, qty: qty, unit: unit),
  band: MatchBand.none,
);

/// A two-line import whose method chips both lines and carries a timer — the
/// shape the seam has to carry back and forth without changing a byte.
ReconciliationPayload _payload() => ReconciliationPayload(
  title: 'Charred Pepper Traybake',
  servingsBase: 4,
  groups: [
    ReconGroup(
      lines: [
        _line('red peppers', qty: 2, unit: 'piece'),
        _line('onions', qty: 3, unit: 'piece'),
      ],
    ),
  ],
  steps: const [
    Step(
      tokens: [
        TextToken(s: 'Toss the '),
        RefToken(refs: [0], label: 'red peppers'),
        TextToken(s: ' and '),
        RefToken(refs: [1], label: 'onions'),
        TextToken(s: ' with oil.'),
      ],
    ),
    Step(
      tokens: [
        TextToken(s: 'Roast for '),
        TimerToken(lowSeconds: 1500, highSeconds: 1800),
        TextToken(s: ', turning once.'),
      ],
    ),
  ],
);

List<LineResolution> _resolutions(ReconciliationPayload payload) => [
  for (final (i, line) in payload.flatLines.indexed)
    initialResolution(i, line).resolveToIngredient('ing-$i', 'Ingredient $i'),
];

List<MethodDraftStep> _drafts(
  ReconciliationPayload payload,
  List<LineResolution> resolutions,
) => draftsFromPreview(
  buildPreviewRecipe(payload, resolutions, servingsBase: 4),
);

void main() {
  test('previewLineIndex parses exactly what previewLineId writes', () {
    expect(previewLineIndex(previewLineId(0)), 0);
    expect(previewLineIndex(previewLineId(17)), 17);
    expect(previewLineIndex('line-item-3'), isNull);
    expect(previewLineIndex('deadbeef-uuid'), isNull);
  });

  test('the drafts read as the sentences the payload printed', () {
    final payload = _payload();
    final drafts = _drafts(payload, _resolutions(payload));
    expect(drafts, hasLength(2));
    expect(drafts[0].text, 'Toss the red peppers and onions with oil.');
    expect(drafts[1].text, 'Roast for 25–30 min, turning once.');
    // …and the chips point at the preview's own ids, which is what lets the
    // "Reads as" fold show live amounts with no extra plumbing.
    final refs = [
      for (final span in drafts[0].spans)
        if (span is RefSpan) ...span.refs,
    ];
    expect(refs, [previewLineId(0), previewLineId(1)]);
  });

  test('ROUND TRIP: steps → drafts → steps is byte-identical when the user '
      'edits nothing (the sausage-sliders gold)', () {
    final payload = _payload();
    final resolutions = _resolutions(payload);
    final kept = {for (final r in keptLines(resolutions)) r.lineIndex};

    final back = stepsFromDrafts(_drafts(payload, resolutions), kept);

    expect(back, payload.steps);
  });

  test('an edit lands in the steps and changes nothing else', () {
    final payload = _payload();
    final resolutions = _resolutions(payload);
    final drafts = _drafts(payload, resolutions);
    final edited = [...drafts]
      ..[1] = applyEdit(drafts[1], 'Roast for 25–30 min, turning twice.');

    final back = stepsFromDrafts(edited, {0, 1});

    expect(back[0], payload.steps[0]);
    expect(back[1].tokens.last, const StepToken.text(s: ', turning twice.'));
    // The timer survives the prose edit around it.
    expect(
      back[1].tokens[1],
      const StepToken.timer(lowSeconds: 1500, highSeconds: 1800),
    );
  });

  test('a chip whose ONLY line was dropped demotes to plain prose — the '
      'never-dangling-line rule, said once more at this seam', () {
    final payload = _payload();
    final resolutions = _resolutions(payload);
    final drafts = _drafts(payload, resolutions);

    final back = stepsFromDrafts(drafts, {0});

    // "and onions" survives as words; only the link dies, and the prose either
    // side folds into one text token rather than three.
    expect(back[0].tokens, [
      const StepToken.text(s: 'Toss the '),
      const StepToken.ref(refs: [0], label: 'red peppers'),
      const StepToken.text(s: ' and onions with oil.'),
    ]);
  });

  test('a COLLECTIVE chip keeps the refs that survived', () {
    final payload = ReconciliationPayload(
      title: 'T',
      groups: _payload().groups,
      steps: const [
        Step(
          tokens: [
            TextToken(s: 'Soften the '),
            RefToken(refs: [0, 1], label: 'vegetables'),
            TextToken(s: '.'),
          ],
        ),
      ],
    );
    final drafts = _drafts(payload, _resolutions(payload));

    final back = stepsFromDrafts(drafts, {1});

    expect(
      back.single.tokens[1],
      const StepToken.ref(refs: [1], label: 'vegetables'),
    );
  });

  test('an id that is not a review line id THROWS — a chip that vanished '
      'silently would be worse than a crash', () {
    final drafts = [
      const MethodDraftStep(
        id: 'step-0',
        text: 'Toss the peppers.',
        spans: [
          RefSpan(start: 9, end: 16, refs: ['some-uuid']),
        ],
      ),
    ];
    expect(() => stepsFromDrafts(drafts, {0}), throwsA(isA<StateError>()));
  });

  test('a blank step is dropped, exactly as the recipe editor drops one', () {
    final drafts = [
      const MethodDraftStep(id: 'step-0', text: 'Do the thing.'),
      const MethodDraftStep(id: 'step-1', text: '   '),
    ];
    expect(stepsFromDrafts(drafts, {0}), hasLength(1));
  });
}
