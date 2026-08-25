# Dependency references

Offline, in-repo knowledge of the key dependencies, so an agent doesn't have to
guess an API from a half-remembered training snapshot. Where a project publishes
an `llms.txt` (an LLM-oriented docs digest), we vendor it here.

Populate with `scripts/fetch_references.sh` (best-effort; needs network). Vendored
copies are snapshots — note the date you fetched them, and refresh when a
dependency's major version changes.

| Dependency | Why it's here | Source |
|------------|---------------|--------|
| Forui | UI component API (shadcn-style) | https://forui.dev/docs |
| PowerSync | Sync SDK, schema, connector API | https://docs.powersync.com/client-sdks/reference/flutter |
| Supabase | Auth, RLS, edge functions, CLI | https://supabase.com/docs |
| Riverpod | Providers, codegen, testing | https://riverpod.dev |
| go_router | Routing + deep links | https://pub.dev/packages/go_router |
| Freezed | Immutable models + unions | https://pub.dev/packages/freezed |

_These files are not committed by default (network-fetched). Run the script, then
commit the snapshots you want the harness to rely on._
