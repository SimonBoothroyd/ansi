/// Test doubles for [IngredientRepository].
///
/// The interface carries a write half (the form, density, default measure,
/// delete). Screens that only *read* the vocab shouldn't have to restate it,
/// so [ReadOnlyIngredientRepo] answers the whole interface with the empty,
/// harmless value and throws from the writes — subclass it and override only
/// the lookup the screen actually drives. Screens that exercise the manager
/// use [FakeIngredientRepo], an in-memory implementation that keeps the
/// vocabulary write semantics honest (a rename rewrites `match_text`, a form
/// completes only with macros, delete is refused while a reference count is
/// set).
library;

import 'dart:async';

import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';

/// A vocabulary that answers every read with nothing and refuses every write.
///
/// Screens that merely *look up* an ingredient get the whole interface from
/// here; a suite that needs one lookup to answer overrides that one method.
class ReadOnlyIngredientRepo implements IngredientRepository {
  const ReadOnlyIngredientRepo();

  @override
  Future<Ingredient?> byId(String id) async => null;

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => const {};

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      (rows: const <Ingredient>[], guessed: false);

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Stream<Ingredient?> watchIngredient(String id) => Stream.value(null);

  @override
  Stream<List<IngredientAlias>> watchAliases(String ingredientId) =>
      Stream.value(const []);

  @override
  Stream<List<Ingredient>> watchVocabulary() => const Stream.empty();

  @override
  Stream<List<String>> watchCategories() => Stream.value(const []);

  @override
  Stream<int> watchStubCount() => Stream.value(0);

  @override
  Stream<int> watchVocabularyCount() => Stream.value(0);

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async =>
      null;

