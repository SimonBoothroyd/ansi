/// `searchRank` alone, over the in-memory corpus in `search_vectors.json`.
///
/// The vectors file is the contract in data form; this suite is the half of it
/// that runs without SQLite. `ingredient_repository_test.dart` runs the same
/// queries through the real database, and `line_target_picker_test.dart` runs
/// the title half through both recipe pickers — three readings of one rule.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ansi/features/ingredients/domain/normalize.dart';
import 'package:ansi/features/ingredients/domain/search_query.dart';
import 'package:ansi/features/ingredients/domain/search_rank.dart';
import 'package:flutter_test/flutter_test.dart';

/// One corpus row, reduced to what the rule actually sees.
typedef _Row = ({String name, List<String> surfaces});

List<_Row> _corpus(List<dynamic> rows) => [
  for (final row in rows.cast<Map<String, dynamic>>())
    _row(
      row['name'] as String,
      ((row['aliases'] as List<dynamic>?) ?? const []).cast<String>(),
    ),
];

/// The surface a vocab row exposes: its `match_text`, each alias's
/// `match_text`, and the character-normalized raw name.
_Row _row(String name, List<String> aliases) => (
  name: name,
  surfaces: [
    normalizeMatchText(name),
    for (final alias in aliases) normalizeMatchText(alias),
    normalizeSearchQuery(name),
  ],
);

/// The corpus ranked for [query] the way every caller ranks it: the best tier
/// wins outright, and only inside that tier does the score order rows.
List<({String name, SearchHit hit})> _ranked(List<_Row> corpus, String query) {
  final hits = <({String name, SearchHit hit})>[];
  for (final row in corpus) {
    final hit = searchRank(query, row.surfaces);
    if (hit != null) hits.add((name: row.name, hit: hit));
  }
  if (hits.isEmpty) return const [];
  final best = hits
      .map((h) => h.hit.tier.index)
      .reduce((a, b) => a < b ? a : b);
  return [
    for (final h in hits)
      if (h.hit.tier.index == best) h,
  ]..sort((a, b) {
    final byScore = b.hit.score.compareTo(a.hit.score);
    if (byScore != 0) return byScore;
    final byLength = a.name.length.compareTo(b.name.length);
    if (byLength != 0) return byLength;
    return a.name.compareTo(b.name);
  });
}

