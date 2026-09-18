import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/receipts/domain/receipt_payload.dart';
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
    }
  });
}
