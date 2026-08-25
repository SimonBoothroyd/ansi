# ADR-0003: Riverpod 3 + go_router + feature-first MVVM

- **Status:** Accepted
- **Date:** 2026-08-24

## Context

The spec fixed the framework and backend but left client-side state management,
navigation, and code organisation open. This is the one genuinely open call in
the initial scaffold, so it gets its own ADR — override it here if you disagree.

## Decision

- **Riverpod 3 with code generation** (`@riverpod`) for state and dependency
  injection. Rationale: compile-safe, no `BuildContext` needed, first-class
  provider overrides make ViewModels and repositories testable, `AsyncValue`
  gives clean loading/error/data branches — and it pairs naturally with
  PowerSync's reactive query streams (watch a query → a provider → the UI).
- **go_router** for declarative, deep-link-friendly navigation.
- **Freezed + json_serializable** for immutable domain models and DTOs.
- **Feature-first + MVVM** layout (Views, ViewModels, Repositories, Services),
  the structure Flutter's official architecture guidance recommends.

## Alternatives considered

- **Bloc** — excellent for large teams needing strict event/state discipline;
  heavier ceremony than a two-person hobby project needs.
- **Provider / setState** — fine for tiny apps; doesn't scale to the derived
  plan→cook→shop pipeline cleanly.

## Consequences

- We adopt `build_runner` codegen (`make gen`). Generated `*.g.dart` /
  `*.freezed.dart` files are committed so analysis and CI are deterministic.
- One state solution only — do not mix in Bloc "because a package wanted it".
