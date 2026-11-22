# Exec plan: receipts by email

- **Status:** draft (frames proposed, nothing built)
- **Owner:** agent
- **Roadmap step:** — (owner's ask)
- **Created:** 2026-11-22

## Goal

A receipt that arrives by email, or as a saved order file, reaches the review
without a camera. Owner: *"i'm now doing online shops more and getting
e-receipts also which doesn't fit our current pattern"*.

## Acceptance criteria

- [ ] An itemised receipt email, forwarded, appears as *1 to review*.
- [ ] An online order's saved file, mailed to the same address, does the same.
- [ ] The same order twice is one receipt. A later copy of a saved order
      offers an update.
- [ ] Weight beats quantity, a struck price is no charge, substitutes replace
      what was ordered, and a refunded line prices nothing.
- [ ] Nothing is a receipt before Save.
- [ ] Tests cover the new logic, and the prompt is proven on the real model.
- [ ] `PRIVACY.md`, `docs/SECURITY.md`, the specs and the board are updated.

## Approach

1. The reader takes text and PDF beside photos, evaluated on real orders kept
   in the gitignored local fixtures. Committed fixtures are synthetic.
2. Migration: the source `email`, an order reference, the pending table and
   the household's address. `ReceiptSource.fromDb` already reads an unknown
   source as `photo`, so the last release tolerates the value.
3. A Cloudflare Email Worker passes the raw message to an inbound function,
   which finds the household by the address, parses it and stores it pending.
   The Worker parses nothing: the free plan allows it 10 ms of CPU.
4. Receipts lists what is pending and opens the review that exists.

## Decision log

- 2026-11-22 — **One door: a private address.** An in-store shop emails an
  itemised receipt. An online order's email names no items, but *Save Order
  Details* saves a file that can be mailed to the same address.
- 2026-11-22 — **No inbox access.** Connecting Gmail reads a whole inbox for a
  few emails a week.
- 2026-11-22 — **Online and in store are the same store** (owner).
- 2026-11-22 — **The address is the credential**: random, replaceable and
  rate-limited. A sender is never trusted. Email is untrusted text, read by a
  model with no tools and a fixed schema.
- 2026-11-22 — **The least is kept.** The message is held as extracted text
  until Save or Dismiss, then deleted. A delivery address, a name and card
  digits never reach a note or a line.

## Notes / open questions

- The saved file is assumed to be a PDF. A real one is needed before step 1.
- Enabling Email Routing is the owner's, after checking the domain has no mail
  records in use.
- Gmail's automatic forwarding is set up on a computer and sends a
  confirmation to the address, which the pending list would have to show.
