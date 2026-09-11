# Search & matching — one rule, three tiers

**What this is.** Every place on the phone that matches text a person typed
against a name calls one function, `searchRank`. This document says what that
function does, why each guard is the value it is, and — the part that matters
most — where the rule is deliberately *not* applied.

**Where the code is.** `app/lib/features/ingredients/domain/search_rank.dart`
(the rule), `search_query.dart` (the character normalizer it rests on),
`normalize.dart` and its TypeScript mirror `supabase/functions/_shared/
normalize.ts` (the phrase normalizer that writes every stored `match_text`).
The vectors that pin it: `app/test/features/ingredients/search_vectors.json`.

---

## 1. Why there is one rule

Before this, four surfaces searched typed text against a name under **three
different rules**, and they failed in opposite directions:

| | ingredient picker | planning recipe picker | editor's "Your recipes" |
|---|---|---|---|
| `almonds` → *Almond Cake* | would hit | miss | miss |
| `pasta tomato` → *Weeknight Tomato Pasta* | would hit | hit | **miss** (the whole query had to prefix) |
| `jalapeño` → *Grilled Jalapeño Poppers* | would hit | hit | **miss** (`[^a-z0-9]+` split words, so an accent was a word break) |
| `fungi` → *Gumbo z'Fungi* | would miss | **miss** (the apostrophe fuses the word) | hit |
| a single-word typo | empty list | none | none |

Three rules is the bug. Half-unifying is how three rules became three: a tier
that exists but is wired to only some of its callers drifts again. So there is
one function, and a cross-picker test asserts the two recipe pickers return
identical sets over the same corpus (`cross_picker_search_test.dart`).

---

## 2. The three tiers

Tiers are evaluated in order and the **first** one that hits wins. A tier-2 hit
can never outrank a tier-0 or tier-1 hit whatever the scores say — that is what
makes "did you mean" honest.

**Tier 0 — exact.** The normalized query, raw *or* per-token singularized,
equals one of the row's surfaces. Score 1.0. This is what puts **Onion** above
**Onion Powder** for `onion`.

**Tier 1 — every-token word prefix.** Every query token, in its raw or singular
form, is a *word* prefix of some word of the surface. Order-independent, so
`tomato pasta` and `pasta tomato` both land. Score is how much of the matched
words the query actually spelled.

**Tier 2 — typo-tolerant, guarded per token.** Runs **only when tiers 0 and 1
return nothing at all**. Every token must find a word scoring at least the
floor. Score is the mean of the per-token bests, always reported under every
tier-0/1 hit.

### The searchable surface (and the trap it avoids)

A row's surface is the **union** of its `match_text`, each live alias's
`match_text`, and the **character-normalized raw name**. The third is not
redundant. The phrase normalizer drops measure words, so
`normalizeMatchText('Green Goddess Chickpea Jars')` is `green goddess chickpea`
— **"Jars" is in the measure strip set and vanishes.** Indexing a name through
the phrase normalizer alone silently deletes any name word that happens to be a
measure: Jars, Sticks, Blocks, Head, Bunch, Packs, Slices. The server escapes
this because it normalizes *both* sides identically; the phone cannot, because a
typed query is deliberately only character-normalized. So the phone searches
both surfaces.

---

## 3. The guards, and why each number

Every value below was measured against the shipped seed vocabulary
(`supabase/seed/snapshot.jsonl`, a few hundred rows) over 30
hand-written single-word typos, 9 multi-word probes, 34 must-stay-quiet
queries and 477 machine-generated one-edit typos.

| Guard | Value | Why |
|---|---|---|
| distance | **OSA / Damerau-Levenshtein** — an adjacent transposition costs **one** edit, not two | The single highest-value line in the rule. Transposition is the most common human typo, and charging it double is why `soy suace` and `parsely` used to find nothing. Switching the metric alone moves systematic right-family recall from **47 % to 80 %**. |
| minimum token length, **single**-token query | **4** | Owner ruling, 2026-09-02 (the lane proposed 5). Four is what finds `almnd` → Almonds, `nion` → Onion and — the deciding probe — `aoli` → *Romesco Aioli*, which a five-character floor cannot reach at all. |
| minimum token length, **multi**-token query | **3** | A correctly spelled neighbour corroborates. This is what keeps `coconut mlk` and `soy suace` working while a lone `mlk` stays silent. |
| edit budget | **1 edit** for tokens 3–7 characters, **2** for 8+ | The binding guard. Length-relative, so a long word gets proportionally more forgiveness without a short one getting any. |
| per-token floor | **0.75** | Belt and braces. On this vocabulary it is not binding — the edit budget rejects everything it would — but it is the guard that still holds on a vocabulary of much longer names. |
| prefix tolerance | a token also scores against the word's leading `len(token)` characters | Lets a typo'd *prefix* of a longer name hit: `almnd` names `almond butter` as much as it names `almond`. |

