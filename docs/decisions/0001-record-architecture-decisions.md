# ADR-0001: Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

We want the reasoning behind significant choices to be discoverable later, by
both humans and coding agents, without archaeology through chat logs or commits.

## Decision

Use lightweight Architecture Decision Records (ADRs), one Markdown file per
decision, numbered sequentially in `docs/decisions/`. Each records context, the
decision, and consequences. ADRs are immutable once accepted; a reversal is a new
ADR that supersedes the old one (noted in both).

## Consequences

- The "why" travels with the repo and is diff-reviewable.
- `AGENTS.md` and `architecture.md` link to ADRs instead of restating rationale.
