# Exec plan: Cloud verification & seeding harness

- **Status:** draft
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

- [ ] `scripts/cloud_verify.sh` runs green against the cloud project from a
      clean checkout, **strictly read-only**: JWKS reachable + ES256;
      `/auth/v1/settings` shows Google enabled + records autoconfirm state;
      auth health endpoint; PowerSync instance liveness; prints (does not run)
      a read-only SQL block for `supabase db query --linked` — migration count
      vs local, `add_household_claim` exists, RLS-enabled table count, WAL
      settings (`max_slot_wal_keep_size`), junk-household census.
- [ ] A committed, non-secret `cloud.env` (Supabase URL, publishable key,
      PowerSync instance URL — all public-by-design) so no dashboard
      archaeology is needed to target cloud.
- [ ] The PowerSync Cloud **stream YAML is committed**
      (`docker/powersync-cloud.streams.yaml`) as source of truth — today the
      second copy of the household security boundary exists only in the
      PowerSync dashboard — plus a check that its table list matches
      `docker/powersync.yaml`.
- [ ] `smoke_auth.sh` gains: a signup-token mode (decode the claims of the
      *signup* token — the app's real first-run flow), prints whether the user
      **joined or created** a household (open-seat canary), and a documented
      human-run teardown (service-role janitor SQL) so smoke users stop
      accumulating.
- [ ] Cloud vocab seeded with reference data: `seed_usda.sql` +
      `seed_prefill.sql` run against cloud (macros for the ~248 complete
      ingredients; local parity), under the post-0008 template-household model.
- [ ] `cloud-setup.md`: dashboard-only config checklist with expected values
      (auth hook enabled, JWT audience `authenticated`, JWKS URI, redirect
      URLs, email-confirm state) + a dated **"last verified" ledger**. (The
      stale "onboarding users then join Home" line was already rewritten for
      the template-clone model by the 7.4 hardening sweep.)
- [ ] One real Google browser sign-in performed (human task — the only
      non-scriptable check), recorded in the ledger; tracker row retired.
- [ ] Tests cover the new logic (stream-YAML drift check at minimum).
- [ ] Docs updated: `cloud-setup.md`, `SECURITY.md` pointer, tracker rows.

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

- 2026-08-27 — Staged. Read-only-by-default is the design center: the
  verification tool must never be the thing that pollutes the target (the
  local seat-pollution incident during the step-7 review came from a leftover
  smoke user).

## Notes / open questions

- Management API (`GET /v1/projects/{ref}/config/auth`) could automate the
  hook/provider checks with a personal access token — optional upgrade, keep
  the tokenless curl path as the baseline.
- Agent sessions are (correctly) permission-blocked from `supabase db query
  --linked` and key-fetching; once the script exists, a scoped Bash allowlist
  entry makes it routinely runnable.

## Step-done checklist

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (n/a — no app
      code in this step; record the cloud_verify run here instead).
- [ ] Tech-debt rows added for corners knowingly cut, and retired for debt this
      step paid off (Google-OAuth row, cloud-vocab row).
- [ ] `make ci` green.
