/// The household's ingredient names and aliases are one namespace, keyed by
/// `match_text`. Pure Dart.
///
/// The seed generator (`planSeed` in `supabase/seed/scripts/gen_seed.ts`) and
/// the import cascade's exact tier hold the same rule. Two questions are asked
/// of one list of [NameEntry]:
///
/// - [collisionIn]: is this text already a name here? Exact, over normalized
///   match text; a save is refused on it.
/// - [nearMatchesIn]: is it nearly one? [searchRank]'s guarded typo tier,
///   offered and never acted on unattended (ADR-0004).
library;

import 'package:meta/meta.dart';

import '../../../core/search/search_rank.dart';
import 'normalize.dart';

/// What the form's note and the write's refusal both open with. Exported apart
/// from [nameTakenMessage] because a widget draws the name after it as a link.
const kNameTakenPrefix = 'Already an ingredient: ';

/// The refusal in words: `Already an ingredient: Sauerkraut`.
String nameTakenMessage(String existingName) =>
    '$kNameTakenPrefix$existingName';

/// One name in the namespace: a row's canonical name or one of its live
/// aliases. [ingredientName] is always the row's canonical name, which is where
/// a person is sent.
@immutable
class NameEntry {
  const NameEntry({
    required this.ingredientId,
    required this.ingredientName,
    required this.text,
    required this.matchText,
    this.isAlias = false,
  });

  /// The row this name belongs to.
  final String ingredientId;

  /// That row's canonical name — what a refusal says out loud and what the
  /// door onto the row is labelled with.
  final String ingredientName;

  /// This name as it is written: the canonical name, or the alias text.
  final String text;

  /// The stored `match_text` — the namespace's key.
  final String matchText;

  final bool isAlias;

  @override
  bool operator ==(Object other) =>
      other is NameEntry &&
      other.ingredientId == ingredientId &&
      other.ingredientName == ingredientName &&
      other.text == text &&
      other.matchText == matchText &&
      other.isAlias == isAlias;

  @override
  int get hashCode =>
      Object.hash(ingredientId, ingredientName, text, matchText, isAlias);

  @override
  String toString() =>
      'NameEntry($ingredientName${isAlias ? ' alias' : ''}: $matchText)';
}

/// The live entry [text] would collide with, or null when the name is free.
/// Exact over [normalizeMatchText], and an alias counts as much as a canonical
/// name. [selfId] is the row being edited; its own entries are skipped.
NameEntry? collisionIn(
  String text,
  Iterable<NameEntry> entries, {
  String? selfId,
}) {
  final matchText = normalizeMatchText(text);
  if (matchText.isEmpty) return null;
  for (final entry in entries) {
    if (entry.ingredientId == selfId) continue;
    if (entry.matchText == matchText) return entry;
  }
  return null;
}

/// Up to [limit] rows whose name or alias [text] nearly spells, one per row,
/// best first. Empty unless the typo tier answered ([bestTier]): a word-prefix
/// hit is a spelling, not a guess, so "Onion" beside "Onion Powder" raises
/// nothing.
List<NameEntry> nearMatchesIn(
  String text,
  Iterable<NameEntry> entries, {
  String? selfId,
  int limit = 3,
}) {
  final scored = <({NameEntry entry, SearchHit hit})>[];
  for (final entry in entries) {
    if (entry.ingredientId == selfId) continue;
    final hit = searchRank(
      text,
      {entry.matchText, ...nameSurfaces(entry.text)}.toList(),
    );
    if (hit != null) scored.add((entry: entry, hit: hit));
  }
  if (bestTier(scored.map((s) => s.hit)) != SearchTier.typo) return const [];

  final guesses =
      [
        for (final s in scored)
          if (s.hit.tier == SearchTier.typo) s,
      ]..sort((a, b) {
        final byScore = b.hit.score.compareTo(a.hit.score);
        if (byScore != 0) return byScore;
        return a.entry.ingredientName.length.compareTo(
          b.entry.ingredientName.length,
        );
      });

  final seen = <String>{};
  final best = <NameEntry>[];
  for (final s in guesses) {
    if (!seen.add(s.entry.ingredientId)) continue;
    best.add(s.entry);
    if (best.length == limit) break;
  }
  return best;
}
