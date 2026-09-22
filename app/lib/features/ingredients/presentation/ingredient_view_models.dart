/// The ingredient form's state: one notifier over one draft.
///
/// The draft holds everything the form intends, and [IngredientForm.save]
/// writes it in one transaction (ADR-0011). It is held as deltas, so a measures
/// stream that failed to load cannot be written back as a narrowed set. The
/// view keeps only what needs a `BuildContext` and hands each result back as an
/// intent.
library;

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/result/result.dart';
import '../../../core/text/name_clean.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/units.dart';
import '../../../core/words.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../data/label_read_provider.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/label_reading.dart';
import '../domain/name_namespace.dart';
import '../domain/serving_measure.dart';
import '../domain/suggest_name.dart';
import '../domain/usda_probe.dart';
import 'ingredient_facts.dart';
import 'macros_format.dart';
import 'serving_row.dart';

part 'ingredient_view_models.freezed.dart';
part 'ingredient_view_models.g.dart';

const _uuid = Uuid();

/// Said when a per-serving panel has no serving amount, so no per-100 reading.
const kServingAmountFirst =
    'One serving is how much? The label’s figures become per 100 only once '
    'the serving amount is typed.';

/// The macro inputs as typed text, so "half filled in" is a nameable state.
/// [kcal], [protein], [carb] and [fat] move together; [fiber] ([Macros.fiber])
/// is optional but cannot be the only thing typed.
@freezed
abstract class MacroDraft with _$MacroDraft {
  const factory MacroDraft({
    @Default('') String kcal,
    @Default('') String protein,
    @Default('') String carb,
    @Default('') String fat,
    @Default('') String fiber,
  }) = _MacroDraft;

  /// Seeds the fields from a stored panel, losslessly; see [macroFieldSeed].
  factory MacroDraft.from(Macros? m) => m == null
      ? const MacroDraft()
      : MacroDraft(
          kcal: macroFieldSeed(m.kcal),
          protein: macroFieldSeed(m.protein),
          carb: macroFieldSeed(m.carb),
          fat: macroFieldSeed(m.fat),
          fiber: m.fiber == null ? '' : macroFieldSeed(m.fiber!),
        );

  const MacroDraft._();

  List<String> get _fields => [kcal, protein, carb, fat];

  static bool _blank(String field) => field.trim().isEmpty;

  static bool _parses(String field) =>
      double.tryParse(field.trim())?.isFinite ?? false;

  /// The four required fields are empty. Fibre is ignored, so a lone fibre
  /// figure does not read as a panel to a scan ([DraftTarget.hasMacros]).
  bool get allBlank => _fields.every(_blank);

  /// All four parse, or all four are blank. Anything between is a panel with a
  /// hole in it, which the form refuses rather than zero-filling.
  bool get fourCoherent => allBlank || _fields.every(_parses);

  /// Fibre is blank, or it is a number ON a panel. It is an extra figure the
  /// four carry, never a panel of its own.
  bool get fiberCoherent => _blank(fiber) || (_parses(fiber) && !allBlank);

  bool get isCoherent => fourCoherent && fiberCoherent;

  /// The macros this draft asserts, or null for "none" — the deliberate clear.
  Macros? toMacros() {
    if (allBlank || !isCoherent) return null;
    return Macros(
      kcal: double.parse(kcal.trim()),
      protein: double.parse(protein.trim()),
      carb: double.parse(carb.trim()),
      fat: double.parse(fat.trim()),
      fiber: _blank(fiber) ? null : double.parse(fiber.trim()),
    );
  }
}

/// The macro half of the form as it stood before a label was read, so the undo
/// puts it back exactly. Nothing was written, so this is the whole of it.
@freezed
abstract class LabelFillUndo with _$LabelFillUndo {
  const factory LabelFillUndo({
    required MacroDraft macros,
    required MacroDraft seededMacros,
    required bool perServing,
    required MacrosBasis basis,
    required ServingDraft serving,
    MacroDraft? per100Macros,
    String? pendingSource,
    String? pendingSourceLabel,
    double? pendingSourceScore,
  }) = _LabelFillUndo;
}

