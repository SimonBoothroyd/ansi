# Exec plan: spend and stores, on the desk

- **Status:** draft (frames proposed, nothing built)
- **Owner:** agent
- **Roadmap step:** — (owner's ask)
- **Created:** 2026-11-22

## Goal

At a desk the household can ask where the money goes, whether one store is
dearer than another, and what to buy where this week.

## Acceptance criteria

- [ ] Receipts at the expanded width gains *Spend* and *Stores*. The phone is
      unchanged.
- [ ] Spend reads by month, store and category, with non-food and fees apart.
- [ ] Stores compares only what was bought at both, prints how much that is,
      and refuses a winner the data does not support.
- [ ] Every figure opens to the receipt lines behind it.
- [ ] This week's list names each item's usual cheaper store. An extra trip is
      suggested only above the household's threshold.
- [ ] Tests cover the new logic. ADR-0017, the spec and the board are updated.

## Approach

1. Spend, over the receipts that exist.
2. The typical price, one pure function.
3. Stores.
4. This week, with the threshold column (the only migration).

## Decision log

- 2026-11-22 — **Ballpark, and a deal does not set a price** (owner). The
  typical price is per ingredient and store over 90 days: one vote per
  shopping day, the median, the dearer middle on an even count, so it is
  always a price really paid.
- 2026-11-22 — **Variants are the same ingredient** (owner). No "not the same
  thing" list.
- 2026-11-22 — **The threshold is settable, $5 to begin with** (owner).
- 2026-11-22 — **Thin data still ships** (owner: *"the app grows with us"*).
  It says *about the same* within 5 %, *too close to call* when leaving out
  any one item flips the answer, and *seen once* beside a single visit.

## Notes / open questions

- **Open:** does the typical price also replace the latest in recipe and week
  costs, and the cheapest seen on the Shop? Recommended. It amends ADR-0017
  and the Shop ruling in plan 0056.
- Wrong saved packs move a comparison more than prices do, so a row behind a
  figure opens its receipt, where it can be corrected.
