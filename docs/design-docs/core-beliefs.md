# Core beliefs

The agent-first operating principles for this repo. Short, opinionated, and
meant to be enforced by tooling wherever possible. When one of these is violated
repeatedly, the fix is to promote it into a lint or structural test — not to
write a longer paragraph here.

## On the code

1. **The repo is the only context that exists.** If a decision isn't written
   down here, an agent (or a future human) can't see it. Push knowledge into the
   repo, don't leave it in chat.
2. **Enforce invariants, not implementations.** We care about boundaries,
   dependency direction, and correctness. Within those, an agent may express a
   solution however it likes. Parse/validate data at boundaries; don't guess at
   shapes deeper in.
3. **Domain logic is pure Dart.** The unit system and every `domain/` layer stay
   free of `package:flutter` so they're testable as plain functions. This is an
   invariant, enforced in CI.
4. **Prefer boring, legible dependencies.** Choose tools an agent can fully model
   from the training set and stable APIs. Occasionally a small in-repo helper
   beats an opaque package.
5. **Honest numbers over convenient numbers.** A stub ingredient is excluded from
   conversions and macros until a human completes it. Never fabricate density or
   macro data to make a total render.

## On the process

6. **Every change lands with a test and (if behaviour changed) a doc update.**
7. **Small, short-lived changes.** Prefer many small PRs over a big one. Pay down
   tech debt continuously (`docs/exec-plans/tech-debt-tracker.md`), not in bursts.
8. **Plans are artifacts.** Non-trivial work starts from a checked-in exec plan.
9. **Follow the build sequence.** The unit system underpins everything and is
   built and hardened first (`docs/exec-plans/roadmap.md`). Don't skip ahead.
