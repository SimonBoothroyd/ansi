# ADR-0002: Flutter + Forui + Supabase + PowerSync

- **Status:** Accepted (carried from product spec §2)
- **Date:** 2026-08-24

## Context

A shared, offline-tolerant recipe app for two people, Android first with web as a
cheap stretch. Hobby-scale budget (free tiers).

## Decision

- **Flutter** for the client — one codebase for Android now and web later;
  Impeller for smooth rendering.
- **Forui** for UI — shadcn-style, minimalist, MIT, requires Flutter 3.44+.
  `fl_chart` for macro charts (stretch).
- **Supabase** (Postgres + Auth + Storage) as backend; recipe photos in Storage,
  not the DB.
- **PowerSync** for offline sync — local SQLite with an upload queue, native
  Supabase integration.
- **Google OAuth** via Supabase Auth.

## Consequences

- Anyone added to the household needs a Google account.
- Free-tier caveats to remember: set a smaller `max_wal_size` on Supabase to
  avoid WAL runaway with PowerSync on an idle hobby instance; the free Supabase
  instance pauses after ~1 week idle and must be resumed.
- Web support in PowerSync is in beta (`^1.9.0`) — fine for the stretch goal,
  test before relying on it.