  @override
  Future<Ingredient?> clearDensity(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> stopOfferingPiece(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> setDefaultMeasure(
    String ingredientId,
    String? measureId,
  ) => throw UnimplementedError();

  @override
  Future<Ingredient?> declineUsdaPrefill(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> unconfirm(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> saveForm(String? ingredientId, IngredientFormEdit edit) =>
      throw UnimplementedError();
}

/// A read-only vocabulary that answers every lookup with the same row.
///
/// The import review surfaces resolve ids they were HANDED, not ids they
/// chose, so what matters to them is that a lookup answers at all — which row
/// comes back is the suite's fixture, not the repository's job.
class OneRowIngredientRepo extends ReadOnlyIngredientRepo {
  const OneRowIngredientRepo(this.row);

  final Ingredient row;

  @override
  Future<Ingredient?> byId(String id) async => row;

  @override
  Stream<Ingredient?> watchIngredient(String id) => Stream.value(row);

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final id in ids) id: row,
  };
}

/// An in-memory vocabulary with the step-8.5 write semantics, for widget
/// tests of the list and the flesh-out form.
class FakeIngredientRepo implements IngredientRepository {
  FakeIngredientRepo(
    List<Ingredient> initial, {
    this.references = const {},
    Map<String, List<IngredientAlias>> aliasesById = const {},
  }) : rows = [...initial],
       _aliases = {
         for (final e in aliasesById.entries) e.key: [...e.value],
       };

  /// Every [IngredientFormEdit] this fake was handed, in order.
  final List<IngredientFormEdit> savedForms = [];
  final List<Ingredient> rows;
  final Map<String, List<IngredientAlias>> _aliases;

  /// Live recipe references per ingredient id — what the delete guard reads.
  final Map<String, ({int recipeCount, int lineCount})> references;

  /// The match_text each write left behind, by id — the rename hazard is
  /// invisible in the entity, so the fake records it for assertions.
  final matchTextById = <String, String>{};

  final _changes = StreamController<void>.broadcast();

  Ingredient? _find(String id) {
    for (final r in rows) {
      if (r.id == id) return r;
    }
    return null;
  }

  void _replace(Ingredient updated) {
    rows[rows.indexWhere((r) => r.id == updated.id)] = updated;
    _changes.add(null);
  }

  @override
  Stream<List<Ingredient>> watchVocabulary() async* {
    yield [...rows];
    yield* _changes.stream.map((_) => [...rows]);
  }

  @override
  Stream<int> watchStubCount() async* {
    int count() => rows.where((r) => r.status == IngredientStatus.stub).length;
    yield count();
    yield* _changes.stream.map((_) => count());
  }

  @override
  Stream<int> watchVocabularyCount() async* {
    yield rows.length;
    yield* _changes.stream.map((_) => rows.length);
  }

  @override
  Stream<List<String>> watchCategories() async* {
    List<String> categories() => {
      for (final r in rows)
        if ((r.category ?? '').trim().isNotEmpty) r.category!.trim(),
    }.toList()..sort();
    yield categories();
    yield* _changes.stream.map((_) => categories());
  }

  @override
  Future<Ingredient?> byId(String id) async => _find(id);

  @override
  Stream<Ingredient?> watchIngredient(String id) async* {
    yield _find(id);
    yield* _changes.stream.map((_) => _find(id));
  }

  @override
  Future<Map<String, Ingredient>> byIds(Set<String> ids) async => {
    for (final r in rows)
      if (ids.contains(r.id)) r.id: r,
  };

  @override
  Future<IngredientMatches> search(String query, {int limit = 30}) async =>
      (rows: [...rows], guessed: false);

  @override
  Future<List<Ingredient>> recentlyUsed({int limit = 8}) async => const [];

  @override
  Future<Ingredient?> setDensity(String ingredientId, double gPerMl) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    final updated = current.copyWith(
      densityGPerMl: gPerMl,
      allowedUnits: [
        ...{
          ...current.allowedUnits ?? allowedUnitsFor(current),
          ...densityUnlockedUnits(current),
        },
      ],
      // The quantity sheet's density write is a human write over a number
      // (0034) — a DIFFERENT number: re-stating the stored one is not an edit.
      sourceEdited:
          current.sourceEdited ||
          (isLookupFilled(current.source) && gPerMl != current.densityGPerMl),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> stopOfferingPiece(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    final kept = {...current.allowedUnits ?? allowedUnitsFor(current)};
    if (!kept.remove(pieces)) return current;
    final updated = current.copyWith(allowedUnits: kept.toList());
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> setDefaultMeasure(
    String ingredientId,
    String? measureId,
  ) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    // Clearing must survive freezed's "a null means unchanged" copyWith, and
    // clearing is half of what this write is for.
    final updated = Ingredient(
      id: current.id,
      canonicalName: current.canonicalName,
      defaultUnit: current.defaultUnit,
      status: current.status,
      category: current.category,
      densityGPerMl: current.densityGPerMl,
      macros: current.macros,
      macrosBasis: current.macrosBasis,
      allowedUnits: current.allowedUnits,
      defaultMeasureId: measureId,
      measureCount: current.measureCount,
      source: current.source,
      sourceLabel: current.sourceLabel,
      sourceScore: current.sourceScore,
      // "Counts as" is not a number: it never sets the flag, and it never
      // loses one the row already carries (0034).
      sourceEdited: current.sourceEdited,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> clearDensity(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    if (current.densityGPerMl == null) return current;
    // D4b's strip leg, mirroring SqliteIngredientRepository: the density goes
    // and the units it was the only reason to admit go with it. Rebuilt
    // field-by-field because freezed reads a null `densityGPerMl` as
    // "unchanged", and deleting it is the whole point.
    final kept = {...current.allowedUnits ?? allowedUnitsFor(current)}
      ..removeAll(densityStrippedUnits(current));
    final updated = Ingredient(
      id: current.id,
      canonicalName: current.canonicalName,
      defaultUnit: current.defaultUnit,
      status: current.status,
      category: current.category,
      macros: current.macros,
      macrosBasis: current.macrosBasis,
      allowedUnits: kept.toList(),
      measureCount: current.measureCount,
      source: current.source,
      sourceLabel: current.sourceLabel,
      sourceScore: current.sourceScore,
      // Deleting a lookup's density overrides its numbers (0034).
      sourceEdited: current.sourceEdited || isLookupFilled(current.source),
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> declineUsdaPrefill(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null || !isUsdaPrefilled(current.source)) return null;
    // The real write's shape (U-D2): density stripped as clearDensity strips
    // it, macros gone, the stamp replaced, the label kept, back to a stub.
    // Field-by-field because three of those are nulls freezed would read as
    // "unchanged".
    final kept = {...current.allowedUnits ?? allowedUnitsFor(current)}
      ..removeAll(densityStrippedUnits(current));
    final updated = Ingredient(
      id: current.id,
      canonicalName: current.canonicalName,
      defaultUnit: current.defaultUnit,
      status: IngredientStatus.stub,
      category: current.category,
      macrosBasis: current.macrosBasis,
      allowedUnits: kept.toList(),
      defaultMeasureId: current.defaultMeasureId,
      measureCount: current.measureCount,
      source: usdaDeclinedSource,
      sourceLabel: current.sourceLabel,
      // …and `source_edited` goes back to false with the numbers (0034):
      // there is nothing left on the row to have overridden.
    );
    _replace(updated);
    return updated;
  }

  /// The row half of a form save: the fields, the rename's `match_text`, and
  /// D5's reversibility (clearing the macros of a complete row returns it to
  /// `stub`). Private, because the real repository has one write door too —
  /// the form — and a test that could write half a form would be testing a
  /// shape production cannot make.
  Ingredient? _writeRow(String ingredientId, IngredientEdit edit) {
    final current = _find(ingredientId);
    if (current == null) return null;
    matchTextById[ingredientId] = normalizeMatchText(edit.canonicalName);
    // Built field-by-field, not copyWith: freezed reads a null argument as
    // "unchanged", and clearing the macros is the whole point of D5's
    // reversibility leg.
    final updated = Ingredient(
      id: current.id,
      canonicalName: edit.canonicalName.trim(),
      defaultUnit: edit.defaultUnit,
      status: edit.macros == null ? IngredientStatus.stub : current.status,
      category: edit.category,
      densityGPerMl: current.densityGPerMl,
      macros: edit.macros,
      macrosBasis: edit.macrosBasis,
      allowedUnits: edit.allowedUnits.toList(),
      measureCount: current.measureCount,
      // Patch-shaped, like the real write: a null keeps the stored stamp —
      // so a save that is not about the match cannot erase which food filled
      // the row.
      source: edit.source ?? current.source,
      sourceLabel: edit.sourceLabel ?? current.sourceLabel,
      sourceScore: edit.sourceScore ?? current.sourceScore,
    );
    _replace(updated);
    return updated;
  }

  /// The whole form in one act: the row, then the density, the default
  /// measure and the status flip, so a test can assert that ONE call did all
  /// of it — which is the property the real transaction exists to give.
  ///
  /// [savedForms] records what it was handed, so a test can pin *what the
  /// form asked for* separately from what the row ended up looking like.
  @override
  Future<Ingredient?> saveForm(
    String? ingredientId,
    IngredientFormEdit edit,
  ) async {
    savedForms.add(edit);
    var targetId = ingredientId;
    // C1: a null id creates. The fake mints one and seeds a bare stub, so the
    // rest of this method is the same for a create and an edit — which is the
    // property the real transaction has too.
    if (ingredientId == null) {
      final created = Ingredient(
        id: 'new-${rows.length + 1}',
        canonicalName: edit.row.canonicalName.trim(),
        defaultUnit: edit.row.defaultUnit,
        status: IngredientStatus.stub,
        macrosBasis: edit.row.macrosBasis,
      );
      rows.add(created);
      targetId = created.id;
    }
    // 0034, decided against the row AS IT STANDS and applied at the very end,
    // because the rebuilds below drop every field they do not name.
    final before = _find(targetId!);
    final row = _writeRow(targetId, edit.row);
    if (row == null) return null;
    var updated = row;
    switch (edit.density) {
      case DensitySet(:final gPerMl):
        updated = updated.copyWith(densityGPerMl: gPerMl);
      case DensityCleared():
        // copyWith reads null as "unchanged" (freezed), so the clear is built
        // field-by-field — the same reason `_writeRow` above does.
        updated = Ingredient(
          id: updated.id,
          canonicalName: updated.canonicalName,
          defaultUnit: updated.defaultUnit,
          status: updated.status,
          category: updated.category,
          macros: updated.macros,
          macrosBasis: updated.macrosBasis,
          allowedUnits: updated.allowedUnits,
          measureCount: updated.measureCount,
          source: updated.source,
          sourceLabel: updated.sourceLabel,
          sourceScore: updated.sourceScore,
          defaultMeasureId: updated.defaultMeasureId,
        );
      case DensityUnchanged():
        break;
    }
    if (edit.defaultMeasure case DefaultMeasureSet(:final measureId)) {
      updated = measureId == null
          ? Ingredient(
              id: updated.id,
              canonicalName: updated.canonicalName,
              defaultUnit: updated.defaultUnit,
              status: updated.status,
              category: updated.category,
              densityGPerMl: updated.densityGPerMl,
              macros: updated.macros,
              macrosBasis: updated.macrosBasis,
              allowedUnits: updated.allowedUnits,
              measureCount: updated.measureCount,
              source: updated.source,
              sourceLabel: updated.sourceLabel,
              sourceScore: updated.sourceScore,
            )
          : updated.copyWith(defaultMeasureId: measureId);
    }
    if (edit.markComplete && updated.macros != null) {
      updated = updated.copyWith(status: IngredientStatus.complete);
    }
    updated = updated.copyWith(
      sourceEdited: _sourceEdited(before: before, edit: edit),
    );
    _replace(updated);
    return updated;
  }

  /// `SqliteIngredientRepository._sourceEditedPatch`'s rule, as a value rather
  /// than a patch (0034, plan 0040 B-D1). A fresh stamp clears it; a write that
  /// changes macros, the basis or the density over a LOOKUP fill sets it;
  /// everything else — a rename, a unit, a category, a measure, an alias,
  /// "Counts as", Mark complete — leaves it exactly as it was.
  static bool _sourceEdited({
    required Ingredient? before,
    required IngredientFormEdit edit,
  }) {
    if (edit.row.source != null) return false;
    if (before == null) return false;
    if (!isLookupFilled(before.source)) return before.sourceEdited;
    final densityChanged = switch (edit.density) {
      DensitySet(:final gPerMl) => gPerMl != before.densityGPerMl,
      DensityCleared() => before.densityGPerMl != null,
      DensityUnchanged() => false,
    };
    return before.sourceEdited ||
        densityChanged ||
        edit.row.macros != before.macros ||
        edit.row.macrosBasis != before.macrosBasis;
  }

  @override
  Future<Ingredient?> unconfirm(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    // Not a number: `source_edited` rides along untouched (copyWith keeps it).
    final updated = current.copyWith(status: IngredientStatus.stub);
    _replace(updated);
    return updated;
  }

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return const DeleteMissing();
    final refs = references[ingredientId] ?? (recipeCount: 0, lineCount: 0);
    if (refs.lineCount > 0) {
      return DeleteRefused(
        recipeCount: refs.recipeCount,
        lineCount: refs.lineCount,
      );
    }
    rows.remove(current);
    _changes.add(null);
    return const Deleted();
  }

  @override
  Stream<List<IngredientAlias>> watchAliases(String ingredientId) async* {
    List<IngredientAlias> current() => [...?_aliases[ingredientId]];
    yield current();
    yield* _changes.stream.map((_) => current());
  }
}