/// One ingredient form, in flight. [row] is the stored row as last watched, or
/// a blank stand-in with an empty id while creating.
@freezed
abstract class IngredientFormDraft with _$IngredientFormDraft {
  const factory IngredientFormDraft({
    required Ingredient row,
    required bool creating,
    required String name,
    required String category,
    required Unit defaultUnit,
    required MacrosBasis basis,
    required Set<Unit> allowed,
    required MacroDraft macros,

    /// What the row last seeded the macro draft with; "untouched" is measured
    /// against this, not against blankness.
    required MacroDraft seededMacros,

    /// Bumped on every re-seed, and used as the macro fields' key: `initial`
    /// seeds a controller once, so new text needs a new field to seed it into.
    @Default(0) int macroSeed,

    /// Bumped when the name moved by something other than typing, so the name
    /// field pushes the text into its existing controller instead of being
    /// re-keyed.
    @Default(0) int nameSeed,
    @Default(0) int servingSeed,

    /// Per-serving mode: the four fields hold the label's figures as printed,
    /// and what is stored is still per 100 of the basis.
    @Default(false) bool perServing,

    /// The serving the label prints, typed or scanned. Independent of
    /// [perServing]; Save keeps it as the row's one `serving` measure either
    /// way.
    @Default(ServingDraft()) ServingDraft serving,

    /// The per-100 figures the fields held before per-serving mode cleared
    /// them, or a scanned pack's own per-100 column.
    MacroDraft? per100Macros,
    @Default(DensityUnchanged()) DensityChange density,

    /// The piece weight as the form holds it — the count-side twin of
    /// [density], and drafted the same way (ADR-0015).
    @Default(PieceWeightUnchanged()) PieceWeightChange pieceWeight,
    @Default(<Measure>[]) List<Measure> measuresAdded,
    @Default(<String>{}) Set<String> measuresRemoved,
    @Default(<IngredientAlias>[]) List<IngredientAlias> aliasesAdded,
    @Default(<String>{}) Set<String> aliasesRemoved,

    /// A provenance stamp the scan or USDA pick set, written by the next Save.
    String? pendingSource,
    String? pendingSourceLabel,
    double? pendingSourceScore,

    /// What the macro half held before the last label read, and null once
    /// there is nothing to undo. Set by [IngredientForm.applyLabel], spent by
    /// [IngredientForm.undoLabelFill], cleared by a Save.
    LabelFillUndo? labelUndo,

    /// The last barcode scan: the draft the card shows, what [applyDraft]
    /// decided about it, and whether its pack offer was taken.
    IngredientDraft? scanned,
    DraftApplication? scanApplied,
    @Default(false) bool packAdded,

    /// Set when the measures editor refused a volume-named label and handed
    /// back the resolved spoon — the density entry pre-picks it.
    Unit? redirectedSpoon,

    /// The name as typed, when [IngredientForm.tidyName] replaced a word in it;
    /// the `was “…”` line prints it. Null when nothing was suggested.
    String? nameWas,

    /// The live row that already holds this name or alias. Set when the name
    /// field is left or the write refuses; cleared by the next keystroke.
    NameEntry? nameCollision,

    /// Up to three rows this name nearly spells, for the `DID YOU MEAN` band.
    /// Empty whenever something matched exactly.
    @Default(<NameEntry>[]) List<NameEntry> nameNearMatches,

    /// A typed name the person chose to keep. While [name] equals it the tidy
    /// recases but suggests nothing; cleared by the next edit.
    String? namePinned,

    /// Whether the name field was typed in during this sitting. Save tidies
    /// only a name somebody wrote.
    @Default(false) bool nameEdited,

    /// The form's one feedback line.
    String? message,

    /// True while a write is in flight — every door greys rather than
    /// accepting a tap it will drop.
    @Default(false) bool busy,
  }) = _IngredientFormDraft;

  const IngredientFormDraft._();

  /// The density AS THE FORM HOLDS IT. Nothing has been written, so the chips,
  /// the gap note and the entry's own headline all read this.
  double? get densityValue => switch (density) {
    DensitySet(:final gPerMl) => gPerMl,
    DensityCleared() => null,
    DensityUnchanged() => row.densityGPerMl,
  };

  /// The piece weight AS THE FORM HOLDS IT, in the basis unit.
  double? get pieceWeightValue => switch (pieceWeight) {
    PieceWeightSet(:final amount) => amount,
    PieceWeightCleared() => null,
    PieceWeightUnchanged() => row.pieceBasisAmount,
  };

  /// The row as the form reads it: the stored facts with the draft's default
  /// unit, basis, density and piece weight folded in. Every admission question
  /// asks this.
  Ingredient get editedRow => row.copyWith(
    defaultUnit: defaultUnit,
    macrosBasis: basis,
    densityGPerMl: densityValue,
    pieceBasisAmount: pieceWeightValue,
  );

  /// The four fields as numbers, whatever mode they are in.
  Macros? get printedMacros => macros.toMacros();

  /// The per-100 column a scan landed, kept so the comparison line can check
  /// the pack's two readings against each other.
  Macros? get scannedPer100 => scanApplied?.macros;

  /// What Save would store: per 100 of the basis. In per-serving mode it is the
  /// derivation, null until the serving amount is in. A volume serving converts
  /// through the catalog alone, so it needs no density.
  Macros? get storedMacros {
    if (!perServing) return printedMacros;
    final printed = printedMacros;
    final amount = serving.amountInBasis;
    if (printed == null || amount == null) return null;
    return Macros.per100From(serving: amount, basis: basis, printed: printed);
  }

  /// The serving to keep as the row's one measure, or null. Refused when it
  /// cannot be said in the stored basis without a density (ADR-0008 §2).
  ({double inBasis, String label})? get servingMeasure {
    final amount = serving.amount;
    final inBasis = serving.amountInBasis;
    if (amount == null || inBasis == null || serving.basis != basis) {
      return null;
    }
    return (inBasis: inBasis, label: servingMeasureLabel(amount, serving.unit));
  }

  /// What the density sentence is offered: a volume left-hand side, and the
  /// grams when the pack printed a weight beside it ("2 tbsp (7 g)"). Null when
  /// the serving has no volume reading. An offer only (ADR-0008 §2).
  ({double amount, Unit unit, double? grams})? get densityPrefill {
    final printed = readPrintedServing(serving.packPrintedText);
    final said = serving.amount;
    final typed = said == null ? null : (amount: said, unit: serving.unit);
    ({double amount, Unit unit})? reading(UnitFamily family) {
      for (final r in [typed, printed.said, printed.bracketed]) {
        if (r != null && r.unit.family == family) return r;
      }
      return null;
    }

    final volume = reading(UnitFamily.volume);
    if (volume == null) return null;
    final mass = reading(UnitFamily.mass);
    return (
      amount: volume.amount,
      unit: volume.unit,
      grams: mass == null
          ? null
          : switch (convert(Quantity(mass.amount, mass.unit), to: g)) {
              Ok(:final value) when value.amount > 0 => value.amount,
              Ok() || Err() => null,
            },
    );
  }

