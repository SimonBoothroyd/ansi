/// The ingredient form's state, as one notifier over one draft.
///
/// **Everything the form intends and has not written lives here** — the row's
/// fields, the macros as typed, the density, the measures and aliases added and
/// removed, the USDA pick, the barcode scan — and [IngredientForm.save] writes
/// the lot in a single transaction (ADR-0011). The view reads the draft and
/// dispatches intents; it decides nothing.
///
/// The draft is held as DELTAS rather than as replacement lists: a save that
/// only inserts its adds and tombstones its named removes never needs the whole
/// list, so a measures stream that failed to load cannot become a narrowed set
/// written back.
///
/// **The seams that stay in the view** are the ones that need a
/// `BuildContext`: opening the barcode scanner, opening the USDA short-list,
/// and the failure toast. Each of those hands its result back here as an
/// intent, so the decision about what a result means is still one place —
/// exactly the shape `RecipeEditor` uses for the recipe editor's Save.
library;

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/text/name_clean.dart';
import '../../../core/units/macros.dart';
import '../../../core/units/measure.dart';
import '../../../core/units/number_format.dart';
import '../../../core/units/units.dart';
import '../barcode/barcode_add.dart';
import '../data/ingredient_providers.dart';
import '../domain/allowed_units.dart';
import '../domain/apply_draft.dart';
import '../domain/ingredient.dart';
import '../domain/ingredient_repository.dart';
import '../domain/serving_offer.dart';
import '../domain/suggest_name.dart';
import '../domain/usda_probe.dart';
import 'serving_row.dart';

part 'ingredient_view_models.freezed.dart';
part 'ingredient_view_models.g.dart';

const _uuid = Uuid();

