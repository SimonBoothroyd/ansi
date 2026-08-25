# Execution plans

Plans are first-class, checked-in artifacts (harness-engineering §"Plans are
treated as first-class artifacts"). They let an agent — or a human returning to a
task — pick up exactly where things stood, with the reasoning intact.

- **Trivial change?** No plan needed. Just do it (with a test).
- **Non-trivial change?** Copy [`_template.md`](./_template.md) into `active/`,
  named `NNNN-short-slug.md`. Keep its decision log updated as you go. When done,
  move it to `completed/`.
- [`roadmap.md`](./roadmap.md) is the standing, ordered build sequence with live
  status — the first thing to read before starting work.
- [`tech-debt-tracker.md`](./tech-debt-tracker.md) lists known debt to pay down
  continuously.