  /// True for a scan that landed a per-100 panel and named no serving: the one
  /// state where the section hints that per-serving mode exists. Reads the
  /// fields, so it goes once the person touches the mode or a figure.
  bool get scannedPer100NeedsServingHint {
    final scanned = this.scanned;
    final applied = scanApplied;
    if (scanned == null || applied == null) return false;
    if (scanned.macrosGap != DraftMacrosGap.none) return false;
    if (applied.serving != null) return false;
    final landed = applied.macros;
    if (landed == null) return false;
    return !perServing &&
        basis == applied.macrosBasis &&
        macros == MacroDraft.from(landed);
  }

  bool get stub => row.status == IngredientStatus.stub;

  /// Whether the provenance the form holds is a pick or a scan that has not
  /// been written yet — the state the card says *not saved* in.
  bool get sourcePending => pendingSource != null;

  /// The row as the form reads its provenance: the draft's pick or scan, else
  /// the stored stamp. The three source fields travel together, and a fresh
  /// fill clears [Ingredient.sourceEdited].
  Ingredient get sourcedRow => pendingSource == null
      ? row
      : row.copyWith(
          source: pendingSource,
          sourceLabel: pendingSourceLabel,
          sourceScore: pendingSourceScore,
          sourceEdited: false,
        );

  /// Why this form cannot be saved yet, in the user's words, or null. On the
  /// draft so the dock can ask before the tap.
  String? get refusal {
    if (name.trim().isEmpty) {
      return 'A name is the one field an ingredient can’t go without.';
    }
    // One namespace: a name or alias another row carries is refused.
    if (nameCollision case final taken?) {
      return nameTakenMessage(taken.ingredientName);
    }
    // New rows only: rows already stored without a category stay saveable.
    if (creating && category.trim().isEmpty) {
      return 'Which aisle is it in? Pick a category — an uncategorised row '
          'sorts ahead of every aisle, and words like pinch and handful are '
          'earned by one.';
    }
    if (!macros.fourCoherent) {
      return 'Enter all four macros, or leave them all blank — a part of a '
          'panel isn’t a panel.';
    }
    if (!macros.fiberCoherent) {
      return 'Fibre is an extra figure on a panel, not a panel of its own — '
          'give it a number beside the four, or clear it.';
    }
    if (perServing && printedMacros != null && serving.amountInBasis == null) {
      return kServingAmountFirst;
    }
    // A basis flip or USDA pick can strand a default already chosen, so the
    // write side refuses too. The row is never rewritten silently.
    if (!unitSayableAsDefault(editedRow, defaultUnit)) {
      final basisWord = basis == MacrosBasis.perMl ? 'ml' : 'g';
      return 'Macros per 100 $basisWord and no density can’t have '
          '${defaultUnit.label} as the default unit — add a density '
          'below, or make it ${basisDefaultUnitFix(editedRow).label}.';
    }
    // The count-side twin (ADR-0015): a `piece` default with no piece weight.
    if (defaultUnitNeedsPieceWeight(editedRow)) {
      return 'Piece can’t be the default unit with nothing weighing one — '
          'enter what one weighs below, or make it '
          '${basisDefaultUnitFix(editedRow).label}.';
    }
    return null;
  }

  /// Whether this form would land a row that counts: nothing refused, and
  /// macros on a basis. The same gate `Mark complete` applies to a stub.
  bool get completable => refusal == null && storedMacros != null;
}

/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).
@riverpod
class IngredientForm extends _$IngredientForm {
  /// The measures stream re-emits; the serving is seeded once, from the first
  /// list that carries one.
  bool _servingSeeded = false;

  @override
  IngredientFormDraft build(String? ingredientId, {String initialName = ''}) {
    _servingSeeded = false;
    // Listened to, not watched: rebuilding the notifier on a row change would
    // discard the draft. A moving row may only re-seed untouched macro fields.
    if (ingredientId != null) {
      ref.listen(ingredientByIdProvider(ingredientId), (_, next) {
        final row = next.asData?.value;
        if (row != null) _rowMoved(row);
      });
      // The row's serving is one of its measures, and the stream may open after
      // the form does.
      ref.listen(ingredientMeasuresProvider(ingredientId), (_, next) {
        final measures = next.asData?.value;
        if (measures != null) _servingArrived(servingMeasureOf(measures));
      });
    }
    final row =
        (ingredientId == null
            ? null
            : ref.read(ingredientByIdProvider(ingredientId)).asData?.value) ??
        Ingredient(
          id: ingredientId ?? '',
          // The seed is a picker query: clean it silently, suggest no other
          // word.
          canonicalName: cleanName(initialName, NameKind.title),
          defaultUnit: g,
          status: IngredientStatus.stub,
        );
    final seeded = MacroDraft.from(row.macros);
    final draft = IngredientFormDraft(
      row: row,
      creating: ingredientId == null,
      name: row.canonicalName,
      category: row.category ?? '',
      defaultUnit: row.defaultUnit,
      basis: row.macrosBasis,
      allowed: _admissionFor(row, allowedUnitsFor(row).toSet()),
      macros: seeded,
      seededMacros: seeded,
    );
    // The serving, when the stream already has it — the ordinary case on a
    // row whose page was open a moment ago.
    final measures = ingredientId == null
        ? null
        : ref.read(ingredientMeasuresProvider(ingredientId)).asData?.value;
    return measures == null
        ? draft
        : _withServing(draft, servingMeasureOf(measures));
  }

