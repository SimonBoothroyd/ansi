/// The extract→match seam, canned: `startImport` hands back a fixed
/// reconciliation payload and `commit` records what the review screen resolved.
///
/// Every review-screen suite drives the same shape — pump a payload, act, then
/// assert on what a Save committed — so the recorded payload is where those
/// assertions land.
library;

import 'package:ansi/features/import/domain/commit_payload.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';

class FakeImportRepo implements ImportRepository {
  FakeImportRepo(this.payload);

  final ReconciliationPayload payload;

  /// What the last [commit] was handed, or null while Save has not landed.
  CommitPayload? committed;

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) async => payload;

  @override
  Future<String> commit(CommitPayload payload) async {
    committed = payload;
    return 'recipe-1';
  }
}
