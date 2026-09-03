/// Probe-and-apply (plan 0020 **D7b**) and its offline contract.
///
/// The rules worth pinning are the ones that make the local apply and the
/// server trigger safe to race: bare stubs only, NULL fields only, the row
/// stays a stub, and every failure — no candidate, no connection, no backend
/// — is the same quiet "nothing came back" rather than an error.
library;

import 'package:ansi/core/units/macros.dart';
import 'package:ansi/core/units/units.dart';
import 'package:ansi/features/ingredients/data/usda_enrichment.dart';
import 'package:ansi/features/ingredients/data/usda_probe_impl.dart';
import 'package:ansi/features/ingredients/domain/ingredient.dart';
import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/usda_probe.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_ingredient_repository.dart';

const _candidate = UsdaCandidate(
  fdcId: 11216,
  description: 'Curry leaves, raw',
  source: 'usda_fdc:11216',
  score: 0.71,
  densityGPerMl: 0.35,
  macros: Macros(kcal: 108, protein: 6, carb: 19, fat: 1),
);

/// Records what it was asked, so the F1 flush can be proven to have happened
/// before the question (the probe must see the NEW name).
class _FakeProbe extends UsdaProbe {
  _FakeProbe([this.answer]);

  final UsdaCandidate? answer;
  final asked = <String>[];

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async {
    asked.add(matchText);
    return [?answer];
  }
}

/// A probe that cannot reach the server. Its whole contract is that it
/// answers nothing rather than throwing — see `SupabaseUsdaProbe`.
class _OfflineProbe extends UsdaProbe {
  const _OfflineProbe();

  @override
  Future<List<UsdaCandidate>> search(String matchText, {int limit = 5}) async =>
      const [];
}

const _bareStub = Ingredient(
  id: 'curry',
  canonicalName: 'Curry leaves, fresh',
  defaultUnit: g,
  status: IngredientStatus.stub,
  source: 'manual',
);