  /// A row that states a serving reopens in per-serving mode: the fields hold
  /// the stored per-100 scaled by the serving ([servingPrintedMacros]),
  /// unrounded, so an unchanged Save writes the same per-100 back. Holding the
  /// label's column also keeps [_rowMoved] from overwriting them.
  IngredientFormDraft _withServing(
    IngredientFormDraft draft,
    Measure? measure,
  ) {
    if (measure == null) return draft;
    final stated = servingFromMeasureLabel(measure.label);
    // A renamed serving no longer parses, and one in another dimension cannot
    // be reversed; either way the form opens per 100.
    if (stated == null || measure.basis != draft.row.macrosBasis) return draft;
    final serving = ServingDraft(
      amountText: macroFieldSeed(stated.amount),
      unit: stated.unit,
    );
    if (serving.basis != draft.row.macrosBasis) return draft;
    _servingSeeded = true;
    final printed = servingPrintedMacros(draft.row, serving: measure);
    return draft.copyWith(
      perServing: true,
      basis: serving.basis,
      serving: serving,
      servingSeed: draft.servingSeed + 1,
      // A row with a serving and no panel has nothing to put in the fields;
      // the mode is still the truth about the row.
      macros: printed == null ? draft.macros : MacroDraft.from(printed),
      macroSeed: draft.macroSeed + 1,
      // Leaving the mode puts the row's own per-100 back, which is exactly
      // what these fields were derived from.
      per100Macros: MacroDraft.from(draft.row.macros),
    );
  }

  /// The serving arriving after the form opened. Seeds once, and only into
  /// untouched fields ([IngredientFormDraft.seededMacros]).
  void _servingArrived(Measure? measure) {
    if (_servingSeeded || state.perServing) return;
    if (state.macros != state.seededMacros) return;
    if (state.serving.amount != null) return;
    state = _withServing(state, measure);
  }

  /// The admission set [allowed] becomes under [row]'s density and piece
  /// weight: a density unlocks the other family, a piece weight unlocks `piece`
  /// on a count row (ADR-0015), and removing either strips them. Derived, so
  /// the chips and the stored set cannot disagree.
  Set<Unit> _admissionFor(Ingredient row, Set<Unit> allowed) {
    final next = {...allowed};
    if (row.densityGPerMl != null) {
      next.addAll(densityUnlockedUnits(row));
    } else {
      next.removeAll(densityStrippedUnits(row));
    }
    if (row.pieceBasisAmount != null) {
      next.addAll(pieceUnlockedUnits(row));
    } else {
      next.removeAll(pieceStrippedUnits(row));
    }
    if (row.defaultUnit.family != UnitFamily.count) next.remove(pieces);
    return next;
  }

  /// Re-seeds the macro fields when the row's macros move, bumping
  /// [IngredientFormDraft.macroSeed] (the fields' key) so their controllers
  /// rebuild. Only while the draft still says what the row last put there;
  /// typed fields are left alone.
  void _rowMoved(Ingredient row) {
    final fresh = MacroDraft.from(row.macros);
    if (fresh == state.seededMacros || state.macros != state.seededMacros) {
      // The row did not move, or the typed draft wins. Either way the fields
      // stand; the rest of the form still follows the new row.
      state = state.copyWith(row: row);
      return;
    }
    state = state.copyWith(
      row: row,
      seededMacros: fresh,
      macros: fresh,
      macroSeed: state.macroSeed + 1,
      // A row's own macros are per 100 by definition — the fields now hold
      // them, so the mode must say so.
      perServing: false,
      per100Macros: null,
    );
  }

  // --- The row's own fields ------------------------------------------------

  /// The name as the field now reads. Identical text is not an edit: a
  /// re-seeded name echoes back through here.
  void setName(String name) {
    if (name == state.name) return;
    state = state.copyWith(
      name: name,
      nameEdited: true,
      nameWas: null,
      namePinned: null,
      // Both are answers about the text that has just changed, so neither may
      // outlive it — a note naming the wrong name is worse than no note.
      nameCollision: null,
      nameNearMatches: const <NameEntry>[],
    );
  }

  /// Tidies the name: [cleanName], then the ingredient suggestion. Recasing is
  /// silent; a changed word sets [IngredientFormDraft.nameWas]. A pinned name
  /// skips the suggestion.
  void tidyName() {
    final typed = state.name;
    final cleaned = cleanName(typed, NameKind.title);
    final pinned = state.namePinned == typed;
    final suggested = pinned ? null : suggestIngredientName(cleaned);
    final next = suggested ?? cleaned;
    if (next == typed && state.nameWas == null) return;
    state = state.copyWith(
      name: next,
      // The seed is what tells the field its text moved by something other
      // than typing.
      nameSeed: next == typed ? state.nameSeed : state.nameSeed + 1,
      nameWas: suggested == null ? null : typed,
      namePinned: pinned ? next : state.namePinned,
    );
  }

  /// The name field was left: tidy first, then check the namespace, because the
  /// check must ask about the name as it will be saved.
  Future<void> leaveNameField() async {
    tidyName();
    await checkName();
  }

  /// Asks the name namespace whether the name is taken and, only when it is
  /// not, which names it nearly spells. The two never show together.
  Future<void> checkName() async {
    final name = state.name;
    if (name.trim().isEmpty) return;
    // The repository, not a provider: a one-shot `.future` on an autoDispose
    // provider disposes it mid-load and completes with a StateError.
    final entries = await ref.read(ingredientRepositoryProvider).nameIndex();
    if (!ref.mounted || state.name != name) return;
    final selfId = state.creating ? null : state.row.id;
    final taken = collisionIn(name, entries, selfId: selfId);
    state = state.copyWith(
      nameCollision: taken,
      nameNearMatches: taken != null
          ? const <NameEntry>[]
          : nearMatchesIn(name, entries, selfId: selfId),
    );
  }

  /// *keep the old word* — the typed name comes back, and the suggestion is
  /// not offered for it again until the field is edited.
  void keepName() {
    final was = state.nameWas;
    if (was == null) return;
    state = state.copyWith(
      name: was,
      nameSeed: state.nameSeed + 1,
      nameWas: null,
      namePinned: was,
      nameCollision: null,
      nameNearMatches: const <NameEntry>[],
    );
  }

