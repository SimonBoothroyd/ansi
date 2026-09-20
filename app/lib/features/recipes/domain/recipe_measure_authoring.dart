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
/// Two refusals are this side's own.
///
/// **A word that merely names a unit is not a word.** `cup`, `g`, `batch` are
/// already on the chip row, and a measure that duplicates one is one thing with
/// two words on one row — which is what ADR-0016 was written to stop. The
/// lookup is the catalog's own ([unitFromLabel], `batch` included), never a
/// hand list.
///
/// **And a word can only be coined against a `makes` it can be held to.** A
/// recipe measure is an amount in a unit (ADR-0018), so a `blob` of 15 g says
/// something about a batch only once the recipe says what a batch weighs. That
/// is the honest cost of the owner's ruling — the word works exactly like the
/// measures he already knows, and the price of that is a gate — so this file
/// pays it out loud rather than guessing: [authorRecipeMeasure] refuses while
/// the recipe states no yield at all, and refuses a unit whose FAMILY is not
/// one of the (up to two) the recipe states. Both sentences send the person to
/// MAKES, which is the thing they can actually go and do.
///
/// The same rule read backwards is [recipeMeasuresOrphanedBy]: which live words
/// a `makes` edit would leave standing on nothing, so the recipe editor can
/// warn before the Save rather than let the lines discover it. Read forwards it
/// is [recipeMeasureUnitChoices]: what the authoring form may offer, so a chip
/// row can never hold a unit whose only possible answer is a refusal.
library;

import '../../../core/result/result.dart';
import '../../../core/units/measure.dart' show measureLabelAsAuthored;
import '../../../core/units/number_format.dart';
import '../../../core/units/recipe_measure.dart';
import '../../../core/units/unit_words.dart';
import '../../../core/units/units.dart';
import 'component_math.dart';

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

