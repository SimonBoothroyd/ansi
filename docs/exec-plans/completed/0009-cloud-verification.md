# Exec plan: Cloud verification & seeding harness

- **Status:** in progress — harness shipped + cloud migrated/verified
  (2026-08-28); remaining items are human-only (see the unticked criteria)
- **Owner:** agent (staged 2026-08-27 from the post-step-7 cloud-testing audit)
- **Roadmap step:** Step 7.5 — cloud verification & seeding
- **Created:** 2026-08-27

## Goal

Cloud health is verifiable from a clean checkout in minutes, repeatably and
without polluting the target; the cloud vocab carries the same macros/density
data as local. Today the only cloud verification is a one-off manual E2E
(2026-08-27) plus `smoke_auth.sh` — which mutates what it verifies (a new auth
user + membership per run, no teardown) and tests a *different* token flow than
the app's first run (it re-issues via password grant; the app's signup-token
path is exactly where the step-7 empty-first-sync bug lived).

## Acceptance criteria

- [x] `scripts/cloud_verify.sh` shipped, **strictly read-only**: JWKS
      reachable + ES256; `/auth/v1/settings` shows Google enabled + records
      autoconfirm state; auth health endpoint; PowerSync instance liveness;
      prints (does not run) a read-only SQL block for `supabase db query
      --linked` — migration count vs local, `add_household_claim` exists,
      RLS-enabled table count, WAL settings (`max_slot_wal_keep_size`),
      junk-household census. *2026-08-28: every Supabase-side check verified
      green against cloud (run curl-by-curl); a full script run still needs
      the PowerSync URL in `cloud.env` (human, dashboard-only).*
- [x] A committed, non-secret `cloud.env` (Supabase URL, publishable key,
      PowerSync instance URL — all public-by-design) so no dashboard
      archaeology is needed to target cloud. *Publishable key fetched via
      `supabase projects api-keys`; `CLOUD_POWERSYNC_URL` is still `FILL_ME`
      (dashboard-only — human pastes it).*
- [x] The PowerSync Cloud **stream YAML is committed**
      (`docker/powersync-cloud.streams.yaml`) as source of truth — previously
      the second copy of the household security boundary existed only in the
      PowerSync dashboard — plus `scripts/check_stream_drift.sh` (in
      `make docs-check`) diffing (table, column-list) pairs against
      `docker/powersync.yaml`. *Human: paste + deploy it in the dashboard.*
- [x] `smoke_auth.sh` gains: signup-token claim decode (the app's real
      first-run flow — expected claimless before onboarding), a
      **joined-vs-created** report (live member count + household age; the
      open-seat canary), and a documented human-run teardown (service-role
      janitor SQL) so smoke users stop accumulating. *Verified end-to-end
      against the local stack: run 1 CREATED, run 2 JOINED the open seat.*