  void setCategory(String category) =>
      state = state.copyWith(category: category);

  /// Only sayable units are offered, except `piece`: picking it is what reveals
  /// the weight field, and Save refuses until the weight is in.
  void setDefaultUnit(Unit unit) {
    final next = state.copyWith(
      defaultUnit: unit,
      allowed: {...state.allowed, unit},
    );
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// Toggles a unit, except the row's own default: [allowedUnitsFor] unions it
  /// back in anyway, so the chip is drawn locked.
  void toggleUnit(Unit unit) {
    if (unit == state.defaultUnit) return;
    final next = {...state.allowed};
    if (!next.remove(unit)) next.add(unit);
    state = state.copyWith(allowed: next);
  }

  /// Back to per 100 of the basis. The fields refill with the derivation, or
  /// with the per-100 figures the mode cleared when nothing was typed. With
  /// figures and no serving amount the mode does not leave, and the chips say
  /// [kServingAmountFirst].
  void setBasis(MacrosBasis basis) {
    if (!state.perServing) {
      state = state.copyWith(basis: basis);
      return;
    }
    final derived = state.storedMacros;
    if (derived == null &&
        !state.macros.allBlank &&
        state.serving.amountInBasis == null) {
      state = state.copyWith(message: kServingAmountFirst);
      return;
    }
    final macros = derived != null
        ? MacroDraft.from(derived)
        : state.per100Macros ?? const MacroDraft();
    state = state.copyWith(
      perServing: false,
      basis: basis,
      macros: macros,
      macroSeed: state.macroSeed + 1,
      per100Macros: null,
    );
  }

  /// The serving's unit sets the BASIS — a `cup` serving stores per 100 ml —
  /// so the admission chips and the stored dimension follow it live.
  void setServingUnit(Unit unit) {
    final serving = state.serving.copyWith(unit: unit);
    state = state.copyWith(serving: serving, basis: serving.basis);
  }

  /// Clears the four fields, because per-100 figures are wrong per serving.
  /// What they held is remembered so [setBasis] can put it back.
  void setPerServing() {
    if (state.perServing) return;
    state = state.copyWith(
      perServing: true,
      basis: state.serving.basis,
      per100Macros: state.macros,
      macros: const MacroDraft(),
      macroSeed: state.macroSeed + 1,
    );
  }

  void setMacros(MacroDraft macros) => state = state.copyWith(macros: macros);

  void setServingAmount(String text) =>
      state = state.copyWith(serving: state.serving.copyWith(amountText: text));

  // --- Density -------------------------------------------------------------

  void draftDensity(double gPerMl) => _withDensity(DensitySet(gPerMl));

  void removeDensity() => _withDensity(const DensityCleared());

  void _withDensity(DensityChange change) {
    final next = state.copyWith(density: change, redirectedSpoon: null);
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// A volume-named measure label is a density in disguise; the editor refuses
  /// it and the density entry pre-picks that spoon.
  void redirectSpoon(Unit unit) =>
      state = state.copyWith(redirectedSpoon: unit);

  // --- Piece weight (ADR-0015) ---------------------------------------------

  /// What one piece weighs, in the basis unit. Drafted, not written.
  void draftPieceWeight(double amount) =>
      _withPieceWeight(PieceWeightSet(amount));

  void removePieceWeight() => _withPieceWeight(const PieceWeightCleared());

  void _withPieceWeight(PieceWeightChange change) {
    final next = state.copyWith(pieceWeight: change);
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  // --- Measures and aliases ------------------------------------------------

  /// Mints the measure the form will insert. It carries the id it will keep, so
  /// the list can draw it beside the stored ones before it exists.
  Measure draftMeasure(String label, double amount, {required int sortOrder}) {
    final pending = Measure(
      id: _uuid.v4(),
      label: label.trim(),
      amount: amount,
      basis: state.basis,
      sortOrder: sortOrder,
    );
    state = state.copyWith(measuresAdded: [...state.measuresAdded, pending]);
    return pending;
  }

  /// Re-states a drafted measure, keeping its id. Null for a stored measure,
  /// which the host corrects through the repository.
  Measure? editDraftMeasure(String measureId, String label, double amount) {
    final index = state.measuresAdded.indexWhere((m) => m.id == measureId);
    if (index < 0) return null;
    final edited = Measure(
      id: measureId,
      label: label.trim(),
      amount: amount,
      basis: state.basis,
      sortOrder: state.measuresAdded[index].sortOrder,
    );
    state = state.copyWith(
      measuresAdded: [
        for (final (i, m) in state.measuresAdded.indexed)
          if (i == index) edited else m,
      ],
    );
    return edited;
  }

  /// Re-stamps the draft's measures to their positions in [ids]; the repository
  /// re-stamps the stored rows.
  void reorderDraftMeasures(List<String> ids) {
    final position = {for (final (i, id) in ids.indexed) id: i};
    state = state.copyWith(
      measuresAdded: [
        for (final m in state.measuresAdded)
          if (position[m.id] case final at?)
            Measure(
              id: m.id,
              label: m.label,
              amount: m.amount,
              basis: m.basis,
              sortOrder: at,
              source: m.source,
            )
          else
            m,
      ],
    );
  }

  /// A pending add is simply dropped; a stored one is named for tombstoning.
  /// Either way nothing is written yet.
  void removeMeasure(String measureId) {
    final pending = state.measuresAdded.any((m) => m.id == measureId);
    state = state.copyWith(
      measuresAdded: pending
          ? [
              for (final m in state.measuresAdded)
                if (m.id != measureId) m,
            ]
          : state.measuresAdded,
      measuresRemoved: pending
          ? state.measuresRemoved
          : {...state.measuresRemoved, measureId},
    );
  }

  /// Takes the scan's pack size into the draft as a measure.
  void addPackMeasure({required int sortOrder}) {
    final pack = state.scanApplied?.packMeasure;
    if (pack == null) return;
    state = state.copyWith(
      measuresAdded: [
        ...state.measuresAdded,
        Measure(
          id: _uuid.v4(),
          label: 'pack',
          amount: pack.amountInBasis,
          basis: state.basis,
          sortOrder: sortOrder,
        ),
      ],
      packAdded: true,
    );
  }

  /// Adds an alias to the draft under an id minted here. An alias shares the
  /// name namespace: returns the entry it collides with, or null when taken.
  Future<NameEntry?> addAlias(String text) async {
    final cleaned = cleanName(text, NameKind.alias);
    final entries = await ref.read(ingredientRepositoryProvider).nameIndex();
    if (!ref.mounted) return null;
    final taken = collisionIn(
      cleaned,
      entries,
      selfId: state.creating ? null : state.row.id,
    );
    if (taken != null) return taken;
    state = state.copyWith(
      aliasesAdded: [
        ...state.aliasesAdded,
        IngredientAlias(id: _uuid.v4(), text: cleaned, source: 'manual'),
      ],
    );
    return null;
  }

  void removeAlias(String aliasId) {
    if (state.aliasesAdded.any((a) => a.id == aliasId)) {
      state = state.copyWith(
        aliasesAdded: [
          for (final a in state.aliasesAdded)
            if (a.id != aliasId) a,
        ],
      );
      return;
    }
    state = state.copyWith(aliasesRemoved: {...state.aliasesRemoved, aliasId});
  }

  // --- The three prefill doors ---------------------------------------------

  /// Reads the nutrition label in the photo at [photoPath] and lands it in the
  /// draft. A failure says so on the form's own feedback line and changes
  /// nothing else.
  Future<void> readLabelFromPhoto(String photoPath) async {
    state = state.copyWith(busy: true, message: 'Reading the label…');
    try {
      final reading = await ref
          .read(labelReadRepositoryProvider)
          .readLabel(photoPath);
      if (!ref.mounted) return;
      applyLabel(reading);
    } on Object catch (e) {
      if (!ref.mounted) return;
      // The reader's exceptions ARE the sentence a person is shown.
      state = state.copyWith(message: '$e');
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Lands one label reading in the draft. Writes nothing, and confirms
  /// nothing: the figures sit in the fields until Save.
  ///
  /// The column the label printed decides the mode. Where it printed a per-100
  /// column, THAT is what the fields hold — deriving per 100 from the serving
  /// would round away the label's own number. Where it printed only a
  /// per-serving column, the form enters per-serving mode and the existing
  /// arithmetic ([IngredientFormDraft.storedMacros]) derives per 100 from the
  /// serving amount, exactly as a typed-in panel does.
  void applyLabel(LabelReading reading) {
    final per100 = reading.per100;
    final servingUnit = reading.serving.unit;
    final servingAmount = reading.serving.amount;

    final printed = per100?.macros ?? reading.perServing;
    final perServing = per100 == null;
    final basis =
        per100?.basis ??
        (servingUnit == null
            ? state.basis
            : ServingDraft(unit: servingUnit).basis);

    // A figure the label did not print leaves its field alone — unless the
    // reading moved the mode or the basis, where whatever is in the field is
    // about a different hundred and would read as this label's.
    final moved = perServing != state.perServing || basis != state.basis;
    final kept = moved ? const MacroDraft() : state.macros;
    final macros = MacroDraft(
      kcal: _labelField(printed.kcal, kept.kcal),
      protein: _labelField(printed.protein, kept.protein),
      carb: _labelField(printed.carb, kept.carb),
      fat: _labelField(printed.fat, kept.fat),
      fiber: _labelField(printed.fiber, kept.fiber),
    );

    var next = state.copyWith(
      labelUndo: LabelFillUndo(
        macros: state.macros,
        seededMacros: state.seededMacros,
        perServing: state.perServing,
        basis: state.basis,
        serving: state.serving,
        per100Macros: state.per100Macros,
        pendingSource: state.pendingSource,
        pendingSourceLabel: state.pendingSourceLabel,
        pendingSourceScore: state.pendingSourceScore,
      ),
      perServing: perServing,
      basis: basis,
      macros: macros,
      // Re-seeded in the same breath, so the row's own re-seed sees a draft
      // that already matches what it would have written and stands down.
      seededMacros: macros,
      macroSeed: state.macroSeed + 1,
      // Nothing to put back on leaving the mode: a label with no per-100
      // column printed no per-100 figures.
      per100Macros: null,
      // A photo names no food, so the stamp carries no label and no fit score.
      pendingSource: labelPhotoSource,
      pendingSourceLabel: null,
      pendingSourceScore: null,
      message: _labelMessage(reading.notes),
    );

    // The serving is replaced only where the label said one this kitchen can
    // read; a serving printed in words we do not keep leaves the row's own.
    if (servingAmount != null && servingUnit != null) {
      next = next.copyWith(
        serving: ServingDraft(
          amountText: macroFieldSeed(servingAmount),
          unit: servingUnit,
          // The label's line verbatim, so the density sentence can be offered
          // its other half.
          packPrintedText: reading.serving.textPrinted,
        ),
        servingSeed: next.servingSeed + 1,
      );
    }
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// Puts the macro half back the way the last label read found it, and takes
  /// the stamp off the form. Nothing was saved, so nothing is unsaved.
  void undoLabelFill() {
    final undo = state.labelUndo;
    if (undo == null) return;
    final next = state.copyWith(
      macros: undo.macros,
      seededMacros: undo.seededMacros,
      macroSeed: state.macroSeed + 1,
      perServing: undo.perServing,
      basis: undo.basis,
      serving: undo.serving,
      servingSeed: state.servingSeed + 1,
      per100Macros: undo.per100Macros,
      pendingSource: undo.pendingSource,
      pendingSourceLabel: undo.pendingSourceLabel,
      pendingSourceScore: undo.pendingSourceScore,
      labelUndo: null,
      message:
          'Undone — the label’s figures are off the form, and nothing was '
          'saved.',
    );
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// One macro field after a label read: the label's figure where it printed
  /// one, else what was already there.
  static String _labelField(double? printed, String kept) =>
      printed == null ? kept : macroFieldSeed(printed);

  /// The feedback line a read leaves. What the model could not read is said
  /// here rather than hidden, because the fields cannot show an absence.
  static String _labelMessage(List<String> notes) {
    const said = 'Read from a photo — nothing is saved until you tap Save.';
    return notes.isEmpty ? said : '$said ${notes.join(' ')}';
  }

  /// Lands a barcode draft through the shared rule, against the form's own
  /// draft. Never confirms the row.
  void applyScan(IngredientDraft draft) {
    final applied = applyDraft(
      draft,
      target: DraftTarget(
        name: state.name,
        hasMacros: !state.macros.allBlank,
        macrosBasis: state.basis,
        source: state.pendingSource ?? state.row.source,
      ),
    );
    var next = state.copyWith(
      scanned: draft,
      scanApplied: applied,
      packAdded: false,
    );
    if (applied.macros != null) {
      // A per-100 label that also names its serving keeps both: the serving as
      // a measure, the figures in the fields.
      final printedServing = applied.serving;
      final serving = printedServing == null
          ? null
          : ServingDraft(
              amountText: macroFieldSeed(printedServing.amount),
              unit: printedServing.unit,
              packPrinted: printedServing.printed,
              packPrintedText: printedServing.printedText,
            );
      // A pack that printed a per-serving column beside its per-100 one is
      // entered per serving. A serving with no figures, or figures with no
      // serving, stays per 100.
      final printed = printedServing?.printed;
      final perServing = serving != null && printed != null;
      next = next.copyWith(
        basis: perServing ? serving.basis : applied.macrosBasis!,
        macros: MacroDraft.from(perServing ? printed : applied.macros),
        macroSeed: next.macroSeed + 1,
        perServing: perServing,
        per100Macros: perServing ? MacroDraft.from(applied.macros) : null,
      );
      if (serving != null) {
        next = next.copyWith(
          serving: serving,
          servingSeed: next.servingSeed + 1,
        );
      }
    }
    final panel = applied.servingPanel;
    if (panel != null) {
      // A per-serving panel lands in per-serving mode; the serving amount
      // prefills only from a payload number, never parsed from free text.
      final unit = (panel.servingBasis ?? next.basis).baseUnit;
      final amount = panel.servingAmount;
      final serving = ServingDraft(
        amountText: amount == null ? '' : macroFieldSeed(amount),
        unit: unit,
        // The pack's line verbatim, so the density sentence can be offered its
        // other half.
        packPrintedText: panel.servingSize,
      );
      next = next.copyWith(
        perServing: true,
        basis: serving.basis,
        macros: MacroDraft.from(panel.printed),
        macroSeed: next.macroSeed + 1,
        per100Macros: null,
        serving: serving,
        servingSeed: next.servingSeed + 1,
      );
    }
    // `applyDraft` returns a name only where the target's was empty.
    if (applied.name case final scanned?) {
      next = next.copyWith(name: scanned, nameSeed: next.nameSeed + 1);
    }
    // A scan is an exact-key fetch, so its stamp carries the pack's name and no
    // fit score.
    state = applied.source == null
        ? next
        : next.copyWith(
            pendingSource: applied.source,
            pendingSourceLabel: applied.sourceLabel,
            pendingSourceScore: null,
          );
  }

  /// A USDA pick: fills the draft with the macros, the density and the food
  /// they came from. Writes nothing.
  void applyUsdaPick(UsdaCandidate pick) {
    var next = state.copyWith(
      pendingSource: pick.source,
      pendingSourceLabel: pick.description,
      pendingSourceScore: pick.score,
      // A pick replaces the old fill whole, so a food with no density clears
      // the previous food's.
      density: pick.densityGPerMl != null
          ? DensitySet(pick.densityGPerMl!)
          : const DensityCleared(),
      message:
          'Filled from “${pick.description}” — nothing is saved until you '
          'tap Save.',
    );
    if (pick.macros != null) {
      final filled = MacroDraft.from(pick.macros);
      next = next.copyWith(
        macros: filled,
        // Re-seeded in the same breath, so the row's own re-seed sees a draft
        // that already matches what it would have written and stands down.
        seededMacros: filled,
        macroSeed: next.macroSeed + 1,
        perServing: false,
        per100Macros: null,
      );
    }
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// `Not this food`: the fill always comes out of the form, and out of the row
  /// when the row carries it. A pick reaches the draft before the row
  /// (ADR-0011), so both halves are needed.
  Future<void> declineUsda() async {
    final stored = isUsdaPrefilled(state.row.source);
    _dropUsdaFill();
    // A pick that only sat in the draft has no row to clear.
    if (!stored) {
      state = state.copyWith(
        message:
            'Not this food — the pick is off the form, and nothing was '
            'saved.',
      );
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final cleared = await ref
          .read(ingredientRepositoryProvider)
          .declineUsdaPrefill(state.row.id);
      if (!ref.mounted) return;
      if (cleared == null) return;
      state = state.copyWith(
        message:
            'Cleared — the USDA numbers are gone, and a rename will not bring '
            'them back.',
      );
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// Drops the refused fill from the draft: the pending stamp, the density it
  /// asserted (back to unchanged, not cleared) and any macro fields nobody has
  /// typed over ([_rowMoved]'s guard).
  void _dropUsdaFill() {
    var next = state.copyWith(
      pendingSource: null,
      pendingSourceLabel: null,
      pendingSourceScore: null,
      density: const DensityUnchanged(),
    );
    if (state.macros == state.seededMacros) {
      final fresh = MacroDraft.from(state.row.macros);
      next = next.copyWith(
        macros: fresh,
        seededMacros: fresh,
        macroSeed: next.macroSeed + 1,
        perServing: false,
        per100Macros: null,
      );
    }
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  // --- The three writes ----------------------------------------------------

  /// Writes the whole form in one transaction (ADR-0011). Returns the row as
  /// written, or null when the form refused itself. A repository failure
  /// throws; the view's `ref.write` owns the toast.
  Future<Ingredient?> save({bool markComplete = false}) async {
    // The backstop for a name typed and never left.
    if (state.nameEdited) tidyName();
    final refusal = state.refusal;
    if (refusal != null) {
      state = state.copyWith(message: refusal);
      return null;
    }
    state = state.copyWith(busy: true);
    try {
      final result = await ref
          .read(ingredientRepositoryProvider)
          .saveForm(
            // A null id makes the row, its measures and its aliases in one
            // transaction.
            state.creating ? null : state.row.id,
            _edit(markComplete: markComplete),
          );
      if (!ref.mounted) return null;
      if (result case Err(:final failure)) {
        // The write refused a taken name; re-check so the field gets its note
        // back.
        await checkName();
        if (!ref.mounted) return null;
        state = state.copyWith(message: failure.message);
        return null;
      }
      final saved = result.valueOrNull;
      if (saved == null) {
        state = state.copyWith(message: 'It is no longer here.');
        return null;
      }
      // Landed, so the draft empties and a second Save writes nothing twice.
      // The watched queries re-fire on their own.
      state = state.copyWith(
        message: 'Saved.',
        pendingSource: null,
        pendingSourceLabel: null,
        pendingSourceScore: null,
        // The fill is the row's now; undoing it would be an edit, not an undo.
        labelUndo: null,
        density: const DensityUnchanged(),
        pieceWeight: const PieceWeightUnchanged(),
        measuresAdded: const [],
        measuresRemoved: const {},
        aliasesAdded: const [],
        aliasesRemoved: const {},
      );
      return saved;
    } finally {
      if (ref.mounted) state = state.copyWith(busy: false);
    }
  }

  /// The whole form as one intent, including the serving as a `serving`
  /// measure.
  IngredientFormEdit _edit({required bool markComplete}) {
    final serving = state.servingMeasure;
    return IngredientFormEdit(
      row: IngredientEdit(
        canonicalName: state.name,
        defaultUnit: state.defaultUnit,
        macrosBasis: state.basis,
        allowedUnits: state.allowed,
        category: state.category.trim().isEmpty ? null : state.category.trim(),
        macros: state.storedMacros,
        source: state.pendingSource,
        sourceLabel: state.pendingSourceLabel,
        sourceScore: state.pendingSourceScore,
      ),
      density: state.density,
      serving: serving == null
          ? null
          : PendingMeasure(
              id: _uuid.v4(),
              label: serving.label,
              amount: serving.inBasis,
            ),
      measuresAdded: [
        for (final m in state.measuresAdded)
          PendingMeasure(
            id: m.id,
            label: m.label,
            amount: m.amount,
            sortOrder: m.sortOrder,
          ),
      ],
      measuresRemoved: state.measuresRemoved,
      aliasesAdded: [
        for (final a in state.aliasesAdded)
          PendingAlias(id: a.id, text: a.text),
      ],
      aliasesRemoved: state.aliasesRemoved,
      pieceWeight: state.pieceWeight,
      markComplete: markComplete,
    );
  }

  /// Repairs a stranded default, only when asked, and saves at once.
  Future<Ingredient?> fixStrandedDefault() async {
    final fix = basisDefaultUnitFix(state.editedRow);
    setDefaultUnit(fix);
    return save();
  }

  /// Returns a `complete` row to `stub` — confirm is reversible.
  Future<void> unconfirm() async {
    await ref.read(ingredientRepositoryProvider).unconfirm(state.row.id);
    if (!ref.mounted) return;
    state = state.copyWith(
      message:
          'Back to a stub — it stops counting until you complete it again.',
    );
  }

  /// The refusal is the interesting state: it names the count, because "used by
  /// 3 recipes" is a thing a user can act on and "failed" is not.
  Future<DeleteOutcome> delete() async {
    final outcome = await ref
        .read(ingredientRepositoryProvider)
        .softDelete(state.row.id);
    if (!ref.mounted) return outcome;
    state = state.copyWith(
      message: switch (outcome) {
        Deleted() => null,
        final DeleteRefused refused => _refusalSentence(refused),
        DeleteMissing() => 'It is already gone.',
      },
    );
    return outcome;
  }
}

/// The delete refusal for the message line: "Still used by 3 recipes (4 lines).
/// Change those lines first." Week lines join the same sentence; each clause
/// appears only when non-empty.
String _refusalSentence(DeleteRefused refused) {
  final recipes =
      '${refused.recipeCount} ${plural(refused.recipeCount, 'recipe')} '
      '(${refused.lineCount} ${plural(refused.lineCount, 'line')})';
  final planned =
      '${refused.plannedCount} ${plural(refused.plannedCount, 'line')} '
      'in your plan';
  final parts = [
    if (refused.lineCount > 0) recipes,
    if (refused.plannedCount > 0) planned,
  ];
  return 'Still used by ${parts.join(' and ')}. Change those lines first.';
}