/// [label], [amount] and [unit] as a [RecipeMeasure] the recipe can carry, or
/// the refusal a form prints.
///
/// [id] is the row this states — a fresh uuid for a new word, or the existing
/// row's id when the household is **re-stating** it (the board's rule: the row
/// keeps its id, so `blob` moving from 15 g to 18 g follows through to every
/// line already saying it). A row re-stating itself is never its own duplicate.
///
/// [yields] are the recipe's stated denominations — what it says a batch makes,
/// in one or two families. They are the gate, not a courtesy: a word is an
/// amount, and an amount says nothing about a batch until the batch has one
/// too.
///
/// [measures] are the recipe's live ones, for the duplicate check. Failures, in
/// the order they are asked:
///
/// - `recipe_measure/no_yield` — the recipe does not say what a batch makes, so
///   no word can be held against it. This is the door's gate: the MEASURES list
///   is drawn disabled with this sentence under it until MAKES is set;
/// - `recipe_measure/no_label` — nothing was typed;
/// - `recipe_measure/unit_word` — the word merely names a catalog unit;
/// - `recipe_measure/word_taken` — this recipe already says it;
/// - `recipe_measure/unit_cannot_measure` — the unit is `batch` (circular: the
///   word exists to reach a batch) or an imprecise word (converts nothing);
/// - `recipe_measure/amount` — the number is missing, zero, negative or NaN;
/// - `recipe_measure/unit_family` — the unit measures something the recipe does
///   not say it makes: `blob` in ml against a recipe that only says `makes 300
///   g`. There is no density for a recipe, so the way out is the second MAKES
///   denomination, and the sentence says so.
Result<RecipeMeasure> authorRecipeMeasure({
  required String id,
  required String recipeId,
  required String label,
  required double? amount,
  required Unit unit,
  required List<YieldDenomination> yields,
  List<RecipeMeasure> measures = const [],
  int sortOrder = 0,
}) {
  final word = measureLabelAsAuthored(label);
  if (yields.isEmpty) {
    return const Err(
      Failure('recipe_measure/no_yield', kRecipeMeasureNoYieldRefusal),
    );
  }
  if (word.isEmpty) {
    return const Err(
      Failure(
        'recipe_measure/no_label',
        'Give it a word — what you call one of these.',
      ),
    );
  }
  if ((unitFromLabel(word) ?? unitFromWord(word)) != null) {
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
  if (!kRecipeMeasureFamilies.contains(unit.family)) {
    return Err(
      Failure(
        'recipe_measure/unit_cannot_measure',
        recipeMeasureUnitCannotMeasureRefusal(word, unit),
      ),
    );
  }
  // `!(x > 0)` (rather than `x <= 0`) also catches NaN.
  if (amount == null || !amount.isFinite || !(amount > 0)) {
    return Err(
      Failure('recipe_measure/amount', recipeMeasureAmountRefusal(word)),
    );
  }
  final measure = RecipeMeasure(
    id: id,
    recipeId: recipeId,
    label: word,
    amount: amount,
    unit: unit,
    sortOrder: sortOrder,
  );
  // Asked of the finished row, through the one resolution every reader uses, so
  // "the recipe can hold this word" means here exactly what it means to a line.
  if (!recipeMeasureResolvesAgainst(measure, yields)) {
    return Err(
      Failure(
        'recipe_measure/unit_family',
        recipeMeasureUnitFamilyRefusal(word, unit, yields),
      ),
    );
  }
  return Ok(measure);
}

/// What a word may be said in against [yields]: every catalog unit of a family
/// the recipe states, in the catalog's own kitchen order.
///
/// The gate read forwards. [authorRecipeMeasure] refuses a unit whose family
/// the recipe does not state, so an offer assembled any other way would be a
/// chip row whose only possible answer is a refusal — and there is no density
/// for a recipe to bridge one family to another (ADR-0008), so the way to say a
/// blob in millilitres really is the second MAKES denomination.
///
/// Empty for a recipe that states no yield, which is the authoring door's
/// disabled state — and for one whose only yield is in a family no size can be
/// said in ([kRecipeMeasureFamilies]), which has the same answer for the same
/// reason.
List<Unit> recipeMeasureUnitChoices(List<YieldDenomination> yields) {
  final families = {
    for (final y in yields)
      if (kRecipeMeasureFamilies.contains(y.unit.family)) y.unit.family,
  };
  return [
    for (final u in kIngredientUnits)
      if (families.contains(u.family)) u,
  ];
}

/// What the authoring form opens on: the FIRST stated yield's own unit — the
/// batch is measured in it, so the first word a household coins usually is too.
///
/// Falls back to the head of [recipeMeasureUnitChoices] where that yield's own
/// unit is not a unit a word may be said in, and null where nothing may be said
/// at all.
Unit? recipeMeasureOpeningUnit(List<YieldDenomination> yields) {
  final choices = recipeMeasureUnitChoices(yields);
  if (choices.isEmpty) return null;
  final stated = yields.first.unit;
  return choices.contains(stated) ? stated : choices.first;
}

/// Which of [measures] a `makes` edit would leave standing on nothing: the
/// words that can be held against [from] — what the recipe says now — and
/// cannot be held against [to], what the Save would make it say.
///
/// A pure function, so the recipe editor can warn *before* the Save rather than
/// let the lines discover it. A word that is already orphaned is not reported:
/// the warning is about what this edit takes away, and re-warning about a gap
/// that is already on screen teaches a person to dismiss the dialog.
///
/// The one thing it does NOT do is refuse. Re-stating what a batch makes is a
/// fact about the recipe, and the household is allowed to change it; the
/// consequence is that some lines go unresolved, which every surface then names
/// (`ComponentYieldMissing` / `ComponentFamilyMismatch`). This only makes sure
/// nobody finds that out by accident.
List<RecipeMeasure> recipeMeasuresOrphanedBy({
  required List<RecipeMeasure> measures,
  required List<YieldDenomination> from,
  required List<YieldDenomination> to,
}) => [
  for (final m in measures)
    if (recipeMeasureResolvesAgainst(m, from) &&
        !recipeMeasureResolvesAgainst(m, to))
      m,
];

/// Why no word can be coined yet: the recipe does not say what a batch makes.
///
/// A constant rather than a function, because it is also the sentence the
/// disabled MEASURES list carries — the same words whether a person has typed
/// anything or not.
const kRecipeMeasureNoYieldRefusal =
    'Say what a batch makes first, under MAKES. A word like “blob” is a size, '
    'and a size is only a share of a batch once the batch has one too.';

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
    '${_said(taken.amount, taken.unit)}. Re-state that one and every line '
    'saying it follows.';

/// Why a measure cannot be minted without its number.
String recipeMeasureAmountRefusal(String label) =>
    'Say what one “$label” comes to — a number above zero.';

/// Why a word cannot be said in `batch`, or in an imprecise word.
String recipeMeasureUnitCannotMeasureRefusal(String label, Unit unit) =>
    unit.family == UnitFamily.batch
    ? '“$label” can’t be a fraction of a batch — that is the arithmetic nobody '
          'thinks in, and the word is here to reach a batch rather than to be '
          'one. Say what one comes to as a weight, a volume or a count.'
    : '“${unit.label}” is not a size, so it can’t say what one “$label” comes '
          'to. Say it as a weight, a volume or a count.';

/// Why a word in this unit cannot be read against this recipe: the recipe does
/// not say what a batch makes in that unit's family, and a recipe has no
/// density to bridge one family to another (ADR-0008 — that is an ingredient's
/// fact about a substance, and a recipe is not one).
///
/// It names both sides and the way out, because the way out is a real one: the
/// second MAKES denomination exists exactly for this.
String recipeMeasureUnitFamilyRefusal(
  String label,
  Unit unit,
  List<YieldDenomination> yields,
) =>
    'This recipe makes ${yields.map((y) => _said(y.qty, y.unit)).join(' · ')}, '
    'so “$label” can’t be said in ${unit.label} — a recipe has no density to '
    'get from one to the other. Say it in what the batch is measured in, or '
    'add what a batch makes in ${unit.label} under MAKES.';

/// `15 g`, `1.25 cup` — an amount and its unit, said the one way the app says
/// them ([formatAmountIn]).
String _said(double amount, Unit unit) =>
    '${formatAmountIn(amount, unit)} ${unit.label}';
