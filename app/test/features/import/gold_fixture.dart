/// Test helper: load a blessed gold extraction file and wrap it as a
/// [ReconciliationPayload].
///
/// The gold files under `evals/datasets/extraction/gold/` are `ExtractionResult`
/// shaped (`groups[].line_items[]`, no bands). A real reconciliation payload
/// adds a match band + candidates per line; here we wrap every line as an
/// unmatched `none` line (empty candidates), which is exactly what the client
/// must handle for a fresh import. Step tokens carry over verbatim — the gold
/// step JSON already matches the payload's `Step`/`StepToken` shape.
library;

import 'dart:convert';
import 'dart:io';

import 'package:mise/features/import/domain/reconciliation_payload.dart';

/// Reads and decodes a gold file (host filesystem; tests run from `app/`).
Map<String, Object?> loadGoldJson(String name) {
  final file = File('../evals/datasets/extraction/gold/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

/// Wraps a gold extraction as a `none`-banded reconciliation payload.
ReconciliationPayload goldPayload(String name) {
  final json = loadGoldJson(name);
  final groups = (json['groups']! as List).cast<Map<String, Object?>>();
  final steps = (json['steps'] as List? ?? const [])
      .cast<Map<String, Object?>>();
  return ReconciliationPayload(
    title: json['title']! as String,
    servingsBase: (json['servings_base'] as num?)?.toInt(),
    servingsRaw: json['servings_raw'] as String?,
    yieldRaw: json['yield_raw'] as String?,
    totalTimeSeconds: const TimeFieldConverter().fromJson(
      json['total_time_seconds'],
    ),
    cookTimeSeconds: const TimeFieldConverter().fromJson(
      json['cook_time_seconds'],
    ),
    truncated: (json['truncated'] as bool?) ?? false,
    imageQuality: _imageQuality(json['image_quality'] as String?),
    parseWarnings: (json['parse_warnings'] as List? ?? const []).cast<String>(),
    groups: [
      for (final g in groups)
        ReconGroup(
          name: g['name'] as String?,
          lines: [
            for (final li
                in (g['line_items']! as List).cast<Map<String, Object?>>())
              ReconLine(raw: RawLineItem.fromJson(li), band: MatchBand.none),
          ],
        ),
    ],
    steps: [for (final s in steps) Step.fromJson(s)],
  );
}

ImportImageQuality _imageQuality(String? raw) => switch (raw) {
  'degraded' => ImportImageQuality.degraded,
  'poor' => ImportImageQuality.poor,
  _ => ImportImageQuality.ok,
};
