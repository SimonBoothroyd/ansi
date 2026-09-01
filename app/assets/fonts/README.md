# Bundled fonts

All three are SIL Open Font License 1.1 (see `OFL.txt`), from google/fonts:
- **Spectral** (serif — titles, group headers) — ofl/spectral
- **IBM Plex Mono** (data — quantities, units, scale factors, mono-caps labels) — ofl/ibmplexmono
- **Inter** (interface text) — provided by Forui (`packages/forui/Inter`), not bundled here

Bundled (not fetched at runtime) because the app is offline-first. Wired into
the type roles in `lib/core/theme/ansi_theme.dart`.
