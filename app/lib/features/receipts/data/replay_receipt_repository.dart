/// [ReceiptImportRepository] that replays a fixed payload instead of calling a
/// server, so widget tests and a walkthrough build can drive the real
/// controller with no network.
///
/// It narrates the same four stages so the checklist is exercised too; `pace`
/// is how long each takes (zero in tests). Never a production fallback
/// (`receipt_providers.dart`).
library;

import 'dart:async';
import 'dart:convert';

import '../domain/receipt_payload.dart';
import '../domain/receipt_repository.dart';
import '../domain/receipt_stage.dart';
import 'sample_receipt_payloads.dart';

class ReplayReceiptRepository implements ReceiptImportRepository {
  const ReplayReceiptRepository({
    this.json = sampleReceiptJson,
    this.pace = Duration.zero,
  });

  /// The payload to answer with.
  final String json;

  /// How long each of the four stages takes.
  final Duration pace;

  @override
  Future<ReceiptPayload> readReceipt(
    ReceiptPhotos photos, {
    void Function(ReceiptProgress)? onProgress,
  }) async {
    onProgress?.call(const ReceiptPlanned(ReceiptStage.values));
    var elapsed = Duration.zero;
    for (final stage in ReceiptStage.values) {
      if (pace > Duration.zero) await Future<void>.delayed(pace);
      elapsed += pace;
      onProgress?.call(ReceiptStageDone(stage, elapsed));
    }
    return ReceiptPayload.fromJson(
      Map<String, Object?>.from(jsonDecode(json) as Map),
    );
  }
}
