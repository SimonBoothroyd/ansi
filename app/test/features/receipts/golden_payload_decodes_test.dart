import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/receipts/domain/receipt_payload.dart';
import 'package:ansi/features/receipts/domain/receipt_review.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server's golden payload is the contract's one worked example. If the
/// function's shape drifts, this is the test that says so on the app side
/// before a phone does.
void main() {
  test("the server's golden receipt payload decodes on the app side", () {
    final file = File(
      '../supabase/functions/import-receipt/__fixtures__/receipt_payload.golden.json',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'the golden moved — update the path',
    );
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final payload = ReceiptPayload.fromJson(json);
    expect(payload.lines, isNotEmpty);
    expect(payload.lines.length, (json['lines']! as List).length);
    expect(payload.linesSumCents, json['lines_sum_cents']);
    for (final line in payload.lines) {
      expect(line.printedText, isNotEmpty);
      // The title's words: present, and never carrying the line's figure.
      expect(line.namePrinted, isNotNull);
      expect(line.printedText, contains(line.namePrinted));
    }
    // Every match on the golden is the CASCADE's — a fixture has no household
    // to have answered — and the flag rides the wire on all of them, so this
    // side can tell the two apart at all.
    final matched = payload.lines.where((l) => l.match != null).toList();
    expect(matched, isNotEmpty);
    for (final line in matched) {
      expect(line.match!.remembered, isFalse);
    }
    expect(initialReceiptDrafts(payload).every((d) => !d.remembered), isTrue);
  });

  test('a remembered match decodes as the household’s own answer', () {
    final line = ReceiptLineOut.fromJson(const {
      'index': 0,
      'printed_text': 'ORG TRICOLOR QUINOA  4.49',
      'name_printed': 'ORG TRICOLOR QUINOA',
      'cents': 449,
      'kind': 'item',
      'match': {
        'ingredient_id': 'vocab-quinoa',
        'confidence': 1,
        'kind': 'auto',
        'remembered': true,
      },
    }, fallbackIndex: 0);
    expect(line.match!.remembered, isTrue);
    expect(line.match!.auto, isTrue);
    expect(line.match!.confidence, 1);
  });

  test('a server that sends no flag is simply not remembering', () {
    // Decoding is total and forgiving: an absent field reads as absent, never
    // as a claim.
    final line = ReceiptLineOut.fromJson(const {
      'printed_text': 'TJ SRIRACHA  3.99',
      'cents': 399,
      'kind': 'item',
      'match': {'ingredient_id': 'v', 'confidence': 0.9, 'kind': 'auto'},
    }, fallbackIndex: 0);
    expect(line.match!.remembered, isFalse);
  });
}
