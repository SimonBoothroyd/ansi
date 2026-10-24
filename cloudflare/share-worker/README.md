# share-worker

The share host's Cloudflare Worker: `getansi.app/r/*` → the `share-recipe` edge
function ([plan 0051](../../docs/exec-plans/active/0051-recipe-share-link.md)),
and `getansi.app/privacy`, the app's privacy policy.

Live since `v0.28.0`, deployed as `ansi-share` by `deploy-supabase` step 3b.
`getansi.app` is registered with Cloudflare Registrar in the same account, and
the Worker owns it as a custom domain (`wrangler.toml`), so the DNS record and
certificate are Cloudflare's to manage; it also answers on its `workers.dev`
address. Setting it up again, and turning it off:
[`docs/cloud-setup.md` §3d](../../docs/cloud-setup.md).

Supabase serves no HTML from a function on its shared `*.supabase.co` domain, so
the page cannot be opened there. This Worker stands on the share host, forwards
the two paths the function answers, and sets the page's headers itself. It knows
nothing about recipes.

The privacy policy is the one page it serves itself. `privacy.ts` imports the
repository's [`PRIVACY.md`](../../PRIVACY.md) as text
(`import … with { type: "text" }`): `wrangler` bundles the file as it stands in
the checkout it deploys from, and Deno's tests read the same file, so there is
no copy to fall behind. It renders the Markdown the policy uses — headings,
paragraphs, `-` lists, bold, italic, inline code, links — and escapes everything
else; the tests fail if a word of the file is missing from the page or a
Markdown mark is left in it. A change to `PRIVACY.md` reaches the page with the
next `deploy-supabase` run. Health Connect's permission screen opens this
address (`PermissionsRationaleActivity.kt`), and the Play listing's privacy
policy must be the same page.

| Request                                                      | Answer                                                                            |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `GET /r/<22-character token>`                                | the function's page, as `text/html` with the page's security policy and `noindex` |
| `GET /r/share.js?v=<hash>`                                   | the function's bundle, as `text/javascript`, cached as the function says          |
| `GET /privacy`                                               | `PRIVACY.md` as a page of its own, indexable, cached five minutes                 |
| `GET /privacy/`                                              | a 301 to `/privacy`, the one address                                              |
| anything else                                                | a 404 of its own; the origin is never asked                                       |
| an origin that fails or errors                               | a 502 page, uncached, with nothing of the origin's in it                          |
| an origin that redirects, or answers anything but 200 or 404 | a 404; the redirect is not followed or passed on                                  |

`worker.ts` is Web-standard TypeScript: `makeWorker` takes the network as an
argument, so `worker.test.ts` runs under Deno like the functions' tests
(`make worker-test`, and the backend CI; `deno.json` turns on the text import
and lets the tests read `PRIVACY.md`). `wrangler` only bundles and deploys it.
The function's URL is the `SHARE_ORIGIN` variable, passed at deploy time by
`deploy-supabase.yml` from the project ref — never committed.

Setting up the domain and the token:
[`docs/cloud-setup.md` §3d](../../docs/cloud-setup.md).

## The whole chain, locally, without Cloudflare

```
# the function, against the local database (see its README)
SUPABASE_DB_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres \
SHARE_BASE_URL=http://127.0.0.1:8788 \
  deno run --allow-all --config supabase/functions/deno.json \
  supabase/functions/share-recipe/index.ts &

# the Worker exactly as wrangler bundles it, in front of the function
cd cloudflare/share-worker
npx --yes wrangler@4.135.0 deploy --dry-run --outdir /tmp/share-worker \
  --var SHARE_ORIGIN:http://127.0.0.1:8000
deno eval --ext=ts '
  const mod = await import("file:///tmp/share-worker/worker.js");
  Deno.serve({ port: 8788 }, (req) =>
    mod.default.fetch(req, { SHARE_ORIGIN: "http://127.0.0.1:8000" }));'

# then open http://127.0.0.1:8788/r/<token>
```
