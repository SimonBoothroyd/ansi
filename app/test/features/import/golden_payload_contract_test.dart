/// The client half of the TS→Dart CONTRACT test.
///
/// `supabase/functions/import-recipe/golden_payload.test.ts` runs the real
/// edge spine (mock adapter + the real match cascade, no network, no LLM) and
/// pins its `ReconciliationPayload` as a committed golden JSON file. This test
/// parses THAT SAME FILE with the Dart mirror and asserts every load-bearing
/// field decoded to a real value.
///
/// WHY the "non-default" framing: `reconciliation_payload.dart` mirrors
/// `types.ts` by hand and is defaults-everywhere (`@Default('') rawAmount`,
/// `@Default(true) unitMappable`, `@Default(<Step>[]) steps`, …). A
/// server-side rename therefore does NOT throw here — `fromJson` quietly
/// yields the default. So it is not enough to parse the file; each field has
/// to be asserted to a value the default could never produce. Between the two
/// suites:
///
///   - the server changing shape          → the Deno golden test fails (drift)
///   - the golden regenerated, Dart stale → the assertions below fail
///
/// After an INTENTIONAL contract change: `cd supabase/functions && deno task
/// golden`, review the fixture diff, then update these assertions.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:flutter_test/flutter_test.dart';

/// The golden the edge function's own test writes. Tests run from `app/`.
const _goldenPath =
    '../supabase/functions/import-recipe/__fixtures__/'
    'reconciliation_payload.golden.json';

ReconciliationPayload _loadGolden() {
  final file = File(_goldenPath);
  expect(
    file.existsSync(),
    isTrue,
    reason:
        'missing $_goldenPath — regenerate it with '
        '`cd supabase/functions && deno task golden`',
  );
  return ReconciliationPayload.fromJson(
    jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
  );
}

