/// The ingredient form's name suggestion. Pure Dart.
///
/// A person often types a recipe line ("2 cups flour", "chopped onions"). When
/// the name field is left, the form offers the entry the line was about
/// (`Flour`, `Onions`) and prints `was “…” · keep the old word` so one tap
/// restores it. Which words are quantity, measure, size, prep or filler is
/// [normalizeMatchText]'s verdict, read through [displayWords].
///
/// It does not reorder (`Fresh Ginger` stays as typed), look for an existing
/// twin, or singularize (the vocabulary keeps plurals like `Bay Leaves`).
library;

import '../../../core/text/name_clean.dart';
import 'normalize.dart';

/// A better display name for an already-[cleanName]ed name, or null when
/// [cleaned] is already the entry. Stop words drop out ("2 cups flour" →
/// "flour") and the rest is [cleanName]ed. Null when the result differs only in
/// case, or when every word was a stop word.
String? suggestIngredientName(String cleaned) {
  final kept = displayWords(cleaned);
  if (kept.isEmpty) return null;
  final suggestion = cleanName(kept.join(' '), NameKind.title);
  if (suggestion.isEmpty) return null;
  return suggestion.toLowerCase() == cleaned.toLowerCase() ? null : suggestion;
}
