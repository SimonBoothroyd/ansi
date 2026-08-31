# Import v1 — review jank (running log)

Rough edges caught while driving the real import on the sim (2026-08-31). **Not
fixing now** — collected here so they don't get lost; triage into the tech-debt
tracker / a polish pass later.

## Reconciliation / recipe view

- **Method-step chips render the amount but NOT the ingredient.** A step reads
  "Add the chopped `1`, `0.5`, `0.25`, `1`, `0.5 cup`…" — bare quantities, no
  ingredient names. The tokenized-step fold is dropping the ref `label`; a chip
  should show the ingredient (label) + its live amount, not the number alone.
  (High-impact — the chips are near-useless as-is.)
- **Too many unit chips in the amount editor.** A matched ingredient dumps its
  entire measure set + allowed units + imprecise words — Tomato showed ~13
  (piece · tomato medium/large/small · cherry · plum · slice medium/large ·
  wedge · slice thin small · g · pinch · dash · handful · to taste), Red Onion
  ~9. Overwhelming. Trim / prioritise the few most-likely, collapse the rest
  behind a "more".
- **Redundant "from source" line.** e.g. "from source: 2–3 cloves garlic cloves,
  sliced" — the raw amount and the ingredient text overlap ("cloves" twice).
  De-dupe the reference string.
- **Header "N to review" doesn't decrement** as lines are resolved (stuck at
  "4 to review" while the Save button's "N line(s) need you" does update).
  Reconcile the two counters.
- **Every cup-measured produce flags "pick a supported unit"** (mango, tomato,
  onion, avocado all needed a manual unit pick) because cup has no density for
  them. Common enough that seeding densities / a smarter default (offer the
  produce's own count-measure pre-selected) would remove a lot of manual taps.

- **No-quantity items dump the full raw line into the amount slot.** "Tortilla
  chips (to serve (optional))" shows that entire parenthetical as the "amount"
  (because there's no parsed qty/unit) — janky. A no-amount / "to serve" item
  should render a blank/"—" amount with the qualifier in NOTES, never the raw
  ingredient line in the amount column. (Same family as the pinch/handful
  raw-text fallback.)

- **Library doesn't refresh after an import commit.** A freshly-imported recipe
  doesn't appear on the Library screen until you switch tabs and back (which
  forces a re-watch). The library's watched query isn't re-firing on the commit's
  writes — likely the LEFT-JOIN watch trap ([[mise-powersync-watch-left-join]]):
  select a column from every table the commit touches. (Functional bug, not
  cosmetic — promoted to the tech-debt tracker.)

## Add here as we find more.