/// A stored double as editable text: `60` not `60.0`, and every other digit
/// kept exactly as stored.
String _seed(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

/// The four macro inputs as typed TEXT, so "half filled in" is a state the form
/// can name rather than a silent zero.
@freezed
abstract class MacroDraft with _$MacroDraft {
  const factory MacroDraft({
    @Default('') String kcal,
    @Default('') String protein,
    @Default('') String carb,
    @Default('') String fat,
  }) = _MacroDraft;

  /// Seeds the four fields from a stored panel.
  ///
  /// **Lossless, deliberately.** These are not printed numbers — they are the
  /// editable text a Save reads back, so `60` must not open as `60.0` and a
  /// USDA-derived `285.7142857` must not open as `285.71`. Rounding here would
  /// make opening a row and saving it untouched a silent edit of its macros.
  /// [formatNumber] is the rule for a number the app only *shows*.
  factory MacroDraft.from(Macros? m) => m == null
      ? const MacroDraft()
      : MacroDraft(
          kcal: _seed(m.kcal),
          protein: _seed(m.protein),
          carb: _seed(m.carb),
          fat: _seed(m.fat),
        );

  const MacroDraft._();

  List<String> get _fields => [kcal, protein, carb, fat];

  bool get allBlank => _fields.every((f) => f.trim().isEmpty);

  /// All four parse, or all four are blank. Anything between is a panel with a
  /// hole in it, which the form refuses rather than zero-filling.
  bool get isCoherent =>
      allBlank ||
      _fields.every((f) => double.tryParse(f.trim())?.isFinite ?? false);

  /// The macros this draft asserts, or null for "none" — the deliberate clear.
  Macros? toMacros() {
    if (allBlank || !isCoherent) return null;
    return Macros(
      kcal: double.parse(kcal.trim()),
      protein: double.parse(protein.trim()),
      carb: double.parse(carb.trim()),
      fat: double.parse(fat.trim()),
    );
  }
}

/// One ingredient form, in flight.
///
/// [row] is the stored row as the watched query last had it — or a blank
/// stand-in while creating, whose id is empty and never used. Everything else
/// is what the form intends.
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

    /// What the row last handed the macro draft. "Untouched" is defined against
    /// this rather than against blankness, so a row that arrives with numbers
    /// is as re-seedable as an empty one.
    required MacroDraft seededMacros,

    /// Bumped on every re-seed, and used as the macro fields' key: `initial`
    /// seeds a controller once, so new text needs a new field to seed it into.
    @Default(0) int macroSeed,

    /// Bumped whenever the name moved by something other than typing — a scan,
    /// or a tidy. The name field pushes the new text into the controller it
    /// already has rather than being replaced around a fresh one, because
    /// replacing a *focused* field is what a Save tapped straight from the
    /// keyboard would do.
    @Default(0) int nameSeed,
    @Default(0) int servingSeed,

    /// The macros section's per-serving mode: the four fields then hold the
    /// label's figures AS PRINTED and the serving row says what they describe,
    /// and what is stored is still per 100 of the basis.
    @Default(false) bool perServing,
    @Default(ServingDraft()) ServingDraft serving,

    /// Whether the serving's "1 tbsp = 14 g" was taken as this row's density
    /// (or a measure). Off by default — a pack's "about 1 tbsp" is sometimes a
    /// guess, and a density minted from a guess decides what units admit.
    @Default(false) bool servingOfferTaken,
    @Default(DensityUnchanged()) DensityChange density,

    /// The piece weight as the form holds it — the count-side twin of
    /// [density], and drafted the same way (ADR-0015).
    @Default(PieceWeightUnchanged()) PieceWeightChange pieceWeight,
    @Default(<Measure>[]) List<Measure> measuresAdded,
    @Default(<String>{}) Set<String> measuresRemoved,
    @Default(<IngredientAlias>[]) List<IngredientAlias> aliasesAdded,
    @Default(<String>{}) Set<String> aliasesRemoved,

    /// A provenance the scan or the USDA pick stamped and the next Save writes
    /// — held with the macros it explains rather than written on its own, so
    /// backing out of the form leaves the row exactly as it was found.
    String? pendingSource,
    String? pendingSourceLabel,
    double? pendingSourceScore,

    /// The last barcode scan: the draft the card shows, what [applyDraft]
    /// decided about it, and whether its pack offer was taken.
    IngredientDraft? scanned,
    DraftApplication? scanApplied,
    @Default(false) bool packAdded,

    /// Set when the measures editor refused a volume-named label and handed
    /// back the resolved spoon — the density entry pre-picks it.
    Unit? redirectedSpoon,

    /// The name as it was typed, when [IngredientForm.tidyName] replaced a
    /// WORD in it — what the `was “…”` line under the field prints, and what
    /// *keep the old word* puts back. Null when nothing was suggested.
    String? nameWas,

    /// A typed name the person chose to KEEP. While [name] is exactly this,
    /// the tidy recases and respaces but suggests nothing: a suggestion once
    /// refused must not be offered again on the next leave. Cleared by the
    /// next edit, and carried forward when the tidy's own recasing moves it.
    String? namePinned,

    /// Whether a person has typed in the name field during this sitting.
    ///
    /// Save tidies only what somebody wrote. A stored name is not rewritten by
    /// a Save that was about the macros — the row's own name is a thing a
    /// human already chose, and a save of something else is no occasion to
    /// take it away.
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

  /// The row as the FORM currently reads it: the stored facts with the draft
  /// choices the admission rule turns on — the default unit, the macros basis,
  /// the density and the piece weight — folded in. Every "what may this row
  /// say" question asks this rather than the stored row, so flipping the basis
  /// chip moves the locks and the flag with it.
  Ingredient get editedRow => row.copyWith(
    defaultUnit: defaultUnit,
    macrosBasis: basis,
    densityGPerMl: densityValue,
    pieceBasisAmount: pieceWeightValue,
  );

  /// The four fields as numbers, whatever mode they are in.
  Macros? get printedMacros => macros.toMacros();

  /// What Save would STORE: per 100 of the basis. In per-serving mode that is
  /// the derivation, which is null until the serving weight is in — nothing is
  /// stored that was divided by a blank.
  Macros? get storedMacros {
    if (!perServing) return printedMacros;
    final printed = printedMacros;
    final amount = serving.amount;
    if (printed == null || amount == null) return null;
    return Macros.per100From(serving: amount, basis: basis, printed: printed);
  }

  /// What the serving row's name and weight ALSO say, or null.
  ServingOffer? get offer => perServing
      ? servingOfferFor(
          amount: serving.amount,
          name: serving.name,
          basis: basis,
        )
      : null;

  bool get stub => row.status == IngredientStatus.stub;

  /// Why this form cannot be saved yet, in the user's words, or null.
  ///
  /// It lives on the draft rather than inside [IngredientForm.save] because a
  /// dock has to ask it *before* the tap: the create form's one button is
  /// enabled by [completable], and the line above it prints this.
  String? get refusal {
    if (name.trim().isEmpty) {
      return 'A name is the one field an ingredient can’t go without.';
    }
    if (!macros.isCoherent) {
      return 'Enter all four macros, or leave them all blank — a part of a '
          'panel isn’t a panel.';
    }
    if (perServing && printedMacros != null && serving.amount == null) {
      return 'One serving is how much? The label’s figures become per 100 '
          'only once the serving weight is typed.';
    }
    // D4c, held on the write side too. The chips refuse to OFFER a default
    // the row cannot say, but a basis flipped (or a USDA pick landed) after
    // the pick strands the one already chosen, and a flag beside it is only
    // advice a Save can walk past. The row is still never rewritten silently:
    // this names what is wrong and leaves both fixes to the person.
    if (!unitSayableAsDefault(editedRow, defaultUnit)) {
      final basisWord = basis == MacrosBasis.perMl ? 'ml' : 'g';
      return 'Macros per 100 $basisWord and no density can’t have '
          '${defaultUnit.label} as the default unit — add a density '
          'below, or make it ${basisDefaultUnitFix(editedRow).label}.';
    }
    // The count-side twin of D4c (ADR-0015): a `piece` default with nothing
    // weighing a piece is a count the converter can never bridge, and the
    // owner's ruling is that such a row is not saveable. Same manners — the
    // refusal names both ways out and the person picks one.
    if (defaultUnitNeedsPieceWeight(editedRow)) {
      return 'Piece can’t be the default unit with nothing weighing one — '
          'enter what one weighs below, or make it '
          '${basisDefaultUnitFix(editedRow).label}.';
    }
    return null;
  }

  /// Whether this form would land a row that **counts**: nothing refused, and
  /// macros on a basis. It is exactly the gate `Mark complete` applies to a
  /// stub, asked of the draft instead of the stored row — which is what lets
  /// the create form offer one button and mean it.
  bool get completable => refusal == null && storedMacros != null;
}

