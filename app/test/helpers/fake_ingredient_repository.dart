/// Test doubles for [IngredientRepository].
///
/// Step 8.5 grew the interface a write half (rename, allowed units, confirm,
/// delete, aliases). Screens that only *read* the vocab shouldn't have to
/// restate nine unused methods, so [IngredientManagerStubs] supplies them as
/// loud no-ops; screens that exercise the manager use [FakeIngredientRepo],
/// an in-memory implementation that keeps the D5/D6 semantics honest (a
/// rename rewrites `match_text`, confirming without macros throws, delete is
/// refused while a reference count is set).
library;

import 'dart:async';

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/domain/allowed_units.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';

/// The manager's write half as `UnimplementedError`s — for read-only fakes.
mixin IngredientManagerStubs implements IngredientRepository {
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
  Future<Ingredient?> applyUsdaProbe(
    String ingredientId, {
    required String source,
    String? sourceLabel,
    double? sourceScore,
    double? densityGPerMl,
    Macros? macros,
    bool explicitPick = false,
  }) => throw UnimplementedError();

  @override
  Future<Ingredient?> declineUsdaPrefill(String ingredientId) =>
      throw UnimplementedError();

  @override
  Stream<List<Ingredient>> watchVocabulary() => const Stream.empty();

  @override
  Stream<List<String>> watchCategories() => Stream.value(const []);

  @override
  Stream<int> watchStubCount() => Stream.value(0);

  @override
  Stream<int> watchVocabularyCount() => Stream.value(0);

  @override
  Future<Ingredient?> saveEdit(String ingredientId, IngredientEdit edit) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> confirmStub(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<Ingredient?> unconfirm(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<({int lineCount, int recipeCount})> recipeReferences(
    String ingredientId,
  ) async => (recipeCount: 0, lineCount: 0);

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) =>
      throw UnimplementedError();

  @override
  Future<List<IngredientAlias>> aliases(String ingredientId) async => const [];

  @override
  Future<IngredientAlias> addAlias(String ingredientId, String text) =>
      throw UnimplementedError();

  @override
  Future<void> removeAlias(String aliasId) => throw UnimplementedError();
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
  Future<Ingredient> createStub(
    String name, {
    String source = 'manual',
    Macros? macros,
    MacrosBasis macrosBasis = MacrosBasis.perG,
  }) async {
    final created = Ingredient(
      id: 'created-${rows.length}',
      canonicalName: name,
      defaultUnit: g,
      status: IngredientStatus.stub,
      macros: macros,
      macrosBasis: macrosBasis,
      source: source,
    );
    rows.add(created);
    matchTextById[created.id] = normalizeMatchText(name);
    _changes.add(null);
    return created;
  }

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
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> applyUsdaProbe(
    String ingredientId, {
    required String source,
    String? sourceLabel,
    double? sourceScore,
    double? densityGPerMl,
    Macros? macros,
    bool explicitPick = false,
  }) async {
    if (densityGPerMl == null && macros == null) return null;
    final current = _find(ingredientId);
    if (current == null) return null;
    // The same guards the real repo re-checks inside its transaction (D7b):
    // a bare stub only, so a machine's numbers never land on a row someone
    // has filled in — a declined row, or a fill that is still the prefill's
    // own, only for a person's own pick (plan 0027 U-D2/U-D3).
    final bare =
        current.status == IngredientStatus.stub &&
        current.densityGPerMl == null &&
        current.macros == null;
    if (explicitPick) {
      if (!bare && !isUsdaPrefilled(current.source)) return null;
    } else if (!bare || isUsdaDeclined(current.source)) {
      return null;
    }
    // Rebuilt field-by-field: a pick with no density must CLEAR one, and
    // freezed reads a null as "unchanged". The admission list follows the
    // density both ways, as the real write's does.
    final units = {...current.allowedUnits ?? allowedUnitsFor(current)};
    if (current.densityGPerMl != null && densityGPerMl == null) {
      units.removeAll(densityStrippedUnits(current));
    }
    if (densityGPerMl != null) units.addAll(densityUnlockedUnits(current));
    final updated = Ingredient(
      id: current.id,
      canonicalName: current.canonicalName,
      defaultUnit: current.defaultUnit,
      status: IngredientStatus.stub,
      category: current.category,
      densityGPerMl: densityGPerMl,
      macros: macros,
      macrosBasis: current.macrosBasis,
      allowedUnits: units.toList(),
      defaultMeasureId: current.defaultMeasureId,
      measureCount: current.measureCount,
      source: source,
      sourceLabel: sourceLabel,
      sourceScore: sourceScore,
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
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> saveEdit(String ingredientId, IngredientEdit edit) async {
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
      // Patch-shaped, like the real write: a null keeps the stored stamp.
      source: edit.source ?? current.source,
      sourceLabel: current.sourceLabel,
      sourceScore: current.sourceScore,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> confirmStub(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    if (current.macros == null) throw StateError('no macros');
    final updated = current.copyWith(status: IngredientStatus.complete);
    _replace(updated);
    return updated;
  }

  @override
  Future<Ingredient?> unconfirm(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return null;
    final updated = current.copyWith(status: IngredientStatus.stub);
    _replace(updated);
    return updated;
  }

  @override
  Future<({int lineCount, int recipeCount})> recipeReferences(
    String ingredientId,
  ) async => references[ingredientId] ?? (recipeCount: 0, lineCount: 0);

  @override
  Future<DeleteOutcome> softDelete(String ingredientId) async {
    final current = _find(ingredientId);
    if (current == null) return const DeleteMissing();
    final refs = await recipeReferences(ingredientId);
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
  Future<List<IngredientAlias>> aliases(String ingredientId) async => [
    ...?_aliases[ingredientId],
  ];

  @override
  Future<IngredientAlias> addAlias(String ingredientId, String text) async {
    final alias = IngredientAlias(
      id: 'alias-${text.hashCode}',
      text: text.trim(),
      source: 'manual',
    );
    (_aliases[ingredientId] ??= []).add(alias);
    _changes.add(null);
    return alias;
  }

  @override
  Future<void> removeAlias(String aliasId) async {
    for (final list in _aliases.values) {
      list.removeWhere((a) => a.id == aliasId);
    }
    _changes.add(null);
  }
}
