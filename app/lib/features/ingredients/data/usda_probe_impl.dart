/// [UsdaProbe] over the `probe_usda` RPC (migration 0016, plan 0020 D7b).
///
/// The one place in the app that talks to Supabase REST about ingredients.
/// That is a deliberate exception to "reads come from PowerSync's local
/// SQLite", and it is the same exception ADR-0005 already forces: `usda_food`
/// is not synced and never will be, so the only way to ask it anything is to
/// ask the server. The answer is one candidate, and it is applied through the
/// ordinary local write path — nothing here bypasses sync.
///
/// **Every failure is a null.** No connection, no session, a PostgREST error,
/// a shape the migration does not promise: all of them mean "nothing came
/// back", because the 0014/0015 trigger is still there and still enriches the
/// row when it uploads. Turning a network miss into an exception here would
/// put an error dialog in front of a user whose only crime was being on a
/// train (board frame f: a failure comes back to the form with the reason
/// under it, never as a dialog).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/usda_probe.dart';

/// How long to wait before deciding the server is not going to answer.
///
/// Short on purpose: a creation flow awaits this before opening the form, so
/// the cost of being offline must be a beat, not a stall. The trigger path
/// picks up whatever this misses.
const _probeTimeout = Duration(seconds: 4);

class SupabaseUsdaProbe implements UsdaProbe {
  const SupabaseUsdaProbe(this._client);

  final SupabaseClient _client;

  @override
  Future<UsdaCandidate?> probe(String matchText) async {
    if (matchText.trim().isEmpty) return null;
    try {
      final rows = await _client
          .rpc<dynamic>('probe_usda', params: {'name': matchText})
          .timeout(_probeTimeout);
      // `returns table` comes back as a list of rows — empty for "no
      // confident candidate", which is the common and uninteresting case.
      if (rows is! List || rows.isEmpty) return null;
      final first = rows.first;
      if (first is! Map) return null;
      return UsdaCandidate.tryParse({
        for (final e in first.entries) '${e.key}': e.value,
      });
      // Deliberately broad: see the library doc. There is no failure mode
      // here that should reach the user as anything but "nothing came back".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return null;
    }
  }
}

/// The probe when there is no backend configured — a dev build with no
/// `--dart-define`s, and every widget test. Answers null, which is exactly
/// what an offline device answers, so no caller needs a second code path.
class UnconfiguredUsdaProbe implements UsdaProbe {
  const UnconfiguredUsdaProbe();

  @override
  Future<UsdaCandidate?> probe(String matchText) async => null;
}
