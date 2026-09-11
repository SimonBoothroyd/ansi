import 'dart:async';
import 'dart:convert';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/books/data/book_providers.dart';
import 'package:ansi/features/import/data/canned_payload.dart';
import 'package:ansi/features/import/data/import_providers.dart';
import 'package:ansi/features/import/domain/import_repository.dart';
import 'package:ansi/features/import/domain/line_validation.dart';
import 'package:ansi/features/import/domain/reconciliation_payload.dart';
import 'package:ansi/features/import/presentation/import_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_book_repository.dart';
import '../../helpers/fake_import_repository.dart';

/// The canned edge function, plus a [gate] that can hold `startImport` open
/// so a second call races the first.
class _GatedImportRepo extends FakeImportRepo {
  _GatedImportRepo()
    : super(
        ReconciliationPayload.fromJson(
          jsonDecode(cannedReconciliationPayloadJson) as Map<String, Object?>,
        ),
      );

  int startCalls = 0;
  Completer<void>? gate;

  @override
  Future<ReconciliationPayload> startImport(
    ImportSource source, {
    void Function(ImportProgress)? onProgress,
  }) async {
    startCalls++;
    if (gate != null) await gate!.future;
    return payload;
  }
}

void main() {
  late _GatedImportRepo fake;
  late ProviderContainer container;

  setUp(() {
    fake = _GatedImportRepo();
    container = ProviderContainer(
      overrides: [
        importRepositoryProvider.overrideWithValue(fake),
        bookRepositoryProvider.overrideWithValue(const FakeBookRepository()),
      ],
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
        // Resolve any line still missing an ingredient to a row — what the
        // review's create-new chain hands back once the form has popped.
        if (r.chosenIngredientId == null) {
          controller().updateResolution(
            r.lineIndex,
            (res) => res.resolveToIngredient(
              'ing-${res.lineIndex}',
              res.ingredientText,
            ),
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
      // Every committed line carries a real identity — the commit mints none.
      expect(
        fake.committed!.groups
            .expand((g) => g.lines)
            .every((l) => l.ingredientId != null || l.subRecipeId != null),
        isTrue,
      );
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

  test('dropping the lines that need work clears the Save gate, and they are '
      'not written', () async {
    await controller().startImport(const ImportFromUrl('x'));
    var state = container.read(importControllerProvider) as ImportReconciling;
    final before = state.resolutions.length;
    for (final r in state.resolutions) {
      final needsWork =
          r.chosenIngredientId == null || (r.isRange && r.quantity == null);
      if (needsWork) {
        controller().updateResolution(r.lineIndex, (x) => x.drop());
      }
    }

    state = container.read(importControllerProvider) as ImportReconciling;
    expect(state.unresolvedCount, 0);
    expect(state.canCommit, isTrue);

    await controller().commit(issuesByLine: null);
    final written = fake.committed!.groups
        .expand((g) => g.lines)
        .map((l) => l.lineIndex)
        .toList();
    expect(written, isNotEmpty);
    expect(written.length, lessThan(before));
    // Only the kept lines were written, and their flat indexes are unchanged
    // (a step ref pointing at a dropped one has nothing to land on).
    expect(
      written,
      everyElement(
        isIn([
          for (final r in state.resolutions)
            if (!r.isDropped) r.lineIndex,
        ]),
      ),
    );
  });

  test('an import with every line dropped is not committable', () async {
    await controller().startImport(const ImportFromUrl('x'));
    final state = container.read(importControllerProvider) as ImportReconciling;
    for (final r in state.resolutions) {
      controller().updateResolution(r.lineIndex, (x) => x.drop());
    }
    final emptied =
        container.read(importControllerProvider) as ImportReconciling;
    expect(emptied.canCommit, isFalse);
    expect(await controller().commit(issuesByLine: null), isNull);
    expect(fake.committed, isNull);
  });

  test('commit refuses a payload whose lines are not all valid', () async {
    await controller().startImport(const ImportFromUrl('x'));
    var state = container.read(importControllerProvider) as ImportReconciling;
    for (final r in state.resolutions) {
      if (r.chosenIngredientId == null) {
        controller().updateResolution(
          r.lineIndex,
          (res) => res.resolveToIngredient(
            'ing-${res.lineIndex}',
            res.ingredientText,
          ),
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

  group('the header draft', () {
    test('is seeded from the payload — servings and times prefilled, shelf '
        'life unset, filed into the default book', () async {
      await controller().startImport(const ImportFromUrl('x'));
      final state =
          container.read(importControllerProvider) as ImportReconciling;
      final header = state.header;
      expect(header.title, state.payload.title);
      expect(header.servingsBase, state.payload.servingsBase);
      // The canned page prints a total time and no cook time.
      expect(header.totalTimeSeconds, 1500);
      expect(header.cookTimeSeconds, isNull);
      expect(header.keepsForDays, isNull);
      expect(header.freezable, isFalse);
      expect(header.bookId, 'b1');
      expect(header.sectionId, isNull);
      // The preview reads its serving count straight off the draft.
      expect(state.servings, header.servingsBase);
    });

    test('every setter lands on the draft and rides the commit', () async {
      await controller().startImport(const ImportFromUrl('x'));
      var state = container.read(importControllerProvider) as ImportReconciling;
      for (final r in state.resolutions) {
        if (r.chosenIngredientId == null) {
          controller().updateResolution(
            r.lineIndex,
            (res) => res.resolveToIngredient(
              'ing-${res.lineIndex}',
              res.ingredientText,
            ),
          );
        }
        if (r.isRange) {
          controller().updateResolution(
            r.lineIndex,
            (res) => res.pickQuantity(1),
          );
        }
      }
      controller()
        ..setTitle('Tomato Pasta, ours')
        ..setServings(4)
        ..setYield(1.2, kg)
        ..setSecondYield(6, cup)
        ..setCookTime(20 * 60)
        ..setTotalTime(25 * 60)
        ..setKeepsForDays(3)
        ..setFreezable(true)
        ..setFreezerDays(60)
        ..setSection('s-quick');
      state = container.read(importControllerProvider) as ImportReconciling;
      expect(state.header.yields, [
        (qty: 1.2, unit: kg),
        (qty: 6.0, unit: cup),
      ]);
      // A header edit re-runs no vocab query: the validation key is about
      // the lines, and none of them moved.
      expect(state.validationKey, isNotEmpty);

      await controller().commit(issuesByLine: null);
      final c = fake.committed!;
      expect(c.title, 'Tomato Pasta, ours');
      expect(c.servingsBase, 4);
      expect(
        (c.yieldQty, c.yieldUnit, c.yieldQty2, c.yieldUnit2),
        (1.2, kg, 6, cup),
      );
      expect((c.cookTimeSeconds, c.totalTimeSeconds), (1200, 1500));
      expect((c.keepsForDays, c.freezable, c.freezerDays), (3, true, 60));
      expect((c.bookId, c.sectionId), ('b1', 's-quick'));
    });

    test('the header is only readable at the review', () {
      expect(() => controller().header, throwsStateError);
      // …and a setter outside it is a no-op rather than a throw.
      controller().setTitle('nothing to write on');
      expect(container.read(importControllerProvider), isA<ImportIdle>());
    });
  });
}