void main() {
  late ReconciliationPayload payload;
  late List<ReconLine> flat;

  setUp(() {
    payload = _loadGolden();
    flat = payload.flatLines;
  });

  group('recipe-level fields decode from the server payload', () {
    test('identity and servings are not defaults', () {
      expect(payload.title, 'Contract Sampler Stew');
      expect(payload.servingsBase, 4);
      expect(payload.servingsRaw, 'Serves 4');
      expect(payload.yieldRaw, 'Makes about 1.5 litres');
    });

    test('BOTH TimeField forms decode — a bare number and a {low,high}', () {
      // `total_time_seconds: 5400` — the scalar form widens to a zero-width
      // range, so a single printed time round-trips as low == high.
      expect(payload.totalTimeSeconds, isNotNull);
      expect(payload.totalTimeSeconds!.lowSeconds, 5400);
      expect(payload.totalTimeSeconds!.highSeconds, 5400);

      // `cook_time_seconds: {low_seconds, high_seconds}` — the object form.
      expect(payload.cookTimeSeconds, isNotNull);
      expect(payload.cookTimeSeconds!.lowSeconds, 2700);
      expect(payload.cookTimeSeconds!.highSeconds, 3600);
      expect(
        payload.cookTimeSeconds!.lowSeconds,
        isNot(payload.cookTimeSeconds!.highSeconds),
        reason: 'a genuine range must survive as a range, not collapse',
      );
    });

    test('the honesty flags are not defaults', () {
      // Every one of these has a Dart default that would mask a rename:
      // truncated=false, imageQuality=ok, parseWarnings=[].
      expect(payload.truncated, isTrue);
      expect(payload.imageQuality, ImportImageQuality.degraded);
      expect(payload.parseWarnings, hasLength(1));
      expect(payload.parseWarnings.single, contains('parsley'));
    });
  });

  group('groups and line ordering', () {
    test('both groups decode, including the named one', () {
      expect(payload.groups, hasLength(2));
      expect(payload.groups.first.name, isNull);
      expect(payload.groups.last.name, 'To finish');
    });

    test('flatLines spans groups in order — the line_index space', () {
      expect(flat, hasLength(6));
      expect(flat.map((l) => l.raw.ingredientText).toList(), [
        'onion',
        'garlic',
        'coconut milk',
        'flat-leaf parsley',
        'parmasan cheese',
        'gochujang paste',
      ]);
    });
  });

  group('match bands and candidates', () {
    test('all three bands decode from their JSON values', () {
      expect(flat.map((l) => l.band).toList(), [
        MatchBand.auto,
        MatchBand.auto,
        MatchBand.auto,
        MatchBand.auto,
        MatchBand.suggest,
        MatchBand.none,
      ]);
    });

    test('an auto line carries a scored candidate with a real id', () {
      final onion = flat.first;
      expect(onion.candidates, hasLength(1));
      final c = onion.candidates.single;
      expect(c.ingredientId, 'v-onion');
      expect(c.canonicalName, 'Onion');
      expect(c.score, 1); // not the @Default(0)
    });

    test('a suggest line carries a mid-band score', () {
      final parmesan = flat[4];
      expect(parmesan.candidates.single.canonicalName, 'Parmesan Cheese');
      expect(parmesan.candidates.single.score, greaterThan(0.55));
      expect(parmesan.candidates.single.score, lessThan(0.85));
    });

    test('a none line carries NO candidates (no silent auto-stub)', () {
      expect(flat[5].band, MatchBand.none);
      expect(flat[5].candidates, isEmpty);
    });
  });

  group('line-item shapes the UI depends on', () {
    test('a printed RANGE keeps both endpoints with qty null', () {
      final garlic = flat[1];
      expect(garlic.raw.qty, isNull);
      expect(garlic.raw.qtyLow, 2);
      expect(garlic.raw.qtyHigh, 3);
      expect(garlic.raw.rawAmount, '2–3 cloves'); // not the @Default('')
    });

    test('unit_mappable:false survives — it defaults to TRUE in Dart', () {
      // The most dangerous default in the mirror: a dropped/renamed
      // `unit_mappable` would silently mark every unmappable amount mappable.
      final coconut = flat[2];
      expect(coconut.raw.unitMappable, isFalse);
      expect(coconut.raw.unit, 'tin');
      expect(coconut.raw.rawAmount, 'One 400 g tin');
    });

    test(
      'notes decode as the render-time note slot, separate from identity',
      () {
        expect(flat[0].raw.notes, 'finely diced');
        expect(flat[0].raw.ingredientText, 'onion'); // identity stayed clean
        expect(flat[3].raw.notes, 'for garnish');
        expect(flat[2].raw.notes, isNull); // a null note is still a null note
      },
    );

    test('optional and confidence are not defaults', () {
      expect(flat[3].raw.optional, isTrue);
      expect(flat.where((l) => l.raw.optional), hasLength(1));
      expect(flat[0].raw.confidence, 0.97); // not the @Default(1)
      expect(flat[3].raw.confidence, 0.71);
    });

    test('an amount-less line stays amount-less — nothing invented', () {
      final parsley = flat[3];
      expect(parsley.raw.qty, isNull);
      expect(parsley.raw.qtyLow, isNull);
      expect(parsley.raw.qtyHigh, isNull);
      expect(parsley.raw.unit, isNull);
      expect(parsley.raw.rawAmount, isEmpty);
    });
  });

  group('step tokens', () {
    test('the token stream decodes to the sealed union, in order', () {
      expect(payload.steps, hasLength(3));
      final first = payload.steps.first.tokens;
      expect(first.first, isA<TextToken>());
      expect((first.first as TextToken).s, 'Soften the ');
      expect(first.map((t) => t.runtimeType.toString()).toList(), [
        'TextToken',
        'RefToken',
        'TextToken',
        'RefToken',
        'TextToken',
        'TimerToken',
        'TextToken',
      ]);
    });

    test('a ref chip carries its line-index refs, label and mention', () {
      final ref = payload.steps.first.tokens[1] as RefToken;
      expect(ref.refs, [0]); // still by line_index — commit remaps to ids
      expect(ref.label, 'onion');
      expect(ref.mention, MentionKind.isNew);
      expect(ref.portion, isNull);
    });

    test('a COLLECTIVE chip keeps more than one ref', () {
      final collective = payload.steps.last.tokens.whereType<RefToken>().single;
      expect(collective.refs, [3, 4]);
      expect(collective.mention, MentionKind.fraction);
    });

    test('both timer forms decode: single (low == high) and a range', () {
      final timers = payload.steps
          .expand((s) => s.tokens)
          .whereType<TimerToken>()
          .toList();
      expect(timers, hasLength(2));
      expect(timers[0].lowSeconds, 480);
      expect(timers[0].highSeconds, 480); // a single printed time
      expect(timers[1].lowSeconds, 2700);
      expect(timers[1].highSeconds, 3600); // a printed range
    });

    test('a NUMERIC step portion decodes with its unit', () {
      final ref = payload.steps[1].tokens.whereType<RefToken>().firstWhere(
        (r) => r.mention == MentionKind.rementioned,
      );
      expect(ref.refs, [5]);
      expect(ref.portion, isNotNull);
      expect(ref.portion!.qty, 1);
      expect(ref.portion!.unit, 'tbsp');
      expect(ref.portion!.qualifier, isNull);
    });

    test('a QUALIFIER-ONLY step portion decodes with no number', () {
      final ref = payload.steps.last.tokens.whereType<RefToken>().single;
      expect(ref.portion, isNotNull);
      expect(ref.portion!.qualifier, 'the rest');
      expect(ref.portion!.qty, isNull);
      expect(ref.portion!.qtyLow, isNull);
      expect(ref.portion!.qtyHigh, isNull);
      expect(ref.portion!.unit, isNull);
    });

    test('every step ref addresses a real line', () {
      for (final step in payload.steps) {
        for (final ref in step.tokens.whereType<RefToken>()) {
          for (final i in ref.refs) {
            expect(i, inInclusiveRange(0, flat.length - 1));
          }
        }
      }
    });
  });

  test('TimeFieldConverter is symmetric on both wire forms', () {
    // The one hand-written converter in the mirror, and the only place the
    // contract is polymorphic (`number | {low,high} | null`). Asymmetry here
    // would silently rewrite a printed time.
    const converter = TimeFieldConverter();
    for (final raw in <Object?>[
      null,
      5400, // scalar form
      {'low_seconds': 2700, 'high_seconds': 3600}, // range form
    ]) {
      final decoded = converter.fromJson(raw);
      expect(converter.toJson(decoded), raw, reason: 'round-trip of $raw');
    }
    // A scalar decodes to a zero-width range and re-encodes as a scalar, never
    // as a {low,high} pair — that is what keeps the wire form stable.
    expect(converter.toJson(payload.totalTimeSeconds), 5400);
    expect(converter.toJson(payload.cookTimeSeconds), {
      'low_seconds': 2700,
      'high_seconds': 3600,
    });
  });
}
