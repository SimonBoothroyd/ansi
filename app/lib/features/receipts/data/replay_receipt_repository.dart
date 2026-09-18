/// [ReceiptImportRepository] that replays a fixed payload instead of calling
/// a server.
///
/// It exists so every screen in this feature is testable and walkable without
/// `import-receipt`: a widget test drives the real controller through it, and
/// a build pointed at it walks the whole flow — camera, checklist, review,
/// Save — with no network and no billed model call.
///
/// It narrates the same four stages, because the reading screen's honesty is
/// that it draws what the server SAID: a replay that skipped straight to the
/// payload would leave the checklist untested. `pace` is how long each stage
/// takes; zero makes a test instant and a real duration makes the walk look
/// like the thing it stands in for.
///
/// **Never a production fallback.** The app's scan door is the real function,
/// and an unconfigured build refuses rather than serving somebody else's
/// groceries (`receipt_providers.dart`).
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