### The rule in one sentence

> A token shorter than the minimum is not *refused* — it just may never be
> **guessed at**. It has to be spelled right.

### What four characters costs, stated plainly

Six short queries now guess where they were silent: `nion → Onion`,
`pear → Peach`, `beef → Beets`, `pork → Portobello Mushroom`,
`lamb → Burger Buns`, `crab → Black Pepper`. Each is a real word landing on a
different food, and this vocabulary is vegan so several have no honest answer at
all. Wrong-family-at-rank-1 rises from 4 % to 7 % across the systematic probes;
every case inspected is a near-sibling with the intended row at rank 2–3
(`papika → Sweet Paprika` when Smoked was meant), which is a visible ranking
wobble in a three-row band, not a wrong commit.

**They are acceptable only because of the band.** They appear under a
`DID YOU MEAN` header, in a list that exists only because nothing was spelled
right, and nothing is ever resolved unattended. The band is what buys the floor.

### Where the phone stops guessing

Three characters. A genuinely mistyped three-character token — `rce`, `oyl`,
`tfu`, `mlk`, `crn`, `wtr` — stays silent (measured). `egg`, `oil`, `oat`, `ol`,
`ric`, `sal`, `tom` never reach tier 2 at all, because they are exact word
prefixes of real rows and tier 1 answers first. The picker says so when the
query was under the floor, rather than leaving the silence mysterious.

---

## 4. The band rule

Tier 2 runs only when tiers 0 and 1 are empty, so a guessed list is **the whole
list or it is absent** — a guess is never a tail of weak rows under strong ones.
Guesses render under a `DID YOU MEAN` header (`DidYouMeanHeader` in
`shared/picker_shell.dart`), in the caution colour, in all three pickers. The
add-new footer stays under both cases, because a guess must never be the only
way out.

**An empty band is an answer, not a bug.** "No match for 'chikn thigh'" is the
honest result in a vegan vocabulary that has no chicken thigh. Never invent one.

The band's rule is per **corpus**, not per row: the editor's line picker
searches ingredients and recipe titles side by side, and each section is
labelled on its own evidence.

### The band's fourth caller: the ingredient form's name field

The same header, over the same tier, asked of a name being **typed** rather
than searched. When the name field is left, the form asks the household's one
name namespace two questions in order (`domain/name_namespace.dart`): is this
name already somebody's — an exact answer over `match_text`, which refuses the
save — and, only when it is not, was it *nearly* somebody's. The second is
`searchRank` over every live name and alias, and the band rule decides what is
shown: a word-prefix hit is a spelling, not a guess, so `Onion` beside the
household's `Onion Powder` offers nothing. At most three rows, one per row
however many of its names matched.

