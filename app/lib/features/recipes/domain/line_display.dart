/// How an ingredient line READS — inline display grouping for the recipe page
/// and the source-line join the import review shows — PURE DART (invariant 2).
///
/// The recipe page reads `amount · ingredient · notes` on one line per
/// ingredient identity (v3 LOCKED design). When several line items in a group
/// resolve to the SAME ingredient — the reconcile-time "used N ways" identity —
/// the page folds them into ONE [LineUses] row: the ingredient is named once,
/// and each use keeps its own amount and note. Amounts and notes are joined in
/// parallel ("2 cloves + 1 clove" · "finely chopped + sliced"), **never
/// summed** (invariant 3 — a count of cloves is not a mass to add up; the two
/// uses are two distinct call-outs in the method).
///
/// Grouping is by the line's IDENTITY — its [LineItem.ingredientId], or its
/// [LineItem.subRecipeId] for a sub-recipe component (step 8.6 / D1) — and
/// scoped to a single [IngredientGroup]: two mentions of garlic under "for the
/// sauce" fold; garlic in a separate "to serve" group stays its own row.
/// First-occurrence order is preserved, so the folded row sits where the
/// ingredient first appears.
library;

import 'recipe.dart';

/// One inline recipe-page row: an ingredient identity and its ordered [uses].
///
/// A single-use ingredient has a one-element [uses]; a multi-use identity holds
/// each sibling line in source order. The presentation layer renders the amount
/// column by joining each use's amount with " + " and the note modifier by
/// joining the non-empty notes — an empty note drops its slot rather than
/// leaving a dangling "+".
class LineUses {
  const LineUses({required this.uses, this.ingredientId, this.subRecipeId})
    : assert(uses.length > 0, 'a display row needs at least one use');

  /// The ingredient this row names, or null when the row is a sub-recipe
  /// component — exactly one of the two is set, mirroring [LineItem]'s XOR.
  final String? ingredientId;

  /// The sub-recipe this row names (step 8.6), or null for an ingredient row.
  final String? subRecipeId;

  /// The sibling line items, in source order. The first carries the display
  /// name ([ingredientName]); every sibling shares the same identity.
  final List<LineItem> uses;

  /// Whether this row names a sub-recipe rather than an ingredient.
  bool get isComponent => subRecipeId != null;

  /// The ingredient's display name — taken from the first use.
  String get ingredientName => uses.first.ingredientName;

  /// Whether this identity was mentioned more than once in the group.
  bool get isMultiUse => uses.length > 1;

  /// The non-empty notes of each use, in order — parallel to the amounts, with
  /// a missing note omitted (never merged, never summed).
  List<String> get notes => [
    for (final u in uses)
      if (u.note != null && u.note!.trim().isNotEmpty) u.note!.trim(),
  ];
}

/// Joins one imported line's printed amount and ingredient text into the
/// single "from source" reference string, eliding a word the two both print.
///
/// Extractors routinely repeat the measure word on both sides — `2–3 cloves` +
/// `garlic cloves, sliced` — and rendering them back to back stutters: "2–3
/// cloves garlic cloves, sliced". The overlap is dropped from the AMOUNT side
/// so the ingredient text (the identity we matched on) survives verbatim:
/// "2–3 garlic cloves, sliced".
///
/// The comparison is case- and plural-insensitive and looks only at the
/// ingredient text's leading phrase (up to the first comma/bracket): a word
/// repeated in a trailing prep note ("garlic, cloves separated") is a second
/// fact, not a stutter. Only whole trailing words of the amount are elided, and
/// only once — the printed source is a reference, never prose we rewrite.
String joinSourceLine(String rawAmount, String ingredientText) {
  final amount = rawAmount.trim();
  final text = ingredientText.trim();
  if (amount.isEmpty || text.isEmpty) {
    return [amount, text].where((s) => s.isNotEmpty).join(' ');
  }

  final amountWords = amount.split(RegExp(r'\s+'));
  final lead = [
    for (final w in text.split(RegExp(r'[,;(\[]')).first.split(RegExp(r'\s+')))
      _displayWordKey(w),
  ];
  for (var k = amountWords.length; k > 0; k--) {
    final tail = [
      for (final w in amountWords.sublist(amountWords.length - k))
        _displayWordKey(w),
    ];
    if (tail.any((w) => w.isEmpty)) continue;
    if (!_containsRun(lead, tail)) continue;
    final kept = amountWords.sublist(0, amountWords.length - k).join(' ');
    return kept.isEmpty ? text : '$kept $text';
  }
  return '$amount $text';
}

/// A word reduced to what makes two printings "the same word": lowercase,
/// letters and digits only, and the simple `s` plural dropped (only on a word
/// long enough for that to be a plural — "as" is not "a").
String _displayWordKey(String word) {
  final bare = word.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (bare.length >= 4 && bare.endsWith('s')) {
    return bare.substring(0, bare.length - 1);
  }
  return bare;
}

/// Whether [run] appears as a contiguous subsequence of [words].
bool _containsRun(List<String> words, List<String> run) {
  if (run.isEmpty || run.length > words.length) return false;
  for (var i = 0; i + run.length <= words.length; i++) {
    var hit = true;
    for (var j = 0; j < run.length; j++) {
      if (words[i + j] != run[j]) {
        hit = false;
        break;
      }
    }
    if (hit) return true;
  }
  return false;
}

/// Folds [items] into inline display rows, one per identity, in
/// first-occurrence order. Items sharing an identity — the same
/// [LineItem.ingredientId], or the same [LineItem.subRecipeId] for a component
/// — coalesce into one [LineUses]; every other item is its own single-use row.
///
/// A line with neither identity cannot exist (the DB's XOR check) but would
/// arrive from foreign data; it gets its own row keyed by the line id rather
/// than being folded with every other such line.
List<LineUses> groupLineUses(List<LineItem> items) {
  final order = <String>[];
  final byKey = <String, List<LineItem>>{};
  for (final item in items) {
    final key = item.ingredientId ?? 'sub:${item.subRecipeId ?? item.id}';
    byKey
        .putIfAbsent(key, () {
          order.add(key);
          return <LineItem>[];
        })
        .add(item);
  }
  return [
    for (final key in order)
      LineUses(
        ingredientId: byKey[key]!.first.ingredientId,
        subRecipeId: byKey[key]!.first.subRecipeId,
        uses: byKey[key]!,
      ),
  ];
}
