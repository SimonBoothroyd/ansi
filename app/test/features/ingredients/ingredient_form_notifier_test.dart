/// The ingredient form's ViewModel, with no widget tree in the way.
///
/// The app's most complex write path used to be reachable only through the UI:
/// thirty pieces of state in one `build()`, and the only way to ask what Save
/// would send was to pump a form and tap it. These ask the notifier directly —
/// what the draft holds after each intent, and what one call hands the
/// repository.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/ingredient_providers.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/ingredient_repository.dart';
import 'package:ansi/features/ingredients/domain/serving_offer.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:ansi/features/ingredients/presentation/ingredient_view_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../helpers/fake_ingredient_repository.dart';

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
}) async {
  final container = ProviderContainer(
    overrides: [ingredientRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  if (id != null) {
    final row = container.listen(ingredientByIdProvider(id), (_, _) {});
    addTearDown(row.close);
    await container.read(ingredientByIdProvider(id).future);
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
      expect(draft.name, 'curry leaves');
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

      form
        ..setServingAmount('50')
        ..setServingName('1 tbsp');
      expect(at().storedMacros!.kcal, 60);
      // And the serving's own second fact is offered, unticked.
      expect(at().offer, isA<DensityOffer>());
      expect(at().servingOfferTaken, isFalse);
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
      form.applyUsdaPick(
        const UsdaCandidate(
          fdcId: 11216,
          description: 'Mango, raw',
          source: 'usda_fdc:11216',
          score: 1,
          densityGPerMl: 0.35,
          macros: Macros(kcal: 60, protein: 1, carb: 15, fat: 0),
        ),
      );

      final draft = at();
      expect(draft.pendingSource, 'usda_fdc:11216');
      expect(draft.pendingSourceLabel, 'Mango, raw');
      expect(draft.macros.kcal, '60');
      expect(draft.densityValue, 0.35);
      expect(repo.savedForms, isEmpty, reason: 'a pick writes nothing');
      expect(repo.rows.single.macros, isNull);
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
        ..draftDensity(0.66)
        ..addAlias('mangoes');
      final measure = form.draftMeasure('whole', 200, sortOrder: 0);

      final saved = await form.save(markComplete: true);

      expect(saved, isNotNull);
      final asked = repo.savedForms.single;
      expect(asked.row.canonicalName, 'Ripe mango');
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

    test('the taken serving offer rides the same write', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      form
        ..setPerServing()
        ..setMacros(
          const MacroDraft(kcal: '30', protein: '1', carb: '7', fat: '0'),
        )
        ..setServingAmount('14')
        ..setServingName('1 tbsp')
        ..takeServingOffer(taken: true);

      await form.save();

      final asked = repo.savedForms.single;
      // A volume-named weight is a density (ADR-0008 §2), so it lands as one —
      // in the same transaction as the macros it came with.
      expect(asked.density, isA<DensitySet>());
      expect(asked.measuresAdded, isEmpty);
      // And what is stored is per 100 of the basis, not what the label printed.
      expect(asked.row.macros!.kcal, closeTo(30 / 14 * 100, 1e-9));
    });

    test('a second Save does not write the draft twice', () async {
      final repo = FakeIngredientRepo([_mango]);
      final (:form, at: _) = await _open(repo, id: 'mango');
      form
        ..addAlias('mangoes')
        ..draftDensity(0.66);

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

      form
        ..setMacros(
          const MacroDraft(kcal: '30', protein: '1', carb: '7', fat: '0'),
        )
        ..setPerServing();
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
      form.addAlias('kadi patta');

      final saved = await form.save();

      expect(saved!.canonicalName, 'Curry leaves');
      expect(repo.rows.single.id, saved.id);
      expect(repo.savedForms.single.aliasesAdded.single.text, 'kadi patta');
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
