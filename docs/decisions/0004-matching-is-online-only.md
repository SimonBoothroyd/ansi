# ADR-0004: Matching is online-only; extraction is a server-side LLM

- **Status:** Accepted (from import-and-matching design doc §2, §4)
- **Date:** 2026-08-24

## Context

Ingredient matching is the hardest correctness problem in the app. The naive
approach — ship a reference vocabulary and an embedding model to the phone and
fuzzy-match on device — is heavy and error-prone.

## Decision

Fuzzy matching happens **only at import time**, and import is **always online**.
The entire match engine (normalize → exact → trigram → optional embedding →
stub) lives server-side in a Supabase edge function / Postgres RPC. The
extraction step is a single call to a Flash-tier multimodal LLM that reads the
page/photo and emits raw structured lines; **the model never sees the vocabulary
and never matches** — matching is our deterministic job.

Only resolved, human-readable `ingredient` rows sync to the device. On-device
"Add ingredient" search is exact/prefix retrieval over that small synced set.

## Consequences

- No on-device embedding model; no 8k-row reference set on the phone.
- The receipt door's **match memory** — the household's own past answers per
  printed name, recalled from its saved receipt lines — sits inside this
  decision rather than beside it: the recall is a server-side `SELECT` in the
  same edge function, the phone does no matching of its own, and the answer is
  exact rather than fuzzy. It is not an alias and the vocabulary matcher never
  sees it (`import-and-matching.md` §12.4.1).
- The match engine is independently testable server-side (see `evals/`).
- Chip references in steps are stored as **data** (line-item indices), not
  detected at render time — runtime detection would drag matching back onto the
  device. See design doc §4.6.
- If you ever need offline import, this decision must be revisited explicitly.
