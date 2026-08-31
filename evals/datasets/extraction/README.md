# Extraction fixtures

The dataset for the extraction / provider benchmark (lane D — charter
`docs/exec-plans/active/0018-import-benchmark.md`).

- `gold/` — the blessed structured gold: one `<recipe>.json` per source,
  conforming to `gold/_SCHEMA.md` (mirrors the frozen `ExtractionResult`). This
  is the **oracle** — read-only, never mutated by the scorer. `gold/_INDEX.md`
  lists every file with its confidence notes.
- `images/` — the source photos (12). **Gitignored**: they carry GPS EXIF and are
  copyrighted cookbook pages, so only the derived gold is committed. The scorer
  works keyless from the gold alone (it reconstructs a faithful page text); the
  photos are only needed for the keyed D1/D3 vision stages.
- The 36 `supabase/seed/scripts/recipe_urls.txt` pages feed the `jsonld` /
  `page_text` web paths via lane A's `jsonld.ts` (wired but gated — see the
  `blobFromUrl` seam in `runner/run_extraction_live.ts`).

How it is scored — rubric, stages, paths, ledger, and how to run keyless vs.
live — is in `runner/EXTRACTION.md`.
