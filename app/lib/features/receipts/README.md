# Feature: receipts

A photographed receipt, read through the recipe import's own pipeline,
confirmed line by line, and kept whole — so what a week cost reads off the
receipts themselves, and every matched line with a pack is a price. Drawn on
the board's [Receipts](../../../../docs/product-specs/board/receipts.html) view;
behaviour is specified in
[import-and-matching.md §12](../../../../docs/product-specs/import-and-matching.md).

There is no second price table. A receipt is `receipt` + `receipt_line`, the
same two tables a hand-typed price writes one row each of
(`features/ingredients/domain/price.dart`).

## The rules

- **Nothing is written until Save.** The review is controller state, so an
  abandoned scan leaves the ledger as it was. Save writes the receipt and every
  kept line in one transaction.
- **The join is a flag, never a refusal.** The kept lines' sum is held against
  the printed subtotal — or, where the strip prints none, the total less tax.
  A sum that does not close is counted in the header, and Save still opens.
- **No alias is learned; the household's own answers carry over**
  ([§12.4.1](../../../../docs/product-specs/import-and-matching.md#1241-what-the-household-itself-remembers)).
  Locally: the pack pre-fills from one batched read (`packsByPrintedName`), its
  stored basis figure is never re-derived, and the saved-receipt edit path lands
  no pack. A line that arrived on the server's recalled match is
  `ReceiptLineDraft.remembered` until the person changes it. Both are filed
  under `name_printed`, which the app writes with the line and no edit moves.
  The ingredient page's `On receipts` section
  ([`ingredients/README.md`](../ingredients/README.md)) shows those names.
- **One screen for a receipt.** `/receipts/:id` is the same review, opened on
  the saved rows (`ReceiptScanController.open`). Save rewrites them in place —
  kept lines by id, new ones inserted, dropped ones tombstoned — and the printed
  totals and printed words never move.
- **A zero is never a price.** An unreadable figure arrives as `cents: 0` and
  is flagged, holding Save until somebody reads it off the paper.
- **The count rides on the line, never on the pack.** Both of the owner's shops
  print how many on a sub-row UNDER the item (`8 @ $2.99`, `Qty 4  $2.39 ea`);
  that sub-row attaches to the item above it and never becomes a line
  (`receipt_line.count`, migration 0050). The line's `cents` already include
  them all, so nothing about what the trip cost moves — what moves is the
  price, which divides by `count × pack_basis_amount`. The pack is what ONE of
  them comes in and carries to the next receipt; the count arrives fresh from
  the paper every time. The card reads `8 × block (16 oz) · 66¢ / 100 g`, and
  the COUNT chip beside PACK is the door. A by-weight sub-row
  (`Qty 0.73 lb @ $2.99/lb`) is a WEIGHT, never a count: the unit decides.
- **Identical lines are answered together.** A match, a pack, *Not food* or
  *it is food* lands on every line with the same printed words and figure that
  still stands where this one stood; the card says how many before the answer.
  A drop or a re-read figure is about one occurrence and never rides along
  (`domain/receipt_review.dart`). At Save, twins keeping the same measure mint
  one.

## The files

```
domain/                 PURE DART (invariant 2)
  receipt_payload.dart  the wire contract, decoded totally and forgivingly
  receipt_stage.dart    the four stages, over import's shared PipelineStage
  receipt_review.dart   the ONE map: flags, sums, the join, the Save label
  receipt_save.dart     the review as rows
  receipt_ledger.dart   filing by week and month, the band's second figure
  receipt_repository.dart  the two seams
data/
  remote_receipt_repository.dart  `import-receipt` over the import's SSE client
  replay_receipt_repository.dart  the same four stages, from a fixed payload
  sample_receipt_payloads.dart    a TJ's strip with a join, a discount and a
                                  by-weight line — and a variant whose paper
                                  says $3.49 more than its lines add up to
  receipt_repository_impl.dart    the ledger over local PowerSync SQLite
presentation/
  receipt_view_models.dart   the scan session: photos → checklist → review
  receipt_scan_view.dart     `/receipts/review`, all three states
  receipt_review_body.dart   the paper's own facts, then the lines
  receipt_line_card.dart     one line, money first
  receipt_pack_sheet.dart    *Say what the pack is*, + *keep as a measure*
  receipt_date_sheet.dart    *When was this shop* — the day moves, the clock stays
  receipt_ledger_view.dart   `/receipts`, and `/receipts/:id` hosting the review
```

## The one place a measure is minted

The import pipeline mints no measure; the household's own tap does. *Keep as a
measure* on the pack door names `482 g` as `bottle (17 oz)`, and Save writes
that measure on the row before the line that points at it. The pack carries
over either way (`landPack`); what a measure adds is a chip on the ingredient's
recipe lines and the Shop's rounding unit, so the toggle is off by default.

A measure the row already has is not minted twice. The label is read by the
shared rule (`ingredients/domain/measure_authoring.dart`), and a live measure
with the same label, case-insensitively, either agrees within
`kWholeMeasureTolerance` — the line points at it — or the sheet refuses, naming
both weights.

## The seam

`ReceiptImportRepository` is an interface so every screen can be driven from a
replay payload — no network, no billed model call — which is how the review,
the checklist and the Save gate are widget-tested against the real controller.

## Not built

The desk's three-column review is drawn in [the board's
hatch](../../../../docs/product-specs/board/not-built.html) and has a backlog
row. On a wide window the scan, the review and the ledger are the phone's
column at the 640 measure.
