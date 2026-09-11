/// The ingredient form's ViewModel, with no widget tree in the way.
///
/// The app's most complex write path used to be reachable only through the UI:
/// thirty pieces of state in one `build()`, and the only way to ask what Save
/// would send was to pump a form and tap it. These ask the notifier directly —
/// what the draft holds after each intent, and what one call hands the
/// repository.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/measure.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/barcode/ingredient_draft.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';
import '../../helpers/fake_measure_repository.dart';

/// A weighed count row (ADR-0015): the piece weight is what keeps `piece` in
/// its admission set, and what keeps its own default off the stranded list.
const _mango = Ingredient(
  id: 'mango',
  canonicalName: 'Mango',
  defaultUnit: pieces,
  status: IngredientStatus.stub,
  category: 'produce',
  allowedUnits: [pieces, g, kg],
  pieceBasisAmount: 200,
  pieceSource: 'manual',
  source: 'seed',
);

/// The same row before anybody weighed one — a stranded `piece` default.
const _unweighedMango = Ingredient(
  id: 'mango',
  canonicalName: 'Mango',
  defaultUnit: pieces,
  status: IngredientStatus.stub,
  category: 'produce',
  allowedUnits: [g, kg],
  source: 'seed',
);

/// A candidate carrying both numbers a pick can fill — what the draft holds
/// after one, and what refusing it has to take back out.
const _mangoRaw = UsdaCandidate(
  fdcId: 11216,
  description: 'Mango, raw',
  source: 'usda_fdc:11216',
  score: 1,
  densityGPerMl: 0.35,
  macros: Macros(kcal: 60, protein: 1, carb: 15, fat: 0),
);

/// A bare stub with nothing in its macro fields — the row a scan lands on.
const _bareStub = Ingredient(
  id: 'bare',
  canonicalName: 'Cheddar shreds',
  defaultUnit: g,
  status: IngredientStatus.stub,
  source: 'manual',
);

/// One open form over the fake repository: the notifier, and a reader for the
/// draft it is holding right now.
///
/// Both providers are LISTENED to for the length of the test. They are
/// auto-dispose, so a bare `read` would tear the notifier down between two
/// lines of a test — and the row has to have arrived from the watched query
/// before the draft is seeded from it.
typedef _OpenForm = ({IngredientForm form, IngredientFormDraft Function() at});

Future<_OpenForm> _open(
  FakeIngredientRepo repo, {
  String? id,
  String initialName = '',
  FakeMeasureRepo? measures,
}) async {
  final container = ProviderContainer(
    overrides: [
      ingredientRepositoryProvider.overrideWithValue(repo),
      if (measures != null)
        measureRepositoryProvider.overrideWithValue(measures),
    ],
  );
  addTearDown(container.dispose);
  if (id != null) {
    final row = container.listen(ingredientByIdProvider(id), (_, _) {});
    addTearDown(row.close);
    await container.read(ingredientByIdProvider(id).future);
    if (measures != null) {
      // The row's own serving reaches the draft through this stream, so it
      // has to have arrived before the form opens — the same reason the row
      // above is awaited. (The late-arrival path has its own test.)
      final list = container.listen(ingredientMeasuresProvider(id), (_, _) {});
      addTearDown(list.close);
      await container.read(ingredientMeasuresProvider(id).future);
      // The fake's change stream is a broadcast one and the generator behind
      // it subscribes only once its first value has been consumed, so an add
      // made before this point is dropped rather than delivered.
      await pumpEventQueue();
    }
  }
  final provider = ingredientFormProvider(id, initialName: initialName);
  final open = container.listen(provider, (_, _) {});
  addTearDown(open.close);
  return (
    form: container.read(provider.notifier),
    at: () => container.read(provider),
  );
}

