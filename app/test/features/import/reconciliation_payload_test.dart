import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mise/features/import/data/canned_payload.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';

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
        expect(collective.refs, [2, 5]);
        final garnish = lastTokens.whereType<RefToken>().firstWhere(
          (t) => t.portion != null,
        );
        expect(garnish.portion!.qualifier, 'to serve');
      },
    );
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
  });
}
