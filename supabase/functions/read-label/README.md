# `read-label` — reading a nutrition panel off one photograph

The third model door, and by far the smallest. One photo of a nutrition label
goes in; what the panel PRINTED comes out. It exists because the owner was
typing macros in by hand, off another tab, one figure at a time.

It shares the two import doors' household gate and allowlist, the same Haiku
pin, the same photo caps, transport and failure shapes. Three things differ, all
for the same reason — a label is one image and one call:

- **No stream.** The answer is a plain JSON body: no `plan`, no stages, no
  heartbeat. The whole call fits inside the platform's idle cut-off, which
  `_shared/timeouts.test.ts` asserts rather than assumes.
- **No second tier.** There is nothing to structure afterwards, because a label
  IS the structure.
- **No database.** Not one statement, not even a SELECT. There is no Postgres
  seam in `live.ts` at all, and `no_write.test.ts` refuses a statement verb, the
  driver or the connection string's name in any file this door owns.

## What it reads, and what it refuses to do

```
serving      { amount, unit_printed, text_printed }
per_serving  { kcal, protein_g, carbohydrate_g, fat_g, fibre_g }
per_100      { basis: "g" | "ml", …the same five }   — or null
notes        [ "…what could not be read…" ]
```

**Every figure is one the label printed.** Null means "not printed, or not
legible" — never a zero, and never something worked out. The model is told, in
as many words, not to derive a per-serving figure from a per-100 column, not to
derive a per-100 column from a per-serving one, not to convert a unit and not to
add anything up. Two consequences worth stating out loud:

- **`per_100` exists only where the label prints such a column.** EU packs
  usually do; US "Nutrition Facts" panels usually do not. Where there is none,
  it is null, and the app derives per 100 from the serving with its own tested
  arithmetic (`Macros.per100From`). A per-100 column the model computed would be
  indistinguishable from one the pack printed, and would be believed.
- **Energy in kilojoules alone is null kcal, plus a note.** 2640 kJ is not 631
  kcal on that pack; it is a figure that pack does not state.

`carbohydrate_g` is TOTAL carbohydrate and `fat_g` is TOTAL fat, never the "of
which" row underneath. `fibre_g` is null on a panel that does not print it.

The prompt is `_shared/prompts/label.ts` — short, concrete, and carrying one
worked example of a two-column EU table, which is the case a reader is most
likely to get backwards. Its schema is checked by
`_shared/prompts/schema_keywords.test.ts`: structured outputs refuse `minimum`,
`pattern` and their kin, and the refusal only shows against the live API.

## The wire

`POST` with `{"images": ["<base64>"]}` — exactly one, at most 3 MB decoded
(shared with the import doors; the app already downscales). More than one is a
400: a panel is one panel, and the form has one set of fields.

| Status | Body               | When                                       |
| ------ | ------------------ | ------------------------------------------ |
| 200    | the `LabelReading` | it read                                    |
| 400    | `{error}`          | the body is not one usable image           |
| 422    | `{error}`          | something the person can act on            |
| 504    | `{error}`          | out of time; nothing was saved             |
| 500    | `{error}`          | anything else — the detail goes to the log |

The contract is `_shared/label_types.ts`, mirrored in Dart at
`app/lib/features/ingredients/domain/label_reading.dart`. Both ends coerce the
same way: a figure that is not a usable printed figure is null at both, because
null is what tells the form to leave that field alone.

## What it does NOT do

No tables, no migration, no review screen, no learning, no density, and no guess
at the ingredient's name or brand — the person had already named the row. The
reading lands in the form as a draft and the form's Save is the only thing that
writes.

## Tests

```
cd supabase/functions && deno task test
```

- `index.test.ts` — the body a request may be, the plain-JSON answer, and the
  three failure shapes in this door's voice.
- `_shared/adapters/label_schema.test.ts` — decode, null handling, a per-100
  column with an unusable basis, and a keyless construct.
- `auth.test.ts` — one allowlist, shared with both import doors.
- `no_write.test.ts` — the guarantee above, held by a source guard with a
  completeness check over the folder.

Scored live against three synthetic labels (a US panel, a two-column EU table, a
per-100-ml beverage) plus a skewed phone photo and a kilojoule-only pack: 55 of
55 printed fields.

## Deploy

`deploy-supabase.yml` ships it by name beside the two import doors. No new
secret: it uses the same `ANTHROPIC_API_KEY`, and the same
`IMPORT_ALLOWED_HOUSEHOLDS` — a household allowed to photograph a recipe is the
same household allowed to photograph a label.