void main() {
  group('the draft the form holds', () {
    test(
      'seeds from the row — name, category, unit, basis and admission',
      () async {
        final repo = FakeIngredientRepo([_mango]);
        final draft = (await _open(repo, id: 'mango')).at();

        expect(draft.creating, isFalse);
        expect(draft.name, 'Mango');
        expect(draft.category, 'produce');
        expect(draft.defaultUnit, pieces);
        expect(draft.basis, MacrosBasis.perG);
        expect(draft.allowed, {pieces, g, kg});
        expect(draft.macros.allBlank, isTrue);
        expect(draft.stub, isTrue);
      },
    );

    test('a create has no row behind it and opens on the name it was '
        'handed', () async {
      final repo = FakeIngredientRepo(const []);
      final draft = (await _open(repo, initialName: '  curry leaves  ')).at();

      expect(draft.creating, isTrue);
      // The picker's query is prose; the field opens on the tidied name, and
      // on exactly what a Save would write.
      expect(draft.name, 'Curry Leaves');
      expect(draft.row.id, isEmpty);
    });

    test('a piece weight unlocks `piece`, and removing it strips it — the '
        'count-side twin of the density pair (ADR-0015)', () async {
      final repo = FakeIngredientRepo([_unweighedMango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      expect(at().allowed, isNot(contains(pieces)));

      form.draftPieceWeight(350);
      expect(at().pieceWeightValue, 350);
      expect(at().allowed, contains(pieces));

      form.removePieceWeight();
      expect(at().pieceWeightValue, isNull);
      expect(at().allowed, isNot(contains(pieces)));
      // Nothing was written: the draft holds it until Save, as the density is
      // held (W5).
      expect(repo.rows.single.pieceBasisAmount, isNull);
    });

    test('moving the default off the count drops `piece` from the draft — it '
        'is offered only where the row is counted', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      expect(at().allowed, contains(pieces));

      form.setDefaultUnit(g);
      expect(at().allowed, isNot(contains(pieces)));
      // …and going back is one tap, because the weight is still on the row.
      form.setDefaultUnit(pieces);
      expect(at().allowed, contains(pieces));
    });

    test('the default unit cannot be toggled off — a row keeps the word it is '
        'bought in', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');
      expect(at().defaultUnit, g);

      form.toggleUnit(g);
      expect(at().allowed, contains(g), reason: 'the default is not prunable');

      // Every other chip is still the household's to turn off…
      form.toggleUnit(kg);
      expect(at().allowed, isNot(contains(kg)));

      // …and the lock follows the row rather than the unit: move the default
      // onto `oz` and `g` prunes like anything else, while `oz` stops.
      form.setDefaultUnit(oz);
      expect(at().defaultUnit, oz);
      form.toggleUnit(g);
      expect(at().allowed, isNot(contains(g)));
      form.toggleUnit(oz);
      expect(at().allowed, contains(oz));
    });

    test('a density unlocks the volume units, and removing it strips '
        'them', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');

      form.draftDensity(0.66);
      expect(at().densityValue, 0.66);
      expect(at().allowed, contains(ml));

      form.removeDensity();
      expect(at().densityValue, isNull);
      expect(at().allowed, isNot(contains(ml)));
    });

    test('per serving derives what is STORED, and says nothing until the '
        'weight is in', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form
        ..setPerServing()
        ..setMacros(
          const MacroDraft(kcal: '30', protein: '1', carb: '7', fat: '0'),
        );

      // The four are as PRINTED; the serving weight is what turns them into a
      // per-100 row, so until it is typed there is nothing to store.
      expect(at().printedMacros!.kcal, 30);
      expect(at().storedMacros, isNull);

      form.setServingAmount('50');
      expect(at().storedMacros!.kcal, 60);
      // The serving states no density: that is the density section's subject,
      // and the row is per 100 g because `g` is what the picker says.
      expect(at().basis, MacrosBasis.perG);
      expect(at().densityPrefill, isNull);
    });

    test('a volume serving lands the row per 100 ml, through the catalog and '
        'no density at all', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form
        ..setPerServing()
        ..setServingUnit(cup)
        ..setServingAmount('1')
        ..setMacros(
          const MacroDraft(kcal: '110', protein: '1', carb: '17', fat: '5'),
        );

      // 1 cup is 236.5882365 ml by the catalog — exact, and nothing weighs it.
      expect(at().basis, MacrosBasis.perMl);
      expect(at().storedMacros!.kcal, closeTo(110 / 236.5882365 * 100, 1e-9));
      expect(at().densityValue, isNull);
      // The density section is offered the serving as its left-hand side. A
      // serving nobody read off a pack states no weight, so the sentence's
      // other half is still the person's to type.
      expect(at().densityPrefill, (amount: 1.0, unit: cup, grams: null));
    });

    test(
      'the mode chips clear the four fields, and put them back derived',
      () async {
        final repo = FakeIngredientRepo([_mango]);
        final (:form, :at) = await _open(repo, id: 'mango');
        // Per 100 → per serving CLEARS: those figures were per 100, and reading
        // them as per serving is how a right number becomes a wrong one.
        form
          ..setMacros(
            const MacroDraft(kcal: '60', protein: '1', carb: '15', fat: '0'),
          )
          ..setPerServing();
        expect(at().macros.allBlank, isTrue);

        // Back to per 100 and the fields hold the DERIVATION, not the label.
        form
          ..setServingAmount('2')
          ..setServingUnit(tbsp)
          ..setMacros(
            const MacroDraft(kcal: '190', protein: '7', carb: '7', fat: '16'),
          )
          ..setBasis(MacrosBasis.perMl);
        expect(at().perServing, isFalse);
        expect(
          double.parse(at().macros.kcal),
          closeTo(190 / (2 * 14.78676478125) * 100, 1e-9),
        );

        // And a mode tapped by accident costs nothing: nothing typed in it, so
        // what it cleared comes back.
        form
          ..setBasis(MacrosBasis.perG)
          ..setMacros(
            const MacroDraft(kcal: '60', protein: '1', carb: '15', fat: '0'),
          )
          ..setPerServing();
        expect(at().macros.allBlank, isTrue);
        form.setBasis(MacrosBasis.perG);
        expect(at().macros.kcal, '60');
      },
    );

    test('leaving per serving with figures and NO serving amount keeps them, '
        'and asks for the number it is missing', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');
      form
        ..setPerServing()
        ..setMacros(
          const MacroDraft(kcal: '180', protein: '6', carb: '10', fat: '14'),
        );
      final typed = at().macros;

      form.setBasis(MacrosBasis.perG);

      // The mode stands and so do the figures. Blanking them is what invited
      // a label's serving column to be retyped as per 100, and carrying them
      // across would relabel that column as a fact about 100 g.
      expect(at().perServing, isTrue);
      expect(at().macros, typed);
      expect(at().message, startsWith('One serving is how much?'));
      // Exactly the sentence Save says about the same missing number.
      expect(at().message, at().refusal);

      // With the serving in, the switch goes through and the fields hold the
      // derivation, as they always did.
      form
        ..setServingAmount('32')
        ..setBasis(MacrosBasis.perG);
      expect(at().perServing, isFalse);
      expect(double.parse(at().macros.kcal), closeTo(562.5, 1e-9));
    });

    test('with nothing typed in the mode it still leaves on the first tap — '
        'a mis-tap costs a person nothing', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form
        ..setMacros(
          const MacroDraft(kcal: '60', protein: '1', carb: '15', fat: '0'),
        )
        ..setPerServing();
      expect(at().macros.allBlank, isTrue);

      form.setBasis(MacrosBasis.perG);

      expect(at().perServing, isFalse);
      expect(at().macros.kcal, '60');
      expect(at().message, isNull);
    });

    test('the seeded fields are LOSSLESS — opening a row and saving it '
        'untouched writes back exactly what was stored', () async {
      // A USDA-derived panel is unrounded (`Macros.per100From` divides). The
      // four fields are editable text a Save reads back, not a printed number,
      // so seeding them through the display rule would make merely opening the
      // form and tapping Save a silent edit of the row's macros.
      const derived = Macros(
        kcal: 285.7142857,
        protein: 6.5,
        carb: 19,
        fat: 1.0666,
      );
      final repo = FakeIngredientRepo([_mango.copyWith(macros: derived)]);
      final (:form, :at) = await _open(repo, id: 'mango');

      expect(at().macros.kcal, '285.7142857');
      expect(at().macros.protein, '6.5');
      expect(at().macros.carb, '19', reason: 'a whole number loses its .0');
      expect(at().macros.fat, '1.0666');

      await form.save();

      expect(repo.savedForms.single.row.macros, derived);
    });

    test('a USDA pick fills the draft and writes nothing', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form.applyUsdaPick(_mangoRaw);

      final draft = at();
      expect(draft.pendingSource, 'usda_fdc:11216');
      expect(draft.pendingSourceLabel, 'Mango, raw');
      expect(draft.macros.kcal, '60');
      expect(draft.densityValue, 0.35);
      expect(repo.savedForms, isEmpty, reason: 'a pick writes nothing');
      expect(repo.rows.single.macros, isNull);
    });

    test('refusing a pick that is still in the draft takes the stamp AND its '
        'numbers back out — the next Save must not write the food that was '
        'just refused', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form.applyUsdaPick(_mangoRaw);
      await form.declineUsda();

      final draft = at();
      expect(draft.pendingSource, isNull);
      expect(draft.pendingSourceLabel, isNull);
      expect(draft.pendingSourceScore, isNull);
      // The fields and the density go back to the row's own — nothing was
      // written, so there is nothing for the undo to have cleared.
      expect(draft.macros.kcal, isEmpty);
      expect(draft.densityValue, isNull);
      // The row never carried the pick, so the decline had nothing to write.
      expect(repo.rows.single.source, 'seed');
      expect(repo.savedForms, isEmpty);

      await form.save();
      expect(repo.savedForms.single.row.source, isNull);
      expect(repo.savedForms.single.row.sourceLabel, isNull);
    });

    test('picking again after a decline puts the new food in the draft — a '
        'refusal is not a lock', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form.applyUsdaPick(_mangoRaw);
      await form.declineUsda();
      form.applyUsdaPick(_mangoRaw);

      expect(at().pendingSource, 'usda_fdc:11216');
      expect(at().pendingSourceLabel, 'Mango, raw');
      expect(at().macros.kcal, '60');
      expect(at().densityValue, 0.35);
    });
  });

  group('a row that states a serving reopens in it', () {
    /// A carton entered from its label: the panel is stored per 100 ml and the
    /// serving it was typed in is half of that.
    const carton = Ingredient(
      id: 'carton',
      canonicalName: 'Oat Milk',
      defaultUnit: ml,
      status: IngredientStatus.complete,
      category: 'pantry',
      macrosBasis: MacrosBasis.perMl,
      macros: Macros(kcal: 500, protein: 10, carb: 20, fat: 30, fiber: 4),
      source: 'manual',
    );
    const cartonServing = Measure(
      id: 's1',
      label: 'serving · 50 ml',
      amount: 50,
      basis: MacrosBasis.perMl,
      source: 'manual',
    );

    /// A pack whose serving is a weight — the per-100 g leg of the same rule.
    const pack = Ingredient(
      id: 'pack',
      canonicalName: 'Cheddar Shreds',
      defaultUnit: g,
      status: IngredientStatus.complete,
      category: 'dairy',
      macros: Macros(kcal: 400, protein: 24, carb: 4, fat: 32),
      source: 'manual',
    );

    test('the form opens per serving, with the label’s own figures in the '
        'fields', () async {
      final repo = FakeIngredientRepo([carton]);
      final (:form, :at) = await _open(
        repo,
        id: 'carton',
        measures: FakeMeasureRepo(const [cartonServing]),
      );

      final draft = at();
      expect(draft.perServing, isTrue);
      expect(draft.basis, MacrosBasis.perMl);
      // The label's words, not a conversion of them.
      expect(draft.serving.amountText, '50');
      expect(draft.serving.unit, ml);
      // Half of 100 ml, so half of every figure — the reverse of the
      // arithmetic that stored them, unrounded.
      expect(
        draft.macros,
        const MacroDraft(
          kcal: '250',
          protein: '5',
          carb: '10',
          fat: '15',
          fiber: '2',
        ),
      );
      // The fields were seeded, so their controllers have to be rebuilt.
      expect(draft.macroSeed, greaterThan(0));
      expect(draft.servingSeed, greaterThan(0));
      // And what Save would store is what the row already says.
      expect(draft.storedMacros, carton.macros);
      // Leaving the mode puts the row's own per-100 column back.
      form.setBasis(MacrosBasis.perMl);
      expect(at().perServing, isFalse);
      expect(at().macros, MacroDraft.from(carton.macros));
    });

    test('a Save straight from the reopened form writes the same per 100 '
        'back, and the same serving', () async {
      final repo = FakeIngredientRepo([carton]);
      final (:form, :at) = await _open(
        repo,
        id: 'carton',
        measures: FakeMeasureRepo(const [cartonServing]),
      );

      await form.save();

      final asked = repo.savedForms.single;
      expect(asked.row.macros, carton.macros);
      expect(asked.row.macrosBasis, MacrosBasis.perMl);
      expect(asked.serving!.label, 'serving · 50 ml');
      expect(asked.serving!.amount, 50);
    });

    test('a serving the label states in spoons comes back in spoons', () async {
      final repo = FakeIngredientRepo([carton]);
      final (:form, :at) = await _open(
        repo,
        id: 'carton',
        measures: FakeMeasureRepo(const [
          Measure(
            id: 's1',
            label: 'serving · 2 tsp',
            amount: 9.8578431875,
            basis: MacrosBasis.perMl,
            source: 'manual',
          ),
        ]),
      );

      expect(at().serving.amountText, '2');
      expect(at().serving.unit, tsp);
      // 2 tsp is 9.86 ml by the catalog, and the round trip through it is
      // exact: what Save would store is what is stored.
      expect(at().storedMacros!.kcal, closeTo(500, 1e-9));
      expect(at().storedMacros!.fat, closeTo(30, 1e-9));
    });

    test('a row with no serving opens per 100, exactly as it always '
        'has', () async {
      final repo = FakeIngredientRepo([carton]);
      final (:form, :at) = await _open(
        repo,
        id: 'carton',
        measures: FakeMeasureRepo(),
      );

      expect(at().perServing, isFalse);
      expect(at().macros, MacroDraft.from(carton.macros));
      expect(at().serving.amount, isNull);
    });

    test('a measure that is not the serving is not read as one', () async {
      final repo = FakeIngredientRepo([pack]);
      final (:form, :at) = await _open(
        repo,
        id: 'pack',
        measures: FakeMeasureRepo(const [
          Measure(id: 'm1', label: 'handful', amount: 30, source: 'manual'),
        ]),
      );

      expect(at().perServing, isFalse);
    });

    test('a serving that arrives after the form is open still seeds '
        'it', () async {
      final repo = FakeIngredientRepo([pack]);
      final measures = FakeMeasureRepo();
      final (:form, :at) = await _open(repo, id: 'pack', measures: measures);
      expect(at().perServing, isFalse);

      // The measures are a watched query: the first frame can precede them.
      await measures.addMeasure(
        ingredientId: 'pack',
        label: 'serving · 50 g',
        amount: 50,
      );
      await pumpEventQueue();

      expect(at().perServing, isTrue);
      expect(at().serving.amountText, '50');
      expect(at().serving.unit, g);
      expect(at().macros.kcal, '200');
    });

    test('a panel somebody is typing is never relabelled per serving under '
        'their hands', () async {
      final repo = FakeIngredientRepo([pack]);
      final measures = FakeMeasureRepo();
      final (:form, :at) = await _open(repo, id: 'pack', measures: measures);

      form.setMacros(
        const MacroDraft(kcal: '111', protein: '1', carb: '2', fat: '3'),
      );
      await measures.addMeasure(
        ingredientId: 'pack',
        label: 'serving · 50 g',
        amount: 50,
      );
      await pumpEventQueue();

      expect(at().perServing, isFalse);
      expect(at().macros.kcal, '111');
    });
  });

  group('save — one call, everything the form is holding', () {
    test('the row half, the density, the measures, the aliases and the '
        'admission set travel together', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form
        ..setName('Ripe mango')
        ..setCategory('  produce  ')
        ..setDefaultUnit(g)
        ..setMacros(
          const MacroDraft(kcal: '60', protein: '1', carb: '15', fat: '0'),
        )
        ..draftDensity(0.66);
      await form.addAlias('mangoes');
      final measure = form.draftMeasure('whole', 200, sortOrder: 0);

      final saved = await form.save(markComplete: true);

      expect(saved, isNotNull);
      final asked = repo.savedForms.single;
      // A name that was typed in is tidied on the way out.
      expect(asked.row.canonicalName, 'Ripe Mango');
      expect(asked.row.category, 'produce', reason: 'trimmed');
      expect(asked.row.defaultUnit, g);
      expect(asked.row.macros!.kcal, 60);
      expect(asked.row.allowedUnits, containsAll(<Unit>[g, ml]));
      expect(asked.density, isA<DensitySet>());
      expect((asked.density as DensitySet).gPerMl, 0.66);
      expect(asked.measuresAdded.single.id, measure.id);
      expect(asked.measuresAdded.single.label, 'whole');
      expect(asked.aliasesAdded.single.text, 'mangoes');
      expect(asked.markComplete, isTrue);
    });

    test('the serving rides the same write, as ONE measure', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      form
        ..setPerServing()
        ..setServingUnit(tbsp)
        ..setServingAmount('2')
        ..setMacros(
          const MacroDraft(kcal: '190', protein: '7', carb: '7', fat: '16'),
        );

      await form.save();

      final asked = repo.savedForms.single;
      // The serving is a measure on the row, named so the reading posture can
      // print the label's own line back — and it states no density.
      expect(asked.serving!.label, 'serving · 2 tbsp');
      expect(asked.serving!.amount, closeTo(2 * 14.78676478125, 1e-9));
      expect(asked.measuresAdded, isEmpty);
      expect(asked.density, isA<DensityUnchanged>());
      // And what is stored is per 100 of the basis, not what the label printed.
      expect(
        asked.row.macros!.kcal,
        closeTo(190 / (2 * 14.78676478125) * 100, 1e-9),
      );
      expect(asked.row.macrosBasis, MacrosBasis.perMl);
    });

    test('a second Save does not write the draft twice', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      await form.addAlias('mangoes');
      form.draftDensity(0.66);

      await form.save();
      await form.save();

      expect(repo.savedForms.first.aliasesAdded, hasLength(1));
      expect(repo.savedForms.last.aliasesAdded, isEmpty);
      expect(repo.savedForms.last.density, isA<DensityUnchanged>());
    });

    test('the three refusals write nothing and say why', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, :at) = await _open(repo, id: 'mango');
      form.setName('   ');

      expect(await form.save(), isNull);
      expect(at().message, contains('A name is the one'));

      form
        ..setName('Mango')
        ..setMacros(const MacroDraft(kcal: '60'));
      expect(await form.save(), isNull);
      expect(at().message, contains('all four macros'));

      // Per-serving mode clears the four, so the refusal is about figures
      // typed IN the mode with no serving under them.
      form
        ..setPerServing()
        ..setMacros(
          const MacroDraft(kcal: '30', protein: '1', carb: '7', fat: '0'),
        );
      expect(await form.save(), isNull);
      expect(at().message, contains('One serving is how'));

      expect(repo.savedForms, isEmpty);
    });

    test('the piece weight rides the same one call, as a PieceWeightSet the '
        'repository lands beside the admission set', () async {
      final repo = FakeIngredientRepo([_unweighedMango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      form.draftPieceWeight(350);

      final saved = await form.save();

      expect(saved, isNotNull);
      final asked = repo.savedForms.single;
      expect(asked.pieceWeight, isA<PieceWeightSet>());
      expect((asked.pieceWeight as PieceWeightSet).amount, 350);
      // The draft already applied the unlock, so the list travels with it.
      expect(asked.row.allowedUnits, contains(pieces));
      expect(repo.rows.single.pieceBasisAmount, 350);
      expect(repo.rows.single.pieceSource, 'manual');
    });

    test('removing it sends a PieceWeightCleared, and `piece` leaves the '
        'admission set in the same write', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      // The row is left counted deliberately: what Save refuses is a piece
      // DEFAULT with no weight, so the default moves with the number.
      form
        ..removePieceWeight()
        ..setDefaultUnit(g);

      await form.save();

      final asked = repo.savedForms.single;
      expect(asked.pieceWeight, isA<PieceWeightCleared>());
      expect(asked.row.allowedUnits, isNot(contains(pieces)));
      expect(repo.rows.single.pieceBasisAmount, isNull);
      expect(repo.rows.single.pieceSource, isNull);
    });

    test('SAVE REFUSES a piece default with nothing weighing one, and names '
        'both ways out', () async {
      final repo = FakeIngredientRepo([_unweighedMango]);
      final (:form, :at) = await _open(repo, id: 'mango');

      expect(await form.save(), isNull);
      expect(
        at().message,
        'Piece can’t be the default unit with nothing weighing one — '
        'enter what one weighs below, or make it g.',
      );
      expect(repo.savedForms, isEmpty);

      // Either fix clears it: the number…
      form.draftPieceWeight(350);
      expect(await form.save(), isNotNull);
    });

    test('…or the other way out: a default that is not a count needs no '
        'weight at all', () async {
      final repo = FakeIngredientRepo([_unweighedMango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      form.setDefaultUnit(g);

      expect(await form.save(), isNotNull);
      expect(repo.savedForms.single.pieceWeight, isA<PieceWeightUnchanged>());
    });

    test('a create passes a NULL id, so the row and its children land in one '
        'transaction', () async {
      final repo = FakeIngredientRepo(const []);
      final (:form, at: _) = await _open(repo, initialName: 'Curry leaves');
      form.setCategory('produce');
      await form.addAlias('kadi patta');

      final saved = await form.save();

      expect(saved!.canonicalName, 'Curry Leaves');
      expect(repo.rows.single.id, saved.id);
      expect(repo.savedForms.single.aliasesAdded.single.text, 'kadi patta');
    });
  });

  group('a new row states its category', () {
    test('the create form refuses until one is picked, and says which '
        'question it is asking', () async {
      final repo = FakeIngredientRepo(const []);
      final (:form, :at) = await _open(repo, initialName: 'Curry leaves');
      form.setMacros(
        const MacroDraft(kcal: '108', protein: '6', carb: '19', fat: '1'),
      );

      expect(at().refusal, startsWith('Which aisle is it in?'));
      expect(at().completable, isFalse);
      expect(await form.save(), isNull);
      expect(repo.savedForms, isEmpty);

      form.setCategory('produce');

      expect(at().refusal, isNull);
      expect(at().completable, isTrue);
      expect(await form.save(), isNotNull);
      expect(repo.rows.single.category, 'produce');
    });

    test('whitespace is not a category', () async {
      final repo = FakeIngredientRepo(const []);
      final (:form, :at) = await _open(repo, initialName: 'Curry leaves');
      form.setCategory('   ');

      expect(at().refusal, startsWith('Which aisle is it in?'));
    });

    // The rows already here that never named one are not a backlog to be
    // cleared through this form: an edit about the macros must still be
    // puttable down.
    test('a row that already exists without one is still saveable', () async {
      const uncategorised = Ingredient(
        id: 'bare',
        canonicalName: 'Cheddar Shreds',
        defaultUnit: g,
        status: IngredientStatus.stub,
        source: 'manual',
      );
      final repo = FakeIngredientRepo(const [uncategorised]);
      final (:form, :at) = await _open(repo, id: 'bare');

      expect(at().category, '');
      expect(at().refusal, isNull);
      expect(await form.save(), isNotNull);
      expect(repo.savedForms.single.row.category, isNull);
    });
  });

  group('which mode a scan lands the macros section in', () {
    /// The cheddar shreds' shape: a per-100 panel, the serving the label
    /// printed beside it, and that serving's own four figures.
    const per100 = Macros(
      kcal: 285.714285714286,
      protein: 0,
      carb: 21.4285714285714,
      fat: 25,
      fiber: 0,
    );
    const perServing = Macros(kcal: 80, protein: 0, carb: 6, fat: 7, fiber: 0);

    IngredientDraft scan({DraftServing? serving}) => IngredientDraft(
      suggestedName: 'Cheddar shreds',
      source: DraftSource.barcode,
      barcode: '0099482514778',
      macros: per100,
      serving: serving,
    );

    test('a serving AND the figures printed for it: the label’s numbers go in '
        'the fields, and per 100 becomes the derivation', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(
        scan(
          serving: const DraftServing(
            amount: 28,
            unit: g,
            printedText: '0.25 cup (28 g)',
            printed: perServing,
          ),
        ),
      );

      final draft = at();
      expect(draft.perServing, isTrue);
      expect(draft.basis, MacrosBasis.perG);
      expect(draft.macros, MacroDraft.from(perServing));
      expect(draft.serving.amountText, '28');
      expect(draft.serving.unit, g);
      // Stored is still per 100, derived through the serving in front of the
      // person.
      expect(draft.storedMacros!.kcal, closeTo(285.7142857, 1e-6));
      // And the pack's own per-100 column is kept, so leaving the mode with
      // nothing typed puts the label's other reading back.
      expect(draft.per100Macros, MacroDraft.from(per100));
      expect(draft.scannedPer100NeedsServingHint, isFalse);
    });

    test('a serving with no figures of its own leaves the row per 100 — there '
        'is no second reading to enter it in', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(
        scan(
          serving: const DraftServing(
            amount: 28,
            unit: g,
            printedText: '0.25 cup (28 g)',
          ),
        ),
      );

      final draft = at();
      expect(draft.perServing, isFalse);
      expect(draft.macros, MacroDraft.from(per100));
      expect(draft.serving.amountText, '28');
      // The row already states a serving, so nothing points at the mode.
      expect(draft.scannedPer100NeedsServingHint, isFalse);
    });

    test('figures with no serving at all stay per 100, and the nudge says the '
        'mode is there', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(scan());

      final draft = at();
      expect(draft.perServing, isFalse);
      expect(draft.macros, MacroDraft.from(per100));
      expect(draft.serving.amount, isNull);
      expect(draft.scannedPer100NeedsServingHint, isTrue);
    });
  });

  // "2 tbsp (7 g)" is a serving AND a density: one spoonful, weighed. Only
  // the reading the basis is in can be the row's serving measure, so the
  // other half survives in the pack's own line and the density sentence is
  // offered the pair.
  group('a printed serving line that weighs its own spoon', () {
    const yeastPer100 = Macros(
      kcal: 385.7,
      protein: 50,
      carb: 35.7,
      fat: 5,
      fiber: 20,
    );

    test('the density sentence is offered both halves — the spoon it says '
        'and the weight it brackets', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(
        const IngredientDraft(
          suggestedName: 'Nutritional Yeast Seasoning',
          source: DraftSource.barcode,
          barcode: '0790011110019',
          macros: yeastPer100,
          serving: DraftServing(
            amount: 7,
            unit: g,
            printedText: '2 tbsp (7 g)',
          ),
        ),
      );

      // The row's serving is the gram half — the only one a per-100 g row can
      // denominate — and the spoon is not lost with it.
      expect(at().serving.amountText, '7');
      expect(at().serving.unit, g);
      final offer = at().densityPrefill!;
      expect(offer, (amount: 2.0, unit: tbsp, grams: 7.0));
      // 7 g per 2 tbsp is 0.237 g/ml — what the sentence will read once it is
      // tapped. NOTHING has written it: the offer is an offer (ADR-0008 §2,
      // ADR-0011), and the draft still says the row has no density.
      expect(offer.grams! / (2 * 14.78676478125), closeTo(0.237, 5e-4));
      expect(at().densityValue, isNull);
      expect(at().density, isA<DensityUnchanged>());
    });

    test('a per-SERVING panel keeps the pack’s line too — it is the same '
        'spoonful, said in the mode the label printed', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(
        const IngredientDraft(
          suggestedName: 'Peanut Butter',
          source: DraftSource.barcode,
          barcode: '0851087000250',
          macrosGap: DraftMacrosGap.perServingPanel,
          servingPanel: DraftServingPanel(
            printed: Macros(kcal: 180, protein: 6, carb: 10, fat: 14),
            servingAmount: 32,
            servingBasis: MacrosBasis.perG,
            servingSize: '2 Tbsp (32 g)',
          ),
        ),
      );

      expect(at().serving.packPrintedText, '2 Tbsp (32 g)');
      expect(at().densityPrefill, (amount: 2.0, unit: tbsp, grams: 32.0));
    });

    test('a mass serving with no spoon anywhere offers nothing — what a gram '
        'weighs is not a fact', () async {
      final repo = FakeIngredientRepo([_bareStub]);
      final (:form, :at) = await _open(repo, id: 'bare');

      form.applyScan(
        const IngredientDraft(
          suggestedName: 'Cheddar shreds',
          source: DraftSource.barcode,
          barcode: '0099482514778',
          macros: Macros(kcal: 285.7, protein: 0, carb: 21.4, fat: 25),
          serving: DraftServing(amount: 28, unit: g, printedText: '28 g'),
        ),
      );

      expect(at().serving.amountText, '28');
      expect(at().densityPrefill, isNull);
    });
  });

  // The household's names and aliases are ONE namespace: the draft answers
  // "is this name taken" before the tap, and the same question is asked again
  // inside the write's transaction.
  group('the name namespace gates the form', () {
    const sauerkraut = Ingredient(
      id: 'kraut',
      canonicalName: 'Sauerkraut',
      defaultUnit: g,
      status: IngredientStatus.complete,
      macros: Macros(kcal: 19, protein: 1, carb: 4, fat: 0),
    );

    test('leaving the field on a taken name refuses the form and names the '
        'row that has it', () async {
      final repo = FakeIngredientRepo([sauerkraut]);
      final (:form, :at) = await _open(repo, initialName: 'sauerkraut');

      await form.leaveNameField();

      expect(at().nameCollision!.ingredientId, 'kraut');
      expect(at().refusal, 'Already an ingredient: Sauerkraut');
      expect(
        at().completable,
        isFalse,
        reason: 'the gate the dock reads has to hold this too',
      );
    });

    test('typing again clears the note — it was an answer about the old '
        'text', () async {
      final repo = FakeIngredientRepo([sauerkraut]);
      final (:form, :at) = await _open(repo, initialName: 'sauerkraut');
      form.setCategory('pantry');
      await form.leaveNameField();

      form.setName('Sauerkraut Juice');

      expect(at().nameCollision, isNull);
      expect(at().refusal, isNull);
    });

    test('a row may always be saved under the name it already has', () async {
      final repo = FakeIngredientRepo([sauerkraut]);
      final (:form, :at) = await _open(repo, id: 'kraut');

      await form.leaveNameField();

      expect(at().nameCollision, isNull);
    });

    test('an ALIAS is refused on the same namespace, and is not taken into '
        'the draft', () async {
      final repo = FakeIngredientRepo([sauerkraut, _mango]);
      final (:form, :at) = await _open(repo, id: 'mango');

      final taken = await form.addAlias('sauerkraut');

      expect(taken!.ingredientName, 'Sauerkraut');
      expect(at().aliasesAdded, isEmpty);
    });

    test('the WRITE refuses too, and the refusal comes back with the row it '
        'names', () async {
      final repo = FakeIngredientRepo([sauerkraut]);
      final (:form, :at) = await _open(repo, initialName: 'Sauerkraut');
      // Straight to Save, without leaving the field — the backstop path.
      form
        ..setCategory('pantry')
        ..setName('Sauerkraut')
        ..setMacros(
          const MacroDraft(kcal: '19', protein: '1', carb: '4', fat: '0'),
        );

      final saved = await form.save(markComplete: true);

      expect(saved, isNull);
      expect(repo.rows, hasLength(1), reason: 'nothing was written');
      expect(at().message, 'Already an ingredient: Sauerkraut');
      expect(at().nameCollision!.ingredientId, 'kraut');
    });
  });

  test('a delete refused by a live line is a message, not a failure', () async {
    final repo = FakeIngredientRepo(
      [_mango],
      references: {'mango': (recipeCount: 3, lineCount: 4)},
    );
    final (:form, :at) = await _open(repo, id: 'mango');

    final outcome = await form.delete();

    expect(outcome, isA<DeleteRefused>());
    expect(
      at().message,
      'Still used by 3 recipes (4 lines). Change those lines first.',
    );
    expect(repo.rows, hasLength(1));
  });
}
