/// **The household's ingredient names and its aliases are ONE namespace**,
/// keyed by `match_text` — PURE DART (invariant 2).
///
/// The seed's generator already holds this rule (`planSeed` in
/// `supabase/seed/scripts/gen_seed.ts` refuses a vocabulary where two rows, or
/// a row and another row's alias, normalize to the same text), and the import
/// cascade's exact tier already reads names and aliases as one surface. What
/// was missing was the phone: the flesh-out form would happily save a second
/// **Sauerkraut** beside the first, and from then on every exact match was a
/// coin toss between two rows.
///
/// Two questions live here, and both are asked of the same list of [NameEntry]
/// so they cannot disagree about what the namespace holds:
///
/// * [collisionIn] — is this text *already* a name here? An exact answer,
///   over normalized match text, and the one a save is refused on.
/// * [nearMatchesIn] — is it nearly one? [searchRank]'s guarded typo tier,
///   offered under the pickers' `DID YOU MEAN` band and never acted on
///   unattended (ADR-0004).
library;

import 'package:meta/meta.dart';

import '../../../core/search/search_rank.dart';
import 'normalize.dart';

/// What the form's note and the write's refusal both open with — one sentence
/// in two places would be two sentences by the second edit.
///
/// The name after it is a **door** where a widget draws it, so the prefix is
/// exported on its own as well as inside [nameTakenMessage].
const kNameTakenPrefix = 'Already an ingredient: ';

/// The refusal in words: `Already an ingredient: Sauerkraut`.
String nameTakenMessage(String existingName) =>
    '$kNameTakenPrefix$existingName';

/// One name in the namespace: a row's own canonical name, or one of its live
/// aliases.
///
/// [ingredientName] is the row's canonical name whichever this is, because it
/// is what a person is sent to — "already an alias of Sauerkraut" names the
/// row, not the alias.
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

/// The live entry [text] would land on top of, or null when the name is free.
///
/// Exact over [normalizeMatchText], because that is what the namespace is
/// keyed by: "Sauerkraut", "sauerkraut " and "Sauer-Kraut" are one name here,
/// and an alias counts exactly as much as a canonical name does.
///
/// [selfId] is the row being edited, and its own entries are skipped — a row
/// may always be saved under the name it already has, and re-saving a row
/// whose alias matches its own name is not a duplicate of anything.
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

/// Up to [limit] rows whose name or alias [text] was very nearly spelled —
/// one per row, best first, and **empty unless the typo tier answered**.
///
/// The band rule the pickers hold, applied to a name being typed: a guess is
/// the whole list or it is absent ([bestTier]). A word-prefix hit is a
/// spelling, not a guess — "Onion" beside the household's "Onion Powder" is
/// two ingredients, and interrupting it with `DID YOU MEAN` would make the
/// band mean nothing where it matters.
///
/// Rows collapse to one entry each: a row matched through both its name and an
/// alias is still one row to go and look at.
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
