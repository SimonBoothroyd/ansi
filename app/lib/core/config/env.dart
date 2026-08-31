/// Compile-time configuration, injected via `--dart-define` (see the Makefile).
/// Nothing here is secret: the Supabase anon key is public by design; real
/// protection is Row-Level Security (see docs/SECURITY.md).
library;

import 'package:meta/meta.dart';

abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const powersyncUrl = String.fromEnvironment('POWERSYNC_URL');

  /// True when the core config is present. Fail fast in bootstrap if false.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// The defines by the name a `--dart-define` flag uses, so an error message
  /// can quote what the caller actually has to fix.
  static Map<String, String> get defines => {
    'SUPABASE_URL': supabaseUrl,
    'SUPABASE_ANON_KEY': supabaseAnonKey,
    'POWERSYNC_URL': powersyncUrl,
  };

  /// Throws a [StateError] when the app is only *half* configured.
  ///
  /// All-blank is the supported local/dev mode ([isConfigured] is false and the
  /// import feature falls back to its canned payload). All-set is production.
  /// Anything between is a foot-gun: an empty `SUPABASE_ANON_KEY` alongside a
  /// real URL built and "initialised" happily, then bounced OAuth three screens
  /// later with a bare 401 ("No API key found in request"). Call this before
  /// `Supabase.initialize`.
  static void assertDefinesUsable() => checkDefines(defines);
}

/// The guard behind [Env.assertDefinesUsable], over an explicit map so it is
/// testable — the real defines are compile-time constants a test cannot set.
@visibleForTesting
void checkDefines(Map<String, String> defines) {
  final blank = [
    for (final e in defines.entries)
      if (e.value.trim().isEmpty) e.key,
  ];
  // Nothing set at all is local/dev mode, not a mistake.
  if (blank.isEmpty || blank.length == defines.length) return;
  final subject = blank.length == 1
      ? '${blank.single} is'
      : '${blank.join(', ')} are';
  throw StateError(
    '$subject empty — check your --dart-define flags. '
    'Set every one of ${defines.keys.join(', ')}, or none of them for '
    'local/dev mode.',
  );
}
