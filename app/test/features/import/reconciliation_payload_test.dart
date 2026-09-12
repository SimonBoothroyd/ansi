import 'dart:convert';

import 'package:ansi/features/import/data/sample_payloads.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gold_fixture.dart';

void main() {
  group('ReconciliationPayload.fromJson (canned fixture)', () {
    final payload = ReconciliationPayload.fromJson(
      jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
    );

    test('parses top-level fields incl. the polymorphic time field', () {
      expect(payload.title, 'Weeknight Tomato Pasta');
      expect(payload.servingsBase, 2);
      // A bare number time becomes a zero-width range.
      expect(payload.totalTimeSeconds, isNotNull);
      expect(payload.totalTimeSeconds!.lowSeconds, 1500);
      expect(payload.totalTimeSeconds!.highSeconds, 1500);
      expect(payload.cookTimeSeconds, isNull);
      expect(payload.parseWarnings, isNotEmpty);
    });

    test('bands and candidates decode per line', () {
      final flat = payload.flatLines;
      expect(flat.first.band, MatchBand.auto);
      expect(flat.first.candidates.single.canonicalName, 'Spaghetti');
      // The two "Aleppo chilli flakes" lines are both unmatched.
      final noneLines = flat.where((l) => l.band == MatchBand.none).toList();
      expect(noneLines.length, greaterThanOrEqualTo(2));
    });

    test('a range line keeps both endpoints, qty null', () {
      final garlic = payload.flatLines[1];
      expect(garlic.raw.qty, isNull);
      expect(garlic.raw.qtyLow, 2);
      expect(garlic.raw.qtyHigh, 3);
      // Garlic is a strong (auto) match — it locks its ingredient while the
      // range stays unpicked (round-3 #4).
      expect(garlic.band, MatchBand.auto);
    });

    test(
      'step tokens decode into the union (text / ref / timer / portion)',
      () {
        final step1 = payload.steps.first.tokens;
        expect(step1.whereType<TextToken>(), isNotEmpty);
        expect(step1.whereType<TimerToken>().single.lowSeconds, 540);
        final ref = step1.whereType<RefToken>().single;
        expect(ref.refs, [0]);
        expect(ref.mention, MentionKind.isNew);

        // The last step carries a collective ref and a qualifier-only portion.
        final lastTokens = payload.steps.last.tokens;
        final collective = lastTokens.whereType<RefToken>().firstWhere(
          (t) => t.refs.length > 1,
        );
        expect(collective.refs, [2, 6]);
        final garnish = lastTokens.whereType<RefToken>().firstWhere(
          (t) => t.portion != null,
        );
        expect(garnish.portion!.qualifier, 'to serve');
      },
    );
  });

  group('recipe_candidates — the additive field', () {
    // The server OMITS the field entirely when a line hits no recipe title,
    // and when no recipe-title matcher is wired at all. An absent field must
    // therefore decode exactly as it did before the field existed.
    test('an ABSENT field decodes as no offers — byte-identical behaviour', () {
      final line = ReconLine.fromJson(const {
        'raw': {'ingredient_text': 'spaghetti'},
        'band': 'auto',
        'candidates': [
          {'ingredient_id': 'v-spag', 'canonical_name': 'Spaghetti'},
        ],
      });
      expect(line.recipeCandidates, isEmpty);
      expect(line.candidates.single.ingredientId, 'v-spag');
    });

    test('the canned payload and every gold file still parse offer-free', () {
      final canned = ReconciliationPayload.fromJson(
        jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
      );
      expect(canned.flatLines.every((l) => l.recipeCandidates.isEmpty), isTrue);
      for (final name in ['sausage-sliders', 'mint-pea-soup']) {
        final gold = goldPayload(name);
        expect(
          gold.flatLines.every((l) => l.recipeCandidates.isEmpty),
          isTrue,
          reason: '$name must not grow offers from a field it never carried',
        );
      }
    }, skip: skipWithoutGold);

    test('a PRESENT field decodes id, title and score — no defaults', () {
      final line = ReconLine.fromJson(const {
        'raw': {'ingredient_text': 'Romesco Aioli (page 38)'},
        'band': 'none',
        'candidates': <Object?>[],
        'recipe_candidates': [
          {'recipe_id': 'r-aioli', 'title': 'Romesco Aioli', 'score': 1},
          {'recipe_id': 'r-toast', 'title': 'Romesco Toasts', 'score': 0.62},
        ],
      });
      expect(line.recipeCandidates, hasLength(2));
      expect(line.recipeCandidates.first.recipeId, 'r-aioli');
      expect(line.recipeCandidates.first.title, 'Romesco Aioli');
      expect(line.recipeCandidates.first.score, 1); // not the @Default(0)
      expect(line.recipeCandidates.last.score, closeTo(0.62, 1e-9));
      // Independent of the ingredient cascade: a line can carry both.
      expect(line.candidates, isEmpty);
      expect(line.band, MatchBand.none);
    });

    test('offers ride ALONGSIDE ingredient candidates on the same line', () {
      final line = ReconLine.fromJson(const {
        'raw': {'ingredient_text': 'aioli'},
        'band': 'suggest',
        'candidates': [
          {
            'ingredient_id': 'v-aioli',
            'canonical_name': 'Aioli, jarred',
            'score': 0.7,
          },
        ],
        'recipe_candidates': [
          {'recipe_id': 'r-aioli', 'title': 'Romesco Aioli', 'score': 0.9},
        ],
      });
      expect(line.candidates, hasLength(1));
      expect(line.recipeCandidates, hasLength(1));
    });
  });

  group('ReconciliationPayload from a blessed gold file', () {
    test('mint-pea-soup parses with fraction portions and multi-timers', () {
      final payload = goldPayload('mint-pea-soup');
      expect(payload.title, 'mint pea soup');
      expect(payload.servingsBase, 4);
      expect(payload.flatLines, hasLength(11));

      // Step 1 holds three timer tokens (6–8 min, 5 min fresh, 2 min frozen).
      final timers = payload.steps.first.tokens
          .whereType<TimerToken>()
          .toList();
      expect(timers, hasLength(3));
      expect(timers.first.lowSeconds, 360);
      expect(timers.first.highSeconds, 480);

      // The stock line is referenced twice, both fraction mentions with a
      // portion (1 cup, then 1½ cups).
      final refs = payload.steps.first.tokens
          .whereType<RefToken>()
          .where((t) => t.mention == MentionKind.fraction)
          .toList();
      expect(refs, hasLength(2));
      expect(refs[0].portion!.qty, 1);
      expect(refs[1].portion!.qty, 1.5);
    });

    test('dense-bean-salad carries a collective catch-all chip', () {
      final payload = goldPayload('dense-bean-salad');
      final collective = payload.steps
          .expand((s) => s.tokens)
          .whereType<RefToken>()
          .firstWhere((t) => t.refs.length > 1);
      expect(collective.refs, [3, 4, 5, 6, 7, 8, 9, 10]);
      expect(collective.label, 'all the remaining ingredients');
    });
  }, skip: skipWithoutGold);
}
