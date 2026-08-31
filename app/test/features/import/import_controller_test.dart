import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/features/import/data/canned_payload.dart';
import 'package:mise/features/import/data/import_providers.dart';
import 'package:mise/features/import/domain/commit_payload.dart';
import 'package:mise/features/import/domain/import_repository.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/import/presentation/import_view_models.dart';

/// A fake edge function + a commit that records the payload instead of writing.
class _FakeImportRepository implements ImportRepository {
  CommitPayload? committed;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async =>
      ReconciliationPayload.fromJson(
        jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
      );

  @override
  Future<String> commit(CommitPayload payload) async {
    committed = payload;
    return 'recipe-1';
  }
}

void main() {
  late _FakeImportRepository fake;
  late ProviderContainer container;

  setUp(() {
    fake = _FakeImportRepository();
    container = ProviderContainer(
      overrides: [importRepositoryProvider.overrideWithValue(fake)],
    );
  });

  tearDown(() => container.dispose());

  ImportController controller() =>
      container.read(importControllerProvider.notifier);

  test('startImport moves Idle → Reconciling with resolutions', () async {
    expect(container.read(importControllerProvider), isA<ImportIdle>());
    await controller().startImport(const ImportFromUrl('x'));

    final state = container.read(importControllerProvider);
    expect(state, isA<ImportReconciling>());
    final reconciling = state as ImportReconciling;
    // The canned payload has unmatched lines (the chilli/basil), so it does not
    // start commit-ready.
    expect(reconciling.canCommit, isFalse);
    expect(reconciling.unresolvedCount, greaterThan(0));
    // Triage surfaces at least the two no-match groups (chilli fold + basil).
    expect(reconciling.reviewCount, greaterThan(0));
    // Not previewing until the user advances.
    expect(reconciling.previewing, isFalse);
  });

  test('showPreview is gated on a fully-resolved import', () async {
    await controller().startImport(const ImportFromUrl('x'));
    // Nothing resolved-through yet → showPreview is a no-op.
    controller().showPreview();
    var state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.previewing, isFalse);

    for (final r in state.resolutions) {
      if (r.chosenIngredientId == null && r.createStubName == null) {
        controller().updateResolution(
          r.lineIndex,
          (res) => res.resolveToNewStub(res.ingredientText),
        );
      }
      if (r.isRange) {
        controller().updateResolution(
          r.lineIndex,
          (res) => res.pickQuantity(1),
        );
      }
    }
    controller().showPreview();
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.previewing, isTrue);
    expect(state.canCommit, isTrue);

    // Back returns to triage without losing the resolutions.
    controller().backToTriage();
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.previewing, isFalse);
    expect(state.canCommit, isTrue);
  });

  test(
    'resolving every line + picking ranges enables commit, then commits',
    () async {
      await controller().startImport(const ImportFromUrl('x'));

      var state = container.read(importControllerProvider) as ImportReconciling;
      for (final r in state.resolutions) {
        // Resolve any line still missing an ingredient with a new stub.
        if (r.chosenIngredientId == null && r.createStubName == null) {
          controller().updateResolution(
            r.lineIndex,
            (res) => res.resolveToNewStub(res.ingredientText),
          );
        }
        // Pick the low endpoint for any range.
        if (r.isRange) {
          controller().updateResolution(
            r.lineIndex,
            (res) => res.pickQuantity(1),
          );
        }
      }

      state = container.read(importControllerProvider) as ImportReconciling;
      expect(state.canCommit, isTrue);

      final id = await controller().commit();
      expect(id, 'recipe-1');
      expect(container.read(importControllerProvider), isA<ImportCommitted>());
      // The two identical "Aleppo chilli flakes" lines coalesced to one stub.
      final stubNames = fake.committed!.stubs.map((s) => s.name).toList();
      expect(stubNames.where((n) => n == 'Aleppo chilli flakes'), hasLength(1));
    },
  );
}
