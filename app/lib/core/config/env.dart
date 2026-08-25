/// Compile-time configuration, injected via `--dart-define` (see the Makefile).
/// Nothing here is secret: the Supabase anon key is public by design; real
/// protection is Row-Level Security (see docs/SECURITY.md).
library;

abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const powersyncUrl = String.fromEnvironment('POWERSYNC_URL');

  /// True when the core config is present. Fail fast in bootstrap if false.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
