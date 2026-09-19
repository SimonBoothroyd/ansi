/// Authoring a recipe measure's WORD and its number — PURE DART (invariant 2),
/// the sub-recipe twin of `features/ingredients/domain/measure_authoring.dart`.
///
/// A recipe measure is authored at two doors — the recipe editor's MEASURES
/// list under MAKES, and the ＋ on a component's quantity dock — and they are
/// the same act, so the label is read the same way at both. It is read by
/// exactly the rule an ingredient measure's is ([measureLabelAsAuthored]:
/// trim, collapse inner whitespace, leave the case alone), because a household
/// that writes `Blob` on one row and `blob` on another has written one word
/// twice, and a silent case change is the kind of edit that makes a person
/// doubt what else was changed.
///
/// One refusal is this side's own: **a word that merely names a unit is not a
/// word.** `cup`, `g`, `batch` are already on the chip row, and a measure that
/// duplicates one is one thing with two words on one row — which is what
/// ADR-0016 was written to stop. The lookup is the catalog's own
/// ([unitFromLabel], `batch` included), never a hand list.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart' show measureLabelAsAuthored;
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_words.dart';

/// One row as a reader hands it in: the measure, and the raw `created_at` text
/// the database stored. [mergeRecipeMeasures] needs the second to decide which
/// of two rows saying one word is the canonical one.
typedef RecipeMeasureRow = ({RecipeMeasure measure, Object? createdAt});

/// The live measure of this recipe that already carries [label], ignoring
/// case, or null.
///
/// Case-insensitive on purpose, and looser than [mergeRecipeMeasures]: that
/// one hides exactly what the database let through, and this one refuses what
/// a PERSON would read as the same word. A recipe offering both `blob` and
/// `Blob` in its chip row is two ways to say one thing.
///
/// [measures] is read in its given order, which is `sort_order`, so two rows
/// that are already duplicates resolve to the same one on every device.
RecipeMeasure? recipeMeasureAlreadyNamed(
  String label,
  List<RecipeMeasure> measures,
) {
  final word = measureLabelAsAuthored(label).toLowerCase();
  if (word.isEmpty) return null;
  for (final m in measures) {
    if (measureLabelAsAuthored(m.label).toLowerCase() == word) return m;
  }
  return null;
}

/// A recipe's rows as every reader sees them: duplicates merged, the oldest of
/// each word kept, ordered `sort_order` then age then id.
///
/// The offline-dupe doctrine, mirrored from the ingredient measures verbatim —
/// including its case rule. No unique index guards `(recipe_id, label)`,
/// because two phones offline can both coin `blob` and neither write is wrong;
/// so the duplicate is **hidden on read** rather than refused on write, and
/// every device hides the same one. The key is the label EXACTLY as stored:
/// `Blob` and `blob` are two rows here, and it is [recipeMeasureAlreadyNamed]
/// on the authoring path — not this — that stops a person minting the pair.
///
/// The creation key is the parsed instant re-serialized canonically (UTC
/// ISO-8601), falling back to the raw text for an unparseable value:
/// `created_at` is TEXT and its format differs by writer — this client writes
/// `…T…Z`, Postgres-sourced rows sync as `… …Z` — and a bare lexicographic
/// compare across formats picks the wrong "oldest" (a space sorts before `T`).
/// A value with no zone marker at all is read as UTC, or two devices in
/// different zones would disagree about which row is older.
List<RecipeMeasure> mergeRecipeMeasures(Iterable<RecipeMeasureRow> rows) {
  final ordered =
      [
        for (final r in rows)
          (measure: r.measure, created: _createdKey(r.createdAt)),
      ]..sort((a, b) {
        final byCreated = a.created.compareTo(b.created);
        return byCreated != 0
            ? byCreated
            : a.measure.id.compareTo(b.measure.id);
      });

  final byLabel = <String, ({RecipeMeasure measure, String created})>{};
  for (final e in ordered) {
    byLabel.putIfAbsent(e.measure.label, () => e); // newer dupe hidden
  }
  final kept = byLabel.values.toList()
    ..sort((a, b) {
      final bySort = a.measure.sortOrder.compareTo(b.measure.sortOrder);
      if (bySort != 0) return bySort;
      final byCreated = a.created.compareTo(b.created);
      return byCreated != 0 ? byCreated : a.measure.id.compareTo(b.measure.id);
    });
  return [for (final e in kept) e.measure];
}

String _createdKey(Object? raw) {
  final s = raw as String? ?? '';
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return s;
  final utc = parsed.isUtc
      ? parsed
      : DateTime.tryParse('${s.trim()}Z') ?? parsed.toUtc();
  return utc.toIso8601String();
}

/// [label] and [perBatch] as a [RecipeMeasure] the recipe can carry, or the
/// refusal a form prints.
///
/// [id] is the row this states — a fresh uuid for a new word, or the existing
/// row's id when the household is **re-stating** it (the board's rule: the row
/// keeps its id, so `blob` moving from 20 to 24 follows through to every line
/// already saying it). A row re-stating itself is never its own duplicate.
///
/// [measures] are the recipe's live ones, for the duplicate check. Failures:
///
/// - `recipe_measure/no_label` — nothing was typed;
/// - `recipe_measure/unit_word` — the word merely names a catalog unit;
/// - `recipe_measure/word_taken` — this recipe already says it;
/// - `recipe_measure/per_batch` — the number is missing, zero or negative.
Result<RecipeMeasure> authorRecipeMeasure({
  required String id,
  required String recipeId,
  required String label,
  required double? perBatch,
  List<RecipeMeasure> measures = const [],
  int sortOrder = 0,
}) {
  final word = measureLabelAsAuthored(label);
  if (word.isEmpty) {
    return const Err(
      Failure(
        'recipe_measure/no_label',
        'Give it a word — what you call one of these.',
      ),
    );
  }
  final unit = unitFromLabel(word) ?? unitFromWord(word);
  if (unit != null) {
    return Err(
      Failure('recipe_measure/unit_word', recipeMeasureUnitWordRefusal(word)),
    );
  }
  final taken = recipeMeasureAlreadyNamed(word, measures);
  if (taken != null && taken.id != id) {
    return Err(
      Failure(
        'recipe_measure/word_taken',
        recipeMeasureWordTakenRefusal(taken),
      ),
    );
  }
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (perBatch == null || !perBatch.isFinite || !(perBatch > 0)) {
    return Err(
      Failure('recipe_measure/per_batch', recipeMeasurePerBatchRefusal(word)),
    );
  }
  return Ok(
    RecipeMeasure(
      id: id,
      recipeId: recipeId,
      label: word,
      perBatch: perBatch,
      sortOrder: sortOrder,
    ),
  );
}

/// Why a word that is a unit's name cannot be minted. It names the way out,
/// which is a real one: the words a measure exists for are the ones the
/// catalog has not got.
String recipeMeasureUnitWordRefusal(String label) =>
    '“$label” is already a unit — the chip row says it on every recipe. A '
    'measure is for the word the units have not got, like “blob” or “ladle”.';

/// Why a word cannot be minted twice: the recipe already says it.
///
/// The way out is a re-statement rather than a second row, because the row
/// keeps its id and every line already saying the word follows the number.
String recipeMeasureWordTakenRefusal(RecipeMeasure taken) =>
    '“${taken.label}” is already this recipe’s word, at '
    '${formatAmount(taken.perBatch)} a batch. Re-state that one and every '
    'line saying it follows.';

/// Why a measure cannot be minted without its number.
String recipeMeasurePerBatchRefusal(String label) =>
    'Say how many “$label” a batch makes — a number above zero.';
