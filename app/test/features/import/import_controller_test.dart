import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mise/features/import/data/canned_payload.dart';
import 'package:mise/features/import/data/import_providers.dart';
import 'package:mise/features/import/domain/commit_payload.dart';
import 'package:mise/features/import/domain/import_repository.dart';
import 'package:mise/features/import/domain/line_validation.dart';
import 'package:mise/features/import/domain/reconciliation_payload.dart';
import 'package:mise/features/import/presentation/import_view_models.dart';

/// A fake edge function + a commit that records the payload instead of writing.
/// [gate], when set, holds `startImport` open so a second call can race it.
class _FakeImportRepository implements ImportRepository {
  CommitPayload? committed;
  int startCalls = 0;
  Completer<void>? gate;

  @override
  Future<ReconciliationPayload> startImport(ImportSource source) async {
    startCalls++;
    if (gate != null) await gate!.future;
    return ReconciliationPayload.fromJson(
      jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
    );
  }

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

      final id = await controller().commit(issuesByLine: null);
      expect(id, 'recipe-1');
      expect(container.read(importControllerProvider), isA<ImportCommitted>());
      // The two identical "Aleppo chilli flakes" lines coalesced to one stub.
      final stubNames = fake.committed!.stubs.map((s) => s.name).toList();
      expect(stubNames.where((n) => n == 'Aleppo chilli flakes'), hasLength(1));
    },
  );

  test('a second startImport while one is in flight is a no-op', () async {
    // Extraction is a billed LLM call; a double-tapped Import must fire one.
    fake.gate = Completer<void>();
    final first = controller().startImport(const ImportFromUrl('x'));
    await controller().startImport(const ImportFromUrl('x'));
    expect(fake.startCalls, 1);

    fake.gate!.complete();
    await first;
    expect(container.read(importControllerProvider), isA<ImportReconciling>());
  });

  test('an import abandoned mid-flight does not throw on the state write', () {
    // Riverpod 3 THROWS when a disposed notifier's state is written, so backing
    // out of /import while extraction runs must not blow up in release.
    fake.gate = Completer<void>();
    final pending = controller().startImport(const ImportFromUrl('x'));
    container.dispose();
    fake.gate!.complete();
    expect(pending, completes);
  });

  test('commit refuses a payload whose lines are not all valid', () async {
    await controller().startImport(const ImportFromUrl('x'));
    var state = container.read(importControllerProvider) as ImportReconciling;
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
    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.canCommit, isTrue); // structurally resolved…

    // …but one line's unit isn't one its ingredient admits. The gate lives in
    // `buildCommit`, not only in the view's disabled button.
    final issues = {
      for (final r in state.resolutions) r.lineIndex: <LineIssue>[],
    }..[0] = [LineIssue.unitNotAllowed];
    expect(() => controller().commit(issuesByLine: issues), throwsStateError);
    expect(fake.committed, isNull);
  });
}
