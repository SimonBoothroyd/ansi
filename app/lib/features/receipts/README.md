# Feature: receipts

**Roadmap:** Next 1 — phase two of
[plan 0049](../../../../docs/exec-plans/active/0049-food-cost-receipts-and-meals-out.md).
Drawn on the board's [Receipts](../../../../docs/product-specs/board/receipts.html)
view.

A photographed receipt, read through the recipe import's own pipeline,
confirmed line by line, and **kept whole** — so what a week cost reads off the
receipts themselves, and every matched line with a pack is a price.

There is no second price table. A receipt is `receipt` + `receipt_line`
(migrations 0044/0046), the same two tables a hand-typed price already writes
one row each of, so a scanned line and a typed one are the same fact read the
same way (`features/ingredients/domain/price.dart`).

## The four things that make this honest

**Nothing is written until Save.** The whole review is controller state. A scan
abandoned half way leaves the ledger exactly as it was, and every failure on
the way is safe to repeat.

**The join is a flag, never a refusal.** The kept lines' sum is held against
the printed subtotal; when they disagree the card says how far apart and what
to look for, the header counts it, and Save still opens — the printed total is
the paper's and it stands. A sum that does not close means a line is missing or
doubled, which is something to look at rather than something to block on.

**The pack carries over; the words never do.** A receipt's text is one store's
abbreviations, so confirming a match teaches the vocabulary nothing and **no
alias is learned here** — there is no call to the learning path anywhere in
this folder. What a second receipt inherits is the **pack**: a matched line
with no printed weight opens on the pack that row was last bought in, and a
line sold by weight prices itself from the weight the paper printed.

**A zero is never a price.** A figure the reader could not make out arrives as
`cents: 0` and is *flagged* — it holds Save and drags the join open until
somebody reads it off the paper — rather than counted as a free line.

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
  receipt_ledger_view.dart   `/receipts` and `/receipts/:id`
```

## The one place a measure is minted

The import pipeline mints no measure and never has. The **household's own tap**
does, once: *keep as a measure* on the pack door names `482 g` as *bottle*, and
Save writes that measure on the row before the line, so the line points at the
word rather than at the unit it was typed in. Everywhere else on this screen,
a word the person did not ask for is not created.

## Where the seam is

`ReceiptImportRepository` is a seam rather than a direct call so every screen
here can be driven from a **replay payload** — no network, no billed model
call. That is what lets the review's states, the checklist's four rows and the
Save gate all be widget-tested against the real controller, and what lets the
owner walk the whole flow before `import-receipt` is deployed.

## What is not built

The desk's **three-column review** — the photos where the recipe review puts
the page — is drawn in [the board's
hatch](../../../../docs/product-specs/board/not-built.html) and has its own
backlog row. On a wide window today the scan, the review and the ledger are the
phone's column at the 640 measure, which works; what the width would buy is the
printed line standing beside the card that claims to read it.