void main() {
  final decoded =
      jsonDecode(
            File(
              'test/features/ingredients/search_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final vocab = _corpus(decoded['vocab'] as List<dynamic>);
  final titles = (decoded['titles'] as List<dynamic>).cast<String>();

  group('shared vectors — the tier of every probe', () {
    for (final v in (decoded['tiers'] as List).cast<Map<String, dynamic>>()) {
      final query = v['q'] as String;
      test('"$query" → ${v['want']} (${v['tier']})', () {
        final got = _ranked(vocab, query);
        expect(got, isNotEmpty, reason: '"$query" found nothing');
        expect(got.first.name, v['want']);
        expect(got.first.hit.tier.name, v['tier']);
      });
    }
  });

  group('shared vectors — recipe titles, through the same rule', () {
    for (final v
        in (decoded['title_tiers'] as List).cast<Map<String, dynamic>>()) {
      final query = v['q'] as String;
      test('"$query" → ${v['want']} (${v['tier']})', () {
        final got = [
          for (final title in titles)
            if (recipeTitleHit(title, query) case final hit?)
              (name: title, hit: hit),
        ]..sort((a, b) => a.hit.tier.index.compareTo(b.hit.tier.index));
        expect(got, isNotEmpty, reason: '"$query" found no title');
        expect(got.first.name, v['want']);
        expect(got.first.hit.tier.name, v['tier']);
      });
    }
  });

  group('shared vectors — the guard refuses', () {
    for (final query in (decoded['refusals'] as List).cast<String>()) {
      test('"$query" returns nothing', () {
        expect(_ranked(vocab, query), isEmpty);
      });
    }
  });

  group('shared vectors — tier 1 answers, so tier 2 never runs', () {
    for (final query in (decoded['tier1_answers'] as List).cast<String>()) {
      test('"$query" is spelled right, not guessed at', () {
        final got = _ranked(vocab, query);
        expect(got, isNotEmpty);
        expect(got.first.hit.tier, isNot(SearchTier.typo));
      });
    }
  });

  group('the searchable surface keeps words the phrase normalizer eats', () {
    for (final v in (decoded['surface'] as List).cast<Map<String, dynamic>>()) {
      final name = v['name'] as String;
      test('"$name"', () {
        // The trap, pinned: the phrase normalizer alone loses "Jars".
        expect(normalizeMatchText(name), v['match_text']);
        for (final query in (v['must_find'] as List).cast<String>()) {
          expect(
            recipeTitleHit(name, query),
            isNotNull,
            reason: '"$query" must still find "$name"',
          );
        }
      });
    }
  });

  group('a guess never outranks a spelling', () {
    test('tier 2 does not run while tier 0 or 1 has anything', () {
      // "onion" is an exact hit AND within one edit of several other rows.
      // Every row it returns is a spelling, never a guess.
      for (final hit in _ranked(vocab, 'onion')) {
        expect(hit.hit.tier, isNot(SearchTier.typo));
      }
      expect(SearchTier.exact.index, lessThan(SearchTier.prefix.index));
      expect(SearchTier.prefix.index, lessThan(SearchTier.typo.index));
    });

    test('a short token beside a spelled one still counts', () {
      // "mlk" alone is under the single-token floor and stays silent; beside a
      // correctly spelled "coconut" it resolves. That is the whole argument
      // for a per-TOKEN guard rather than a per-query one.
      expect(_ranked(vocab, 'mlk'), isEmpty);
      expect(_ranked(vocab, 'coconut mlk').first.name, 'Coconut Milk');
    });
  });

  group('the word-boundary rule the in-memory matcher used to carry', () {
    // Rewritten from `matchesSearchQuery`, which two pickers called and this
    // replaces. The behaviours it pinned are still pinned; what changed is
    // that a miss now falls through to the typo tier instead of stopping.
    const curry = ['weeknight chicken curry'];

    test('hits any word start, not just the leading word', () {
      for (final q in ['chicken', 'week', 'cur']) {
        expect(searchRank(q, curry)?.tier, SearchTier.prefix, reason: q);
      }
    });

    test('never matches mid-word as a SPELLING', () {
      // "hick" and "night" sit inside words, so tiers 0 and 1 refuse them.
      // What they get instead is the typo tier's answer — a guess, labelled
      // as one, or nothing at all. Either way, never a prefix hit.
      for (final q in ['hick', 'night']) {
        expect(searchRank(q, curry)?.tier, isNot(SearchTier.prefix), reason: q);
        expect(searchRank(q, curry)?.tier, isNot(SearchTier.exact), reason: q);
      }
    });

    test('normalizes both sides (hyphens, case, accents)', () {
      const loaf = ['all purpose loaf'];
      expect(searchRank('purpose', loaf)?.tier, SearchTier.prefix);
      expect(searchRank('ALL PURPOSE', loaf)?.tier, SearchTier.prefix);
      expect(recipeTitleHit('All-Purpose Loaf', 'all-purpose'), isNotNull);
    });

    test('an empty or punctuation-only query hits nothing at all', () {
      // It used to answer "everything"; the callers now own that decision, so
      // a browse is never confused with a search that matched the world.
      expect(searchRank('', curry), isNull);
      expect(searchRank('  --  ', curry), isNull);
    });
  });

  group('osaDistance — a transposition is one edit, not two', () {
    test('adjacent swaps', () {
      expect(osaDistance('suace', 'sauce'), 1);
      expect(osaDistance('parsely', 'parsley'), 1);
      expect(osaDistance('teh', 'the'), 1);
    });

    test('the ordinary edits still cost one each', () {
      expect(osaDistance('almnd', 'almond'), 1); // insertion
      expect(osaDistance('onionn', 'onion'), 1); // deletion
      expect(osaDistance('anion', 'onion'), 1); // substitution
      expect(osaDistance('onion', 'onion'), 0);
      expect(osaDistance('', 'onion'), 5);
    });
  });

  group('the edit budget is length-relative', () {
    test('nothing under three characters, one to seven, two from eight', () {
      expect(typoEditBudget(2), 0);
      expect(typoEditBudget(3), 1);
      expect(typoEditBudget(7), 1);
      expect(typoEditBudget(8), 2);
    });
  });

  test('an empty query hits nothing (the caller browses instead)', () {
    expect(searchRank('', const ['onion']), isNull);
    expect(searchRank('  --  ', const ['onion']), isNull);
    expect(searchRank('onion', const []), isNull);
  });
}
