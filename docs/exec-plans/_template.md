# Exec plan: <title>

- **Status:** draft | active | blocked | done
- **Owner:** <human/agent>
- **Roadmap step:** <e.g. Step 2 — single-user recipes>
- **Created:** YYYY-MM-DD

## Goal

One or two sentences: what "done" means, in observable terms.

## Acceptance criteria

- [ ] …
- [ ] Tests cover the new logic
- [ ] Docs updated (which ones?)

## Approach

Break the goal into small building blocks. Note the dependency order.

1. …
2. …

## Decision log

Append-only. Record choices and why, as they happen.

- YYYY-MM-DD — …

## Notes / open questions

- …

## Step-done checklist

The code landing is not the step landing. Tick these before setting Status to
done and moving this file to `completed/`.

- [ ] Roadmap row updated: status flipped, one line on what shipped and what was
      deliberately deferred.
- [ ] `docs/QUALITY.md` grade for every area touched matches reality.
- [ ] `app/AGENTS.md` "Current focus" and command list still true.
- [ ] Feature steps: `make test-sim` run on a booted simulator (the UI paths CI
      can't reach), and the result recorded here.
- [ ] Tech-debt rows **added** for corners knowingly cut, and **retired** (or
      narrowed) for debt this step paid off.
- [ ] `make ci` green.
