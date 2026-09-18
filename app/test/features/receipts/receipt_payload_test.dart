/// The wire contract, decoded.
///
/// Two things are pinned here beyond the field mapping, and both are honesty
/// rules rather than plumbing: the receipt's moment is read as **wall time**
/// (a late shop must not move a day when two phones read it), and decoding is
/// **total** — a field this build does not understand is ignored, and a
/// missing one reads as absent rather than as a zero.
library;

import 'dart:convert';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/receipts/data/sample_receipt_payloads.dart';
import 'package:ansi/features/receipts/domain/receipt_payload.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptPayload decode(String json) =>
    ReceiptPayload.fromJson(Map<String, Object?>.from(jsonDecode(json) as Map));

void main() {
  group('the sample strip', () {
    final payload = decode(sampleReceiptJson);

    test('carries the paper as printed', () {
      expect(payload.storePrinted, "TRADER JOE'S #135");
      expect(payload.purchasedAtPrinted, '09/13/26 05:42 PM');
      expect(payload.subtotalCents, 2846);
      expect(payload.taxCents, 82);
      expect(payload.totalCents, 2928);
      expect(payload.lines, hasLength(9));
      expect(payload.notes, hasLength(1));
      expect(payload.photoJoins.first.overlapLines, 2);
    });

    test('reads the receipt moment as wall time, zone and all removed', () {
      // 17:42 at the till is 17:42 on every device that reads it back. A
      // conversion would file a late shop on the next day seven hours west.
      expect(payload.purchasedAt, DateTime(2026, 9, 13, 17, 42));
      expect(payload.purchasedAt!.isUtc, isFalse);
    });

    test('a discount rides beside the cents, never inside them', () {
      final salmon = payload.lines[2];
      expect(salmon.cents, 604);
      expect(salmon.discountCents, 55);
      expect(salmon.paidCents, 549, reason: 'what you paid is the price');
    });

    test('a by-weight line carries its own pack', () {
      final onions = payload.lines[1];
      expect(onions.weight!.amount, 1.32);
      expect(onions.weight!.unit, lb);
      expect(onions.weight!.rateCents, 199);
      expect(onions.weight!.isPack, isTrue);
    });

    test('an auto match resolves, a suggest one only offers', () {
      expect(payload.lines[0].match!.auto, isTrue);
      expect(payload.lines[4].match!.auto, isFalse);
      expect(payload.lines[4].suggestions.map((s) => s.name), [
        'Cheddar',
        'Cheddar, mild',
      ]);
      expect(payload.lines[5].match, isNull);
      expect(payload.lines[5].lowConfidence, isTrue);
    });

    test('the four kinds arrive as themselves', () {
      expect(payload.lines[0].kind, ReceiptKind.item);
      expect(payload.lines[6].kind, ReceiptKind.notFood);
      expect(payload.lines[8].kind, ReceiptKind.tax);
      expect(ReceiptKind.item.isFood, isTrue);
      expect(ReceiptKind.fee.isFood, isFalse);
    });

    test('the join-apart variant differs only in what the paper says', () {
      final apart = decode(sampleReceiptJoinApartJson);
      expect(apart.subtotalCents, 3195);
      expect(apart.linesSumCents, payload.linesSumCents);
      expect(
        apart.lines.map((l) => l.cents),
        payload.lines.map((l) => l.cents),
      );
    });
  });

  group('decoding refuses to invent', () {
    test('an empty payload reads as absent, never as zero', () {
      final payload = decode('{}');
      expect(payload.storePrinted, isNull);
      expect(payload.purchasedAt, isNull);
      expect(payload.subtotalCents, isNull);
      expect(payload.totalCents, isNull);
      expect(payload.lines, isEmpty);
    });

    test('a kind this build does not know reads as not food', () {
      // The one reading that can never fabricate a price out of a row nobody
      // here understands.
      final payload = decode(
        '{"lines":[{"printed_text":"???","cents":100,"kind":"coupon_book"}]}',
      );
      expect(payload.lines.single.kind, ReceiptKind.notFood);
    });

    test('a weight in a word this catalog has not got is no pack', () {
      final payload = decode(
        '{"lines":[{"cents":100,"kind":"item",'
        '"weight":{"amount":2,"unit":"stone","rate_cents":50}}]}',
      );
      final weight = payload.lines.single.weight!;
      expect(weight.unit, isNull);
      expect(weight.isPack, isFalse, reason: 'it cannot price itself');
    });

    test('a line with no index takes its position', () {
      final payload = decode(
        '{"lines":[{"cents":1,"kind":"item"},{"cents":2,"kind":"item"}]}',
      );
      expect(payload.lines.map((l) => l.index), [0, 1]);
    });

    test('an unreadable figure arrives as a zero the review has to answer', () {
      final payload = decode(
        '{"lines":[{"printed_text":"TJ ????  ?.??","cents":0,"kind":"item", '
        '"low_confidence":true}]}',
      );
      expect(payload.lines.single.paidCents, 0);
      expect(payload.lines.single.lowConfidence, isTrue);
    });
  });
}
