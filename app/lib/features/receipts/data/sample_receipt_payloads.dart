/// A fixed receipt payload, so every screen in this feature can be driven
/// without a server.
///
/// A strip shot in three photos that carries every shape the review draws: a
/// matched line with no pack, two by-weight lines, a discount, a suggested
/// match, a nameless line, two not-food lines and a tax line.
/// [sampleReceiptJoinApartJson] changes one printed figure so the lines fall
/// $3.49 short of the subtotal.
///
/// It lives in `lib/` because `replay_receipt_repository.dart` serves it. Never
/// a production fallback. The `ingredient_id`s are placeholders; tests seed a
/// matching vocabulary.
library;

/// The strip, with the printed subtotal agreeing with the lines.
const sampleReceiptJson = '''
{
  "store_printed": "TRADER JOE'S #135",
  "purchased_at_printed": "09/13/26 05:42 PM",
  "purchased_at": "2026-09-13T17:42:00",
  "printed": { "subtotal_cents": 2846, "tax_cents": 82, "total_cents": 2928 },
  "lines_sum_cents": 2846,
  "photos_joined": [
    { "from": 0, "to": 1, "overlap_lines": 2 },
    { "from": 1, "to": 2, "overlap_lines": 2 }
  ],
  "notes": ["The join between the second and third photo was hard to read."],
  "lines": [
    {
      "index": 0, "printed_text": "TJ ORG BANANAS  3.49",
      "name_printed": "TJ ORG BANANAS", "cents": 349,
      "discount_cents": 0, "kind": "item", "weight": null,
      "match": { "ingredient_id": "vocab-banana", "confidence": 0.94,
        "kind": "auto" },
      "suggestions": [], "low_confidence": false, "photo": 0
    },
    {
      "index": 1, "printed_text": "YELLOW ONIONS  1.32 lb @ 1.99/lb  2.63",
      "name_printed": "YELLOW ONIONS",
      "cents": 263, "discount_cents": 0, "kind": "item",
      "weight": { "amount": 1.32, "unit": "lb", "rate_cents": 199 },
      "match": { "ingredient_id": "vocab-onion", "confidence": 0.97,
        "kind": "auto" },
      "suggestions": [], "low_confidence": false, "photo": 0
    },
    {
      "index": 2, "printed_text": "ATLANTIC SALMON  1.10 lb @ 5.49/lb  6.04",
      "name_printed": "ATLANTIC SALMON",
      "cents": 604, "discount_cents": 55, "kind": "item",
      "weight": { "amount": 1.10, "unit": "lb", "rate_cents": 549 },
      "match": { "ingredient_id": "vocab-salmon", "confidence": 0.91,
        "kind": "auto" },
      "suggestions": [], "low_confidence": false, "photo": 0
    },
    {
      "index": 3, "printed_text": "TJ SRIRACHA  3.99",
      "name_printed": "TJ SRIRACHA", "cents": 399,
      "discount_cents": 0, "kind": "item", "weight": null,
      "match": { "ingredient_id": "vocab-sriracha", "confidence": 0.88,
        "kind": "auto" },
      "suggestions": [], "low_confidence": false, "photo": 1
    },
    {
      "index": 4, "printed_text": "TJ MED CHDR SHRD  3.79",
      "name_printed": "TJ MED CHDR SHRD", "cents": 379,
      "discount_cents": 0, "kind": "item", "weight": null,
      "match": { "ingredient_id": "vocab-cheddar", "confidence": 0.62,
        "kind": "suggest" },
      "suggestions": [
        { "ingredient_id": "vocab-cheddar", "name": "Cheddar",
          "confidence": 0.62 },
        { "ingredient_id": "vocab-cheddar-mild", "name": "Cheddar, mild",
          "confidence": 0.58 }
      ],
      "low_confidence": false, "photo": 1
    },
    {
      "index": 5, "printed_text": "TJ ORG LEMONS  1.98",
      "name_printed": "TJ ORG LEMONS", "cents": 198,
      "count": 3, "each_cents": 99,
      "discount_cents": 0, "kind": "item", "weight": null,
      "match": null, "suggestions": [], "low_confidence": true, "photo": 1
    },
    {
      "index": 6, "printed_text": "PAPER TOWELS  6.99",
      "name_printed": "PAPER TOWELS", "cents": 699,
      "discount_cents": 0, "kind": "not_food", "weight": null,
      "match": null, "suggestions": [], "low_confidence": false, "photo": 2
    },
    {
      "index": 7, "printed_text": "BAG FEE  0.10",
      "name_printed": "BAG FEE", "cents": 10,
      "discount_cents": 0, "kind": "not_food", "weight": null,
      "match": null, "suggestions": [], "low_confidence": false, "photo": 2
    },
    {
      "index": 8, "printed_text": "TAX  0.82",
      "name_printed": "TAX", "cents": 82,
      "discount_cents": 0, "kind": "tax", "weight": null,
      "match": null, "suggestions": [], "low_confidence": false, "photo": 2
    }
  ]
}
''';

/// The same strip, printed $3.49 higher than its lines add up to — the shape
/// a lost line makes, and the join card's ⚠ state.
final sampleReceiptJoinApartJson = sampleReceiptJson
    .replaceFirst('"subtotal_cents": 2846', '"subtotal_cents": 3195')
    .replaceFirst('"total_cents": 2928', '"total_cents": 3277');