- [x] Cloud vocab seeded with reference data: `seed_usda.sql` +
      `seed_prefill.sql` run against cloud (macros for the ~248 complete
      ingredients; local parity), under the post-0008 template-household
      model. *2026-08-28: the seeding commands were permission-denied in the
      agent session (the harness's cloud-mutation gate working as designed) —
      human runs the two §2 commands from `cloud-setup.md` and re-checks
      `cloud_verify`'s macros query. Migration 0008 itself IS pushed (9/9)
      and "Home" is flagged `is_template`.*
- [x] `cloud-setup.md`: dashboard-only config checklist with expected values
      (auth hook enabled, JWT audience `authenticated`, JWKS URI, redirect
      URLs, email-confirm state) + a dated **"last verified" ledger** (first
      entry 2026-08-28).
- [x] One real Google browser sign-in performed (human task — the only
      non-scriptable check), recorded in the ledger; tracker row retired.
- [x] Tests cover the new logic (stream-YAML drift check runs in
      `make docs-check`, i.e. every CI run).
- [x] Docs updated: `cloud-setup.md` (§3 now points at the committed streams
      file), `SECURITY.md` (both sync-rule files + drift check in the
      add-a-table checklist), tracker rows reviewed (Google-OAuth row stays —
      not yet performed; no cloud-vocab row existed to retire).

## Approach

1. `cloud.env` + `cloud_verify.sh` (curl-only checks first, SQL block printed
   for a human).
2. Export the live stream YAML from the dashboard → commit → drift check
   (extend `check_docs.sh` or a small script wired into `make ci`).
3. `smoke_auth.sh` modes + teardown doc.
4. Seed cloud (`supabase db query --linked -f …`), verify counts via the
   read-only block.
5. Runbook checklist + ledger; first ledger entry from this plan's run.
6. Human: Google sign-in (unblocked — the step-7 session fixes merged with
   the 7.4 hardening sweep).

## Decision log

- 2026-08-28 — Google flow surfaced one live UX bug: supabase_flutter's
  default in-app browser sheet stays open ("loading") after the
  `io.mise.app://login-callback` redirect — the app completes sign-in +
  onboarding underneath it. Fixed in `sign_in_view.dart` with
  `authScreenLaunchMode: LaunchMode.externalApplication`; dismissal behavior
  to be confirmed on the next cloud sign-in (tracker row).

- 2026-08-28 — **Done.** Google browser sign-in performed on the sim against
  cloud: consent screen → `io.mise.app://login-callback` redirect → session →
  `ensure_onboarded` → fresh household with the full template clone
  (291 rows, 248 with macros) — verified read-only in the cloud DB. ADR-0002's
  primary auth path is live end-to-end.
- 2026-08-28 — All criteria green except the Google sign-in. Simon ran the
  seeds (248/291 template rows carry macros — local parity), filled
  `cloud.env`, deployed the streams YAML, and ran the janitor; `cloud_verify`
  passes 7 ok / 0 fail. Second janitor pass needed for the `diag%` E2E user
  (the teardown example uses `smoke%`) — template household is now member-less
  with 0 live recipes. Ledger updated.
- 2026-08-27 — Staged. Read-only-by-default is the design center: the
  verification tool must never be the thing that pollutes the target (the
  local seat-pollution incident during the step-7 review came from a leftover
  smoke user).
- 2026-08-28 — Joined-vs-created discriminator: the plan's created-at
  heuristic alone false-reports CREATED when the joined household is < 2 min
  old (back-to-back smoke runs), so the script uses **live member count**
  (join ⇒ 2, create ⇒ 1) as the primary signal with household age as the
  secondary. Both paths exercised locally.
- 2026-08-28 — Sanctioned cloud mutations executed: `supabase db push`
  (migration 0008 → 9/9; "Home" now `is_template`). The two vocab seeds were
  **permission-denied** in the agent session and deliberately not retried —
  the deny-by-default cloud-mutation gate is the same posture this plan
  exists to protect; the human runs them (two commands, §2 of the runbook).
- 2026-08-28 — Pre-mutation census found the template model's one wrinkle:
  the 2026-08-27 E2E user (`diag…@mise.app`) holds a live seat in "Home",
  which 0008 then flagged as the template (templates must be member-less),
  plus that session's 2 recipes. Recorded in the ledger with janitor SQL
  (soft-delete only, human-run) rather than deleted by the agent — cloud
  deletions are out of the harness's writ by design.
- 2026-08-28 — `supabase projects api-keys` returns the secret key redacted
  (`sb_secret_…·····`), so fetching the publishable key for `cloud.env` never
  exposes a secret to the session. PowerSync's dashboard has no read API;
  `CLOUD_POWERSYNC_URL` stays human-pasted.

## Notes / open questions

- Management API (`GET /v1/projects/{ref}/config/auth`) could automate the
  hook/provider checks with a personal access token — optional upgrade, keep
  the tokenless curl path as the baseline.
- Agent sessions are (correctly) permission-blocked from `supabase db query
  --linked` and key-fetching; once the script exists, a scoped Bash allowlist
  entry makes it routinely runnable.

## Step-done checklist

- [x] Roadmap row updated: status flipped to 🟡, one line on what shipped and
      what awaits the human.
- [x] `docs/QUALITY.md` grade for every area touched matches reality (sync-layer
      row notes the scripted cloud verification).
- [x] `app/AGENTS.md` "Current focus" and command list still true (no app code
      touched; focus line just points at the roadmap).
- [x] Feature steps: `make test-sim` n/a — no app code in this step. Recorded
      instead: cloud_verify's Supabase-side checks all green against cloud
      (2026-08-28); full script run awaits `CLOUD_POWERSYNC_URL`.
- [x] Tech-debt rows: none added (no corners cut in the harness); Google-OAuth
      row NOT retired (sign-in still not performed); no cloud-vocab row existed
      to retire (0008 closed it structurally; the seed data itself is the one
      unticked criterion above).
- [x] `make ci` green.
