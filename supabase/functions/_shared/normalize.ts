// Ingredient-text normalization (docs/product-specs/import-and-matching.md §7).
//
// STUB — no logic yet (implementing it is a feature, roadmap step 8). The spec'd
// rules: lowercase; singularize; strip trailing comma modifier; strip prep verbs
// (chopped/diced/minced/sliced/grated); KEEP form/state words (fresh vs ground,
// canned vs cream). Symmetric normalization on both query text and stored names
// is what makes the match cascade work.

export function normalize(_ingredientText: string): string {
  // TODO(step-8): implement per §7. Land with tests in normalize.test.ts.
  throw new Error("normalize() not implemented — roadmap step 8");
}
