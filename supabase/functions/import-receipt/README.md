# `import-receipt` — reading a photographed till receipt

The second import door. Photos of one receipt go in; what the paper printed
comes out, with every food line put through the household's own match cascade
and every seam between photos named.

It is deliberately `import-recipe`'s twin. Same household gate and allowlist,
same Haiku pin, same streaming transport and budgets, same SSE stage events,
same failure shapes. What differs is the document — and the one thing a receipt
has that a recipe does not, which is a printed subtotal the reading can be
checked against.

The product design is
[`docs/product-specs/import-and-matching.md` §12](../../../docs/product-specs/import-and-matching.md),
and the screens are on the board (`not-built.html`, the four receipt frames).

## The pipeline

```
photos → ① transcribe (vision)  → one transcription PER PHOTO
       → join by position        → one strip + the seams  (_shared/receipt_join.ts)
       → ② structure             → what the paper printed (_shared/prompts/receipt.ts)
       → ⑥ match the item lines  → the existing cascade   (_shared/match.ts)
       → ReceiptPayload
```

Two model calls, and nothing between them that thinks:

- **The join is ours.** `transcribe` returns one string per photo, never a
  spliced strip. The seam is the longest run of identical consecutive lines
  shared by the end of photo _n_ and the start of photo _n+1_, found by code
  with tests. A model asked to splice would have to decide whether a repeated
  line is an overlap or a second banana — and a receipt honestly prints the same
  item twice when two were bought. It is never asked. When no run is found the
  photos are concatenated and a note says so; the reconcile figure is the
  backstop.
- **The match is ours.** The model never sees the vocabulary and never matches
  (ADR-0004). The cascade runs afterwards over each item line's printed words,
  and because those words are a store's abbreviations it answers `suggest` far
  more often than it does on a recipe line. That is honest, and the review is
  built for it.
- **Nothing learns.** No alias is written from a receipt (ADR-0004). What
  carries over between shops is the _pack_, on the ingredient row, written by
  the app at Save, and the household's own answer per printed name — a match or
  a fold, either way round — recalled off its saved receipt lines
  (`_shared/receipt_memory.ts`). `no_alias.test.ts` holds it two ways: a SQL spy
  under the real matcher asserts every statement the function issues is a
  `SELECT`, and a source guard over every file the function owns asserts a write
  cannot be introduced without failing that test first.

## The wire

`POST` with `{"images": ["<base64>", …]}` — the photos in order, top to bottom.
At most 8, at most 3 MB decoded each (shared with the recipe door). The answer
is `text/event-stream`:

| Event       | Data                  | When                                     |
| ----------- | --------------------- | ---------------------------------------- |
| `plan`      | `{stages}`            | first, before any work                   |
| `stage`     | `{stage, elapsed_ms}` | as each one completes                    |
| `heartbeat` | `{elapsed_ms}`        | at most every 10 s _during_ a model call |
| `result`    | the `ReceiptPayload`  | last, on success                         |
| `error`     | `{error}`             | last, instead, on failure                |

The stage ids are `received`, `read`, `written`, `matched`. The **wording is the
app's** — the board says "Photos received", "Photos read", "Writing the receipt
out…", "Lines matched" — because copy belongs where the screen is.

The payload contract is `_shared/receipt_types.ts`, pinned by
`__fixtures__/receipt_payload.golden.json` and mirrored in Dart. Money is
integer cents throughout. The reconcile figure is

```
lines_sum_cents = Σ(item.cents − item.discount_cents) + Σ(not_food.cents) + Σ(fee.cents)
```

returned beside `printed.subtotal_cents`. The server states both numbers and
stops: the review draws the join card, and a disagreement is a flag, never a
refusal.

## Running it locally, with no API key

Everything after the model — the join, the money and date readers, the cascade,
the assembly, the HTTP edges — is deterministic, so a saved reading drives the
whole function end to end. Two synthetic fixtures are committed:

```
supabase start                                   # the local stack

SUPABASE_DB_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
RECEIPT_EXTRACT_FIXTURE=$PWD/supabase/functions/import-receipt/testdata/tj_three_photos.json \
  deno run --allow-all --config supabase/functions/deno.json \
  supabase/functions/import-receipt/index.ts
```

then `POST {"images":["<any base64>"]}` with a bearer token carrying a
`household_id` claim for a household the local DB has seeded. The replay adapter
never looks at the bytes, and it hands back the fixture's photos **unjoined**,
so a replay run exercises the real seam-finder rather than skipping it.

`make functions-up` serves both doors the same way, with one wrinkle: it mounts
only `supabase/functions` into the runtime container, so the fixture path has to
be the container's.

Two locks keep this local, neither of them a warning: the variable appears in no
deploy script and no `supabase secrets` row, and the loader **refuses** when
`ANTHROPIC_API_KEY` is set — which a deployed function always has, or it could
not read a receipt at all. `replay.test.ts` holds both.

## Fixtures — and the one that is never committed

`testdata/` holds **synthetic** transcriptions, written by hand around no real
receipt: a Trader Joe's-style strip in three photos (with the same item printed
twice, on purpose) and a Whole Foods-style one with a `PRIME SAVINGS` deduction.
Each says `SYNTHETIC` in the file, and a test asserts it — along with asserting
that neither carries a run of five or more digits.

**Never commit a real receipt.** This repo is public and a receipt carries a
card's last four and a loyalty number. The owner's own go in

```
supabase/functions/import-receipt/__fixtures__/local/
```

which is gitignored (the same pattern the extraction corpus uses under
`evals/`). A local fixture is the same shape as a committed one:

```jsonc
{
  "provider": "claude-haiku-receipt",
  "photos": ["…photo 1's transcription…", "…photo 2's…"],
  "raw": {
    "content": [{ "type": "text", "text": "{…the structure JSON…}" }],
    "stop_reason": "end_turn"
  }
}
```

`raw` is the provider's VERBATIM response, decoded here by the same decoder the
live call uses, so a malformed fixture fails loudly at wiring rather than
surfacing as an empty receipt.

## Tests

```
cd supabase/functions && deno task test            # everything
deno task golden-receipt                           # rewrite the payload golden
```

- `_shared/receipt_join.test.ts` — the seam: found, not found, three photos, and
  the repeated item that must survive.
- `_shared/receipt_parse.test.ts` — money (`$3.49`, `3,49`, `−0.55`, `0.55-`,
  `(0.55)`), the date, the weight units.
- `_shared/receipt_assemble.test.ts` — the reconcile arithmetic, the discount
  fold, by-weight lines, which photo a line came from, and what an unreadable
  figure does (counts as nothing, flags itself, names itself in a note).
- `_shared/adapters/receipt_schema.test.ts` — the schema round-trip.
- `index.test.ts` — the stage order on the wire, the failure shapes, the caps.
- `auth.test.ts`, `replay.test.ts`, `no_alias.test.ts`,
  `golden_payload.test.ts`.

## Deploy

`deploy-supabase.yml` ships it by name beside `import-recipe`. The secrets are
the same two rows — `ANTHROPIC_API_KEY` and `IMPORT_ALLOWED_HOUSEHOLDS` — set by
hand; there is deliberately no second allowlist, because a household allowed to
photograph a recipe is the same household allowed to photograph its receipt.
