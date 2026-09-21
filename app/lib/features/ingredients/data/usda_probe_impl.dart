/// [UsdaProbe] over the `probe_usda` RPC.
///
/// The one place the app talks to Supabase REST about ingredients, because
/// `usda_food` is never synced (ADR-0005). A pick is applied through the
/// ordinary local write path. Every failure (no connection, no session, a
/// PostgREST error, an unexpected shape) is an empty list, never an exception
/// or a dialog.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/usda_probe.dart';

/// How long to wait for the server. Short on purpose, so being offline costs a
/// beat, not a stall.
const _probeTimeout = Duration(seconds: 4);

class SupabaseUsdaProbe extends UsdaProbe {
  const SupabaseUsdaProbe(this._client);

  final SupabaseClient _client;

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async {
    if (matchText.trim().isEmpty) return const [];
    try {
      final rows = await _client
          .rpc<dynamic>(
            'probe_usda',
            params: {'name': matchText, 'limit': limit},
          )
          .timeout(_probeTimeout);
      // `returns table` comes back as a list of rows — empty for "no
      // confident candidate", which is the common and uninteresting case.
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map)
            ?UsdaCandidate.tryParse({
              for (final e in row.entries) '${e.key}': e.value,
            }),
      ];
      // Deliberately broad: see the library doc. There is no failure mode
      // here that should reach the user as anything but "nothing came back".
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return const [];
    }
  }
}

/// The probe when no backend is configured (dev builds without
/// `--dart-define`s, widget tests). Answers nothing, as an offline device does.
class UnconfiguredUsdaProbe extends UsdaProbe {
  const UnconfiguredUsdaProbe();

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async =>
      const [];
}
