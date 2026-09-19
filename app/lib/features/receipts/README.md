# Feature: receipts

**Roadmap:** Next 1 — phase two of
[plan 0049](../../../../docs/exec-plans/active/0049-food-cost-receipts-and-meals-out.md).
Drawn on the board's [Receipts](../../../../docs/product-specs/board/receipts.html)
view.

A photographed receipt, read through the recipe import's own pipeline,
confirmed line by line, and **kept whole** — so what a week cost reads off the
receipts themselves, and every matched line with a pack is a price.

There is no second price table. A receipt is `receipt` + `receipt_line`
(migrations 0044/0046/0047), the same two tables a hand-typed price already writes
one row each of, so a scanned line and a typed one are the same fact read the
same way (`features/ingredients/domain/price.dart`).

## The six things that make this honest

**Nothing is written until Save.** The whole review is controller state. A scan
abandoned half way leaves the ledger exactly as it was, and every failure on
the way is safe to repeat.

**The join is a flag, never a refusal.** The kept lines' sum is held against
the printed subtotal — or, on a strip that prints none, the total less tax,
which the card says; when they disagree the card says how far apart and what
to look for, the header counts it, and Save still opens — the printed total is
the paper's and it stands. A sum that does not close means a line is missing or
doubled, which is something to look at rather than something to block on.

**The household's answers carry over; the vocabulary learns nothing.** A
receipt's text is one store's abbreviations, so confirming a match writes **no
alias** — there is no call to the learning path anywhere in this folder, and
`TJ ORG BANANAS` never becomes a word the recipe door, the picker or the search
can see. What a second receipt inherits is two things, neither of them a
vocabulary word:

- **the pack**, on the ingredient row: a matched line with no printed weight
  opens on the pack that row was last bought in, and a line sold by weight
  prices itself from the weight the paper printed;
- **the match**, recalled by the server per printed name off this household's
  own saved receipt lines (`_shared/receipt_memory.ts`). The cascade matched 0
  of 29 lines on the first real strip — a whole-string trigram cannot score
  `ORG TRICOLOR QUINOA` against `Quinoa` — and once somebody has said it, it
  does not have to. The recall is exact, never fuzzy; the **latest answer
  wins**, so correcting a saved receipt corrects the memory and there is no
  second list to maintain; a row retired since is no answer at all; and a
  recall that fails costs the receipt nothing.

A line that arrived on a recalled answer is `ReceiptLineDraft.remembered` and
its card says `as you matched it last time` beside `tap to change` — the one
`auto` that can be wrong for a reason a person can see. Changing it *is* the
correction, and it stops being remembered the moment they do, because it is
theirs now. `name_printed` is what all of this is filed under: the app writes
it with the line (migration 0047) and no edit moves it.

**One screen for a receipt.** `/receipts/:id` is the review, opened on the
rows instead of on a scan (`ReceiptScanController.open`). Everything that
confirmed the receipt corrects it — the store, the date's calendar door, a
line's match, pack, PRICE chip, *Not food*, a drop — and Save rewrites the rows
in place: kept lines by id, new ones inserted, dropped ones tombstoned. The
printed totals and each line's printed words are the paper's and never move.

**A zero is never a price.** A figure the reader could not make out arrives as
`cents: 0` and is *flagged* — it holds Save and drags the join open until
somebody reads it off the paper — rather than counted as a free line.

**One answer answers the line the receipt printed six times.** Six tubs of
tofu print six identical lines, and answering each of them separately is six
times the same work. So an answer — the match, the pack (its word included),
*Not food*, *it is food* — lands on every line that is that line again: the
same printed words, the same figure, and **standing exactly where this one
stands now**, which is what keeps it off a twin somebody already answered
differently. The open card says `×6 on this receipt — an answer here answers
them all` **before** the answer, so six cards settling at once is what the
person was told would happen. A correction to the paper never rides along: a
drop and a re-read figure are about one occurrence, and a doubled line is
dropped precisely because its twin is staying. `domain/receipt_review.dart`
holds the rule; at Save, six lines each keeping the same word as a measure
mint **one** measure and all point at it.

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
