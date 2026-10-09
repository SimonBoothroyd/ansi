# share-recipe

A recipe's public, read-only page, by the token in its link
([plan 0051](../../../docs/exec-plans/active/0051-recipe-share-link.md)).
Public: deployed with no JWT check, so this function is the whole boundary.

| Path                        | Answer                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `GET …/r/<token>`           | the page, rendered on the server — its JSON-LD and link preview are in the HTML; 404 for a revoked, deleted or unknown token |
| `GET …/r/share.js?v=<hash>` | the bundle the page loads for its servings stepper and timers; immutable when the hash is current                            |
| anything else               | 404, or 405 for a method other than GET and HEAD                                                                             |

## Files

| File                   |                                                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `index.ts`             | the pure handler: paths, refusals, headers                                                                       |
| `payload.ts`           | the one query: a live share's recipe, the sub-recipes it reaches, as the rows the app reads (`recipe_rows.dart`) |
| `bundle.ts`            | evaluates the bundle and holds its source                                                                        |
| `live.ts`              | the Postgres pool (`SUPABASE_DB_URL`) and `SHARE_BASE_URL`                                                       |
| `share_page.js`        | **generated** — the app's `features/share/page` compiled to JS                                                   |
| `share_page_source.ts` | **generated** — the same source as a string, served to browsers                                                  |

The two generated files come from `make share-bundle`
(`scripts/share_bundle.sh`), which also renders the payload fixture
(`app/test/features/share/testdata/share_payload.json`) with the bundle in Deno.
The app's CI rebuilds them and fails when the committed copies are stale. Never
edit them by hand.

## Running it locally

```
make share-bundle
SUPABASE_DB_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
SHARE_BASE_URL=http://127.0.0.1:8000 \
  deno run --allow-all --config supabase/functions/deno.json \
  supabase/functions/share-recipe/index.ts
# then open http://127.0.0.1:8000/r/<token from share_recipe()>
```

The query test runs against that same database when asked:

```
SHARE_TEST_DB_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
  deno test --allow-all --config supabase/functions/deno.json \
  supabase/functions/share-recipe/payload.test.ts
```

It inserts its own households and rolls them back. Under `deno task test` it is
reported as ignored.