void main() {
  group('enrichFromUsda', () {
    test('a bare stub is filled in, stamped, and STAYS a stub (D5)', () async {
      final repo = FakeIngredientRepo(const [_bareStub]);
      final probe = _FakeProbe(_candidate);

      final result = await enrichFromUsda(
        _bareStub,
        probe: probe,
        repository: repo,
      );

      expect(result.outcome, UsdaEnrichment.applied);
      final row = (await repo.byId('curry'))!;
      expect(row.densityGPerMl, 0.35);
      expect(row.macros, const Macros(kcal: 108, protein: 6, carb: 19, fat: 1));
      expect(row.source, 'usda_fdc:11216');
      // U-D1: the match is NAMED beside its stamp, with the score that earned
      // it, so the form can say which food this was — offline.
      expect(row.sourceLabel, 'Curry leaves, raw');
      expect(row.sourceScore, 0.71);
      // A trigram guess never completes an ingredient.
      expect(row.status, IngredientStatus.stub);
    });

    test('U-D2: a DECLINED row is not even asked about — a person said no, '
        'and an automatic probe does not argue', () async {
      final declined = _bareStub.copyWith(
        source: usdaDeclinedSource,
        sourceLabel: 'Curry leaves, raw',
      );
      final repo = FakeIngredientRepo([declined]);
      final probe = _FakeProbe(_candidate);

      final result = await enrichFromUsda(
        declined,
        probe: probe,
        repository: repo,
      );

      expect(result.outcome, UsdaEnrichment.declined);
      expect(probe.asked, isEmpty);
      final row = (await repo.byId('curry'))!;
      expect(row.source, usdaDeclinedSource);
      expect(row.macros, isNull);
      // The refused name survives: the form says WHICH food was declined.
      expect(row.sourceLabel, 'Curry leaves, raw');
    });

    test('it asks under the row’s MATCH TEXT, not its display name — the same '
        'question the server trigger asks', () async {
      final probe = _FakeProbe(_candidate);
      await enrichFromUsda(
        _bareStub,
        probe: probe,
        repository: FakeIngredientRepo(const [_bareStub]),
      );
      expect(probe.asked.single, normalizeMatchText('Curry leaves, fresh'));
      // …which is emphatically not the display name.
      expect(probe.asked.single, isNot('Curry leaves, fresh'));
    });

    test('a row with numbers is never re-probed — not even asked', () async {
      const filled = Ingredient(
        id: 'curry',
        canonicalName: 'Curry leaves, fresh',
        defaultUnit: g,
        status: IngredientStatus.stub,
        macros: Macros(kcal: 1, protein: 2, carb: 3, fat: 4),
      );
      final probe = _FakeProbe(_candidate);
      final repo = FakeIngredientRepo(const [filled]);

      final result = await enrichFromUsda(
        filled,
        probe: probe,
        repository: repo,
      );

      expect(result.outcome, UsdaEnrichment.notBare);
      expect(probe.asked, isEmpty); // no round trip spent on a lost cause
      expect((await repo.byId('curry'))!.macros!.kcal, 1); // untouched
    });

    test('a complete row is refused too', () async {
      const complete = Ingredient(
        id: 'mango',
        canonicalName: 'Mango',
        defaultUnit: pieces,
        status: IngredientStatus.complete,
      );
      final result = await enrichFromUsda(
        complete,
        probe: _FakeProbe(_candidate),
        repository: FakeIngredientRepo(const [complete]),
      );
      expect(result.outcome, UsdaEnrichment.notBare);
    });

    test('offline degrades to noAnswer — the row is untouched and nothing '
        'throws', () async {
      final repo = FakeIngredientRepo(const [_bareStub]);
      final result = await enrichFromUsda(
        _bareStub,
        probe: const _OfflineProbe(),
        repository: repo,
      );
      expect(result.outcome, UsdaEnrichment.noAnswer);
      final row = (await repo.byId('curry'))!;
      expect(row.densityGPerMl, isNull);
      expect(row.macros, isNull);
      expect(row.source, 'manual'); // provenance not churned
    });

    test('a candidate with nothing to copy writes nothing — a name match is '
        'not a prefill', () async {
      const empty = UsdaCandidate(
        fdcId: 1,
        description: 'Nameless',
        source: 'usda_fdc:1',
        score: 0.9,
      );
      final repo = FakeIngredientRepo(const [_bareStub]);
      final result = await enrichFromUsda(
        _bareStub,
        probe: _FakeProbe(empty),
        repository: repo,
      );
      expect(result.outcome, UsdaEnrichment.nothingToCopy);
      expect((await repo.byId('curry'))!.source, 'manual');
    });

    test('THE RACE: applying twice is idempotent — the second pass finds a '
        'row that is no longer bare and declines', () async {
      // The trigger landing first, then the app (or the other way round).
      // Both fill nulls only, both read the same probe, so the row converges
      // rather than flip-flopping (migration 0016's header).
      final repo = FakeIngredientRepo(const [_bareStub]);
      final probe = _FakeProbe(_candidate);
      final first = await enrichFromUsda(
        _bareStub,
        probe: probe,
        repository: repo,
      );
      final second = await enrichFromUsda(
        first.row!,
        probe: probe,
        repository: repo,
      );

      expect(first.outcome, UsdaEnrichment.applied);
      expect(second.outcome, UsdaEnrichment.notBare);
      final row = (await repo.byId('curry'))!;
      expect(row.densityGPerMl, 0.35);
      expect(row.source, 'usda_fdc:11216');
    });
  });

  group('isBareStub — the Dart mirror of the trigger WHEN clause', () {
    test('a stub with no density and no macros, and nothing else', () {
      expect(isBareStub(_bareStub), isTrue);
      expect(isBareStub(_bareStub.copyWith(densityGPerMl: 1)), isFalse);
      expect(
        isBareStub(
          _bareStub.copyWith(
            macros: const Macros(kcal: 1, protein: 1, carb: 1, fat: 1),
          ),
        ),
        isFalse,
      );
      expect(
        isBareStub(_bareStub.copyWith(status: IngredientStatus.complete)),
        isFalse,
      );
    });
  });

  group('UsdaCandidate.tryParse — the RPC row (migrations 0016 + 0027)', () {
    test('parses the shape 0027 promises', () {
      final c = UsdaCandidate.tryParse({
        'fdc_id': 999000001,
        'description': 'Zzquux Test Reference Food',
        'category': 'produce',
        'density_g_per_ml': 0.75,
        'macros': {'kcal': 100, 'protein': 2, 'carb': 20, 'fat': 1},
        'score': 0.82,
        'source': 'usda_fdc:999000001',
      });
      expect(c!.fdcId, 999000001);
      expect(c.description, 'Zzquux Test Reference Food');
      expect(c.category, 'produce');
      expect(c.densityGPerMl, 0.75);
      expect(c.macros, const Macros(kcal: 100, protein: 2, carb: 20, fat: 1));
      expect(c.source, 'usda_fdc:999000001');
      expect(c.hasSomethingToCopy, isTrue);
    });

    test('a density with no panel is still worth copying', () {
      final c = UsdaCandidate.tryParse({
        'fdc_id': 1,
        'description': 'One',
        'density_g_per_ml': 0.5,
        'macros': null,
        'score': 0.6,
        'source': 'usda_fdc:1',
      });
      expect(c!.macros, isNull);
      expect(c.category, isNull);
      expect(c.hasSomethingToCopy, isTrue);
    });

    test('a PARTIAL panel is no panel — three numbers and a hole never '
        'become macros (invariant 3)', () {
      final c = UsdaCandidate.tryParse({
        'fdc_id': 1,
        'description': 'One',
        'macros': {'kcal': 100, 'protein': 2, 'carb': 20},
        'score': 0.6,
        'source': 'usda_fdc:1',
      });
      expect(c!.macros, isNull);
      expect(c.hasSomethingToCopy, isFalse);
    });

    test('a row missing the fields the migration guarantees is no candidate '
        'at all — a nameless match included, because naming it is the point '
        'of 0027', () {
      expect(UsdaCandidate.tryParse(const {}), isNull);
      expect(UsdaCandidate.tryParse(const {'fdc_id': 1, 'score': 0.6}), isNull);
      // The 0016 shape, before descriptions existed: an older server than
      // this build understands degrades to "nothing came back".
      expect(
        UsdaCandidate.tryParse(const {
          'fdc_id': 1,
          'density_g_per_ml': 0.5,
          'score': 0.6,
          'source': 'usda_fdc:1',
        }),
        isNull,
      );
    });
  });

  group('UsdaBand — the score said in the import’s own two words (U-D1)', () {
    test('0.85 and up is a close match; below it, a guess', () {
      expect(UsdaBand.of(1), UsdaBand.close);
      expect(UsdaBand.of(0.85), UsdaBand.close);
      expect(UsdaBand.of(0.849), UsdaBand.guess);
      expect(UsdaBand.of(0.5), UsdaBand.guess);
      expect(UsdaBand.close.word, 'close match');
      expect(UsdaBand.guess.word, 'a guess');
      expect(_candidate.band, UsdaBand.guess);
    });
  });

  test('probe is search with a limit of one — the two cannot disagree about '
      'what "best" means', () async {
    final probe = _FakeProbe(_candidate);
    expect(await probe.probe('curry leaf'), _candidate);
    expect(await const _OfflineProbe().probe('curry leaf'), isNull);
  });

  test('the unconfigured probe answers exactly like an offline one', () async {
    expect(await const UnconfiguredUsdaProbe().probe('anything'), isNull);
    expect(await const UnconfiguredUsdaProbe().search('anything'), isEmpty);
  });
}
