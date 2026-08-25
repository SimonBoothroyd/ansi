# Tech debt tracker

Known, deliberate debt. Pay it down in small, continuous increments rather than
letting it compound. Add an item when you knowingly cut a corner; remove it when
you fix it.

| Added | Area | Debt | Cost if ignored | Plan |
|-------|------|------|-----------------|------|
| 2026-08-24 | scaffold | Package version floors in `app/pubspec.yaml` are caret ranges, not resolved/pinned. | Resolver drift between machines. | Run `flutter pub get` + commit `pubspec.lock` once the app boots, or pin floors. |
| 2026-08-24 | scaffold | `app/` has no generated platform folders (`android/`, `ios/`, `web/`) yet. | Can't build until generated. | Run `flutter create .` in `app/` (see `app/AGENTS.md`). |

_When empty, keep the header — an empty tracker is a healthy signal, not a file to delete._