It obeys §5 exactly. On `/ingredients/new` a tap **asks** ("Use Sauerkraut
instead?") and, on a yes, pops the form with the existing row — the person
resolved it, not the rule. On a row that already exists the near names are
shown and nothing more: renaming onto one of them would be a merge, and
nothing here merges rows.

---

## 5. Tier 2 is retrieval for a human to pick, never a resolution

This is the most important line in the document, and it is what stops the next
unification pass from "finishing the job" and breaking it.

`_findVocabRow` in `import_repository_impl.dart` re-resolves a candidate name
against the vocabulary **unattended**: one row, at commit time, writing the
answer into a saved recipe. It gets **tiers 0 and 1 only, forever**. A guess
there is a wrong ingredient on a line nobody reviewed — the never-invent
invariant, and what ADR-0004 exiles.

Within those two tiers it ranks with `searchRank`, exactly as the pickers do —
the SQL `LIKE` pass only selects the candidates — so the seam nobody reviews
and the list everybody sees cannot disagree about which row is the best match.

It *does* search aliases, for the same reason the picker does: the learning
loop's absorbed phrasing ("coco milk" → Coconut Milk) is a **spelling the
household taught us**, not a guess.

And it gets the tiers it is allowed **from the same rule, not from a second
copy of it**: the seam selects its candidates with a LIKE pass in SQL and then
orders them with `searchRank`, so `tom` commits the row the picker would have
offered first — and it refuses tier 2, which is the one place the shared rule
is deliberately given less of itself.

The asymmetry is pinned by a test that asserts both halves at once: the same
query against the same row is offered by the picker as a labelled guess and
refused by the seam.

---

## 6. What the server does differently, and why (D4)

The server's cascade (`_shared/match.ts`) keeps pg_trgm and its bands,
**unchanged**. It is not an oversight; the two sides do different jobs:

1. **The server commits; the phone offers.** A line scoring `auto ≥ 0.85`
   starts pre-resolved. A guard tuned for "a human is looking at a list" is the
   wrong guard for "this line starts resolved".
2. **Symmetry is what makes the server work.** Both sides go through the same
   `normalize`. A query-side-only rule would break the property the whole
   cascade rests on.
3. **Every calibrated number would move.** `BAND_AUTO_MIN`,
   `BAND_SUGGEST_MIN` and `TRIGRAM_FLOOR` were set against 426 eval cases and
   the extraction benchmark. Evals are explicitly not a merge gate, so the
   regression would be invisible until someone reran them.
4. **pg_trgm does a job Levenshtein cannot** — index-backed over the whole
   vocabulary in one query, and genuinely better on multi-word drift
   (`coconut mlk` → 0.67 `suggest`).

The failure profiles are complementary, not contradictory: trigram is strong
where edit distance is weak and vice versa. The measured consequence — the
server surfaces only **6 %** of single-word one-edit typos — is a *stated*
property in the tech-debt tracker, not a surprise waiting to be re-derived.

**The one exception, already taken:** diacritic folding. `jalapeno` scored
0.500 against `jalapeño`, just under `BAND_SUGGEST_MIN`, so an import line
printed without the tilde got no candidates at all. That is a normalization
miss, not a fuzziness question, and it recurs with `crème`, `açaí` and
`piment d'Espelette`. Both mirrors of `normalize` now fold Latin diacritics
onto their base letter. Dart has no Unicode normalizer in its core library, so
the precomposed letters are tabled explicitly against the TypeScript `NFD` —
the shared vectors pin the two together, and the table's bound (Latin-1
Supplement plus Latin Extended-A) is stated in its doc comment.

---

## 7. What pins it

- **`search_vectors.json`** — one file, read three ways: by `searchRank` alone
  (`search_rank_test.dart`), by the same queries through **real SQLite**
  (`ingredient_repository_test.dart`, which proves the SQL tier-0/1 pass and
  the Dart tier-2 pass agree), and by the title corpus.
  `refusals` is the guard's spine — every entry must return nothing;
  `tier1_answers` is its mirror — tier 2 must never run for them.
- **`cross_picker_search_test.dart`** — the same corpus and query driven
  through **both** recipe picker widgets, asserting identical rendered sets,
  over the exact queries the audit measured them disagreeing on.
- **`normalize_vectors.json`** — the phrase normalizer's Dart/TypeScript
  parity, extended with the diacritic cases and the invariant words
  (`molasses`), and since plan 0023 read by **both** suites rather than
  copied into one.

## 8. Stated bounds

- **Tier 2 loads the whole live vocabulary and scores it in Dart**, with no SQL
  `LIMIT` — deliberately, because a cap would silently stop typo tolerance
  working for whatever fell off the end as a household's vocabulary grew. It is
  specified correct to roughly **2 000 rows** on a phone. Past that it needs an
  index, and that is a tracker row rather than a silent degradation.
- **The Dart diacritic table covers Latin-1 Supplement and Latin Extended-A.**
  A codepoint outside them (Vietnamese `ộ`) folds on the server and not on the
  phone. Extend the table, and the vectors, when a vocabulary needs one.