/// The form's ViewModel — one per ingredient id, and one for the create form
/// (a null id, which is what makes this the app's one add flow).
@riverpod
class IngredientForm extends _$IngredientForm {
  @override
  IngredientFormDraft build(String? ingredientId, {String initialName = ''}) {
    // The row is a WATCHED query, and it moves under an open form: this
    // device's own Save, and a second device's edit. Listened to rather than
    // watched, because rebuilding this notifier on every row change would
    // throw away the draft — what a moving row is allowed to do is re-seed
    // the macro fields, below, and only while nobody has typed in them.
    if (ingredientId != null) {
      ref.listen(ingredientByIdProvider(ingredientId), (_, next) {
        final row = next.asData?.value;
        if (row != null) _rowMoved(row);
      });
    }
    final row =
        (ingredientId == null
            ? null
            : ref.read(ingredientByIdProvider(ingredientId)).asData?.value) ??
        Ingredient(
          id: ingredientId ?? '',
          // The create form's seed is a picker query, which is prose. Only
          // the silent half applies — the field must open reading exactly
          // what a Save would write, and choosing a different WORD is not the
          // picker's to do.
          canonicalName: cleanName(initialName, NameKind.title),
          defaultUnit: g,
          status: IngredientStatus.stub,
        );
    final seeded = MacroDraft.from(row.macros);
    return IngredientFormDraft(
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
  }

  /// The admission set [allowed] would be, given the density and the piece
  /// weight [row] carries: a density unlocks the other family's units and
  /// removing it strips them; a piece weight unlocks `piece` on a count row
  /// and removing it strips that (ADR-0015). `piece` is never kept on a row
  /// whose default is not a count. Derived here rather than by an effect that
  /// watches the numbers, so the chips and the stored set can never disagree.
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

  /// **A lookup's numbers reach the FIELDS, not just the row.**
  ///
  /// The macro inputs are seeded once, when their controllers are built, so a
  /// write that put macros on the row re-rendered everything *derived* from it
  /// while the four fields went on showing the blanks they were born with. The
  /// re-seed bumps [IngredientFormDraft.macroSeed], which is the fields' key,
  /// so the framework rebuilds the controllers around their new text.
  ///
  /// The guard is what keeps a pending edit safe: the draft is re-seeded only
  /// while it still says exactly what the row last put there. Type into any
  /// macro field and the row's own changes stop overwriting you.
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
    );
  }

  // --- The row's own fields ------------------------------------------------

  /// The name as the field now reads.
  ///
  /// Text identical to what the draft already holds is not an edit: pushing a
  /// re-seeded name into the field's controller echoes back through here, and
  /// treating that echo as typing would lift the pin and clear the `was` line
  /// the same tidy had just set.
  void setName(String name) {
    if (name == state.name) return;
    state = state.copyWith(
      name: name,
      nameEdited: true,
      nameWas: null,
      namePinned: null,
    );
  }

  /// The name field was left (or Save is about to write it): [cleanName],
  /// then the ingredient suggestion.
  ///
  /// Recasing and respacing are silent — the field simply reads right. A word
  /// changing is not: [IngredientFormDraft.nameWas] is set and the view prints
  /// the revert line under the field. A pinned name skips the suggestion and
  /// keeps its pin through the recasing, so *keep the old word* holds for as
  /// long as the person leaves that name alone.
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
    );
  }

  void setCategory(String category) =>
      state = state.copyWith(category: category);

  /// Only a sayable unit is offered (the rest are named in the note under the
  /// row), so admitting the pick can never strand the row on the density side.
  /// `piece` is the one exception by design: it is offered with no weight yet,
  /// because picking it is what makes the weight sentence appear — the
  /// admission rule then keeps `piece` locked until the number is in, and Save
  /// refuses meanwhile.
  void setDefaultUnit(Unit unit) {
    final next = state.copyWith(
      defaultUnit: unit,
      allowed: {...state.allowed, unit},
    );
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  void toggleUnit(Unit unit) {
    final next = {...state.allowed};
    if (!next.remove(unit)) next.add(unit);
    state = state.copyWith(allowed: next);
  }

  /// Per 100 of the basis — the mode a row's own macros are in by definition.
  void setBasis(MacrosBasis basis) =>
      state = state.copyWith(perServing: false, basis: basis);

  /// The serving's unit sets the BASIS, so the admission chips follow it live.
  void setServingBasis(MacrosBasis basis) =>
      state = state.copyWith(basis: basis);

  void setPerServing() => state = state.copyWith(perServing: true);

  void setMacros(MacroDraft macros) => state = state.copyWith(macros: macros);

  void setServingAmount(String text) =>
      state = state.copyWith(serving: state.serving.copyWith(amountText: text));

  void setServingName(String text) =>
      state = state.copyWith(serving: state.serving.copyWith(name: text));

  void takeServingOffer({required bool taken}) =>
      state = state.copyWith(servingOfferTaken: taken);

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

  /// What one of these weighs, in the basis unit — drafted, not written; the
  /// chips follow it through the admission rule exactly as they follow the
  /// density.
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

  /// The scan's pack size, taken. It lands in the draft, so it rides the form's
  /// one Save like every other measure — which is what lets a barcode-created
  /// row carry its pack size before the row exists.
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

  /// Minted here and kept: the save inserts under this id.
  void addAlias(String text) => state = state.copyWith(
    aliasesAdded: [
      ...state.aliasesAdded,
      IngredientAlias(
        id: _uuid.v4(),
        text: cleanName(text, NameKind.alias),
        source: 'manual',
      ),
    ],
  );

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

  // --- The two prefill doors -----------------------------------------------

  /// A barcode draft, landed through the shared rule and against the form's OWN
  /// draft — a panel typed and not yet saved is as much the human's as a saved
  /// one. Nothing here confirms the row.
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
      next = next.copyWith(
        basis: applied.macrosBasis!,
        macros: MacroDraft.from(applied.macros),
        macroSeed: next.macroSeed + 1,
        perServing: false,
      );
    }
    final panel = applied.servingPanel;
    if (panel != null) {
      // A per-serving panel lands on the per-serving mode: the four as printed,
      // the serving amount prefilled when the payload had a number and
      // otherwise left for the person, never parsed out of the free text.
      next = next.copyWith(
        perServing: true,
        basis: panel.servingBasis ?? next.basis,
        macros: MacroDraft.from(panel.printed),
        macroSeed: next.macroSeed + 1,
        serving: ServingDraft.fromPanel(panel),
        servingSeed: next.servingSeed + 1,
        servingOfferTaken: false,
      );
    }
    // **The name, when there isn't one yet.** `applyDraft` returns one only
    // where the target's was EMPTY, so on an existing row it never fires; on a
    // new row it is the difference between a scan that fills the form in and a
    // Save that refuses for want of a name. A starting point, not a decision.
    if (applied.name case final scanned?) {
      next = next.copyWith(name: scanned, nameSeed: next.nameSeed + 1);
    }
    // A stamp travels with the name of the pack it points at, and with NO fit
    // score: a scan is an exact-key fetch, so there is no coverage of the typed
    // name to report and a stale one would describe a food that is no longer
    // the row's. A draft that stamps nothing leaves all three alone.
    state = applied.source == null
        ? next
        : next.copyWith(
            pendingSource: applied.source,
            pendingSourceLabel: applied.sourceLabel,
            pendingSourceScore: null,
          );
  }

  /// A USDA pick. **It writes nothing** — it fills the draft with the macros,
  /// the density and which food they came from, and the form's own Save lands
  /// the lot. That is also what lets it work on a row that does not exist yet.
  void applyUsdaPick(UsdaCandidate pick) {
    var next = state.copyWith(
      pendingSource: pick.source,
      pendingSourceLabel: pick.description,
      pendingSourceScore: pick.score,
      // A pick replaces the old fill WHOLE, so a food with no density of its
      // own clears the one the previous food supplied — otherwise the row keeps
      // a number that came from a match the household has just rejected.
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
      );
    }
    state = next.copyWith(allowed: _admissionFor(next.editedRow, next.allowed));
  }

  /// *Not this food*: one write clears the prefilled density and macros and
  /// marks the row declined. The macro fields follow through the row's own
  /// re-seed, the chips through the admission rule.
  Future<void> declineUsda() async {
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

  // --- The three writes ----------------------------------------------------

  /// **One call.** The row's fields, the density, the piece weight, every
  /// measure added and removed, the aliases and — when the CTA asked — the
  /// status flip, in a single transaction (ADR-0011). Nothing here can
  /// half-land.
  ///
  /// Returns the row as the write left it, or null when the form refused
  /// itself — the message line then says why. A repository failure THROWS: the
  /// view's `ref.write` owns the toast, the same way the recipe editor's Save
  /// does.
  Future<Ingredient?> save({bool markComplete = false}) async {
    // The backstop for a field that was TYPED IN and never left — Save tapped
    // straight from the keyboard. A name nobody touched is left exactly as the
    // row has it.
    if (state.nameEdited) tidyName();
    final refusal = state.refusal;
    if (refusal != null) {
      state = state.copyWith(message: refusal);
      return null;
    }
    state = state.copyWith(busy: true);
    try {
      final saved = await ref
          .read(ingredientRepositoryProvider)
          .saveForm(
            // A null id makes the row, its measures and its aliases in one
            // transaction.
            state.creating ? null : state.row.id,
            _edit(markComplete: markComplete),
          );
      if (!ref.mounted) return saved;
      if (saved == null) {
        state = state.copyWith(message: 'It is no longer here.');
        return null;
      }
      // Landed, so the draft empties: a second Save must not write any of it
      // twice. This is the one place the draft is discarded on purpose. The
      // row, its measures and its aliases are watched queries, so nothing is
      // invalidated here — the write that just landed re-fires them.
      state = state.copyWith(
        message: 'Saved.',
        pendingSource: null,
        pendingSourceLabel: null,
        pendingSourceScore: null,
        servingOfferTaken: false,
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

  /// The whole form as one intent. The serving offer, when taken, rides the
  /// same write as everything else.
  IngredientFormEdit _edit({required bool markComplete}) {
    final taken = state.servingOfferTaken ? state.offer : null;
    final offeredDensity = taken is DensityOffer ? taken.gPerMl : null;
    final offeredMeasure = taken is MeasureOffer ? taken : null;
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
      density: offeredDensity != null
          ? DensitySet(offeredDensity)
          : state.density,
      measuresAdded: [
        for (final m in state.measuresAdded)
          PendingMeasure(id: m.id, label: m.label, amount: m.amount),
        if (offeredMeasure != null)
          PendingMeasure(
            id: _uuid.v4(),
            label: offeredMeasure.label,
            amount: offeredMeasure.amount,
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

  /// A stored default the rules no longer support — a cup default on a
  /// per-100 g row with no density. Repaired only when asked, and saved in the
  /// same breath so the row stops being broken.
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
        DeleteRefused(:final recipeCount, :final lineCount) =>
          'Still used by $recipeCount '
              '${recipeCount == 1 ? 'recipe' : 'recipes'} '
              '($lineCount ${lineCount == 1 ? 'line' : 'lines'}). '
              'Change those lines first.',
        DeleteMissing() => 'It is already gone.',
      },
    );
    return outcome;
  }
}
