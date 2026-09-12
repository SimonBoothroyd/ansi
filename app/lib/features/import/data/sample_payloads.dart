/// Fixed reconciliation payloads for tests and the on-device smoke test.
///
/// [cannedReconciliationPayloadJson] is a compact, representative recipe that
/// exercises all three match bands, a printed range, a counted-produce line
/// that names a number and no thing (seam D2 — it arrives on the row's curated
/// default measure, unflagged), a coalescing duplicate no-match, and the full
/// step-token vocabulary (text / ref / timer / portion / collective).
///
/// [peanutStirFryPayloadJson] is the opposite kind of fixture: a whole page
/// written for this repo, with the bands the REAL cascade
/// (`supabase/functions/_shared/match.ts`) returns for it against the seeded
/// vocabulary. The per-line band and why it landed there are recorded on the
/// constant.
///
/// They live in `lib/` (not `test/`) because the on-device smoke tests under
/// `integration_test/` drive the whole import flow through
/// `SqliteImportRepository` against the real synced stack, with no network and
/// no LLM on the import path.
///
/// Neither is a production fallback: the app's import path is the real
/// `import-recipe` edge function, and an unconfigured build refuses to import
/// rather than serving these (see `importRepositoryProvider`). Candidate
/// `ingredient_id`s here are placeholders that `SqliteImportRepository`
/// re-resolves against the real local vocab.
///
/// The extraction-contract tests use the blessed gold files under
/// `evals/datasets/extraction/gold/` instead.
library;

const cannedReconciliationPayloadJson = '''
{
  "title": "Weeknight Tomato Pasta",
  "servings_base": 2,
  "servings_raw": "Serves 2",
  "yield_raw": null,
  "total_time_seconds": 1500,
  "cook_time_seconds": null,
  "truncated": false,
  "image_quality": "ok",
  "parse_warnings": [
    "Quantity for the chilli flakes was not printed — left blank for you to set."
  ],
  "groups": [
    {
      "name": null,
      "lines": [
        {
          "raw": { "qty": 200, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "spaghetti",
            "notes": null, "raw_amount": "200g", "optional": false,
            "confidence": 0.97 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-spaghetti", "canonical_name": "Spaghetti",
              "score": 0.98 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": 2, "qty_high": 3, "unit": "clove",
            "unit_mappable": true, "ingredient_text": "garlic cloves, sliced",
            "notes": null, "raw_amount": "2–3 cloves", "optional": false,
            "confidence": 0.9 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-garlic", "canonical_name": "Garlic",
              "score": 0.95 }
          ]
        },
        {
          "raw": { "qty": 400, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "tinned chopped tomatoes",
            "notes": null, "raw_amount": "1 x 400g tin", "optional": false,
            "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-tomatoes",
              "canonical_name": "Chopped tomatoes", "score": 0.95 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "pinch", "unit_mappable": true,
            "ingredient_text": "Aleppo chilli flakes", "notes": null,
            "raw_amount": "A good pinch", "optional": true, "confidence": 0.8 },
          "band": "none",
          "candidates": []
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "to_taste", "unit_mappable": true,
            "ingredient_text": "Aleppo chilli flakes", "notes": "to serve",
            "raw_amount": "", "optional": true,
            "confidence": 0.8 },
          "band": "none",
          "candidates": []
        },
        {
          "raw": { "qty": 2, "qty_low": null, "qty_high": null,
            "unit": "piece", "unit_mappable": true,
            "ingredient_text": "red peppers, deseeded",
            "notes": "deseeded", "raw_amount": "2",
            "optional": false, "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-red-pepper",
              "canonical_name": "Red Bell Pepper", "score": 0.96 }
          ]
        }
      ]
    },
    {
      "name": "To finish",
      "lines": [
        {
          "raw": { "qty": 30, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "Parmesan, grated",
            "notes": null, "raw_amount": "30g", "optional": false,
            "confidence": 0.9 },
          "band": "suggest",
          "candidates": [
            { "ingredient_id": "vocab-parmesan", "canonical_name": "Parmesan",
              "score": 0.66 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "handful", "unit_mappable": true,
            "ingredient_text": "fresh basil leaves", "notes": null,
            "raw_amount": "A handful", "optional": false, "confidence": 0.85 },
          "band": "none",
          "candidates": []
        }
      ]
    }
  ],
  "steps": [
    {
      "tokens": [
        { "t": "text", "s": "Boil the " },
        { "t": "ref", "refs": [0], "label": "spaghetti", "mention": "new",
          "portion": null },
        { "t": "text", "s": " in well-salted water for " },
        { "t": "timer", "low_seconds": 540, "high_seconds": 660 },
        { "t": "text", "s": "." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Meanwhile, soften the " },
        { "t": "ref", "refs": [1], "label": "garlic", "mention": "new",
          "portion": null },
        { "t": "text", "s": " with the " },
        { "t": "ref", "refs": [5], "label": "peppers", "mention": "new",
          "portion": null },
        { "t": "text", "s": ", add the " },
        { "t": "ref", "refs": [2], "label": "tomatoes", "mention": "new",
          "portion": null },
        { "t": "text", "s": " and a " },
        { "t": "ref", "refs": [3], "label": "pinch of chilli", "mention": "new",
          "portion": null },
        { "t": "text", "s": ", then simmer " },
        { "t": "timer", "low_seconds": 600, "high_seconds": 600 },
        { "t": "text", "s": "." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Toss the drained pasta through the sauce with " },
        { "t": "ref", "refs": [2, 6], "label": "the sauce and cheese",
          "mention": "rementioned", "portion": null },
        { "t": "text", "s": ", then finish with " },
        { "t": "ref", "refs": [7], "label": "basil", "mention": "new",
          "portion": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": null, "qualifier": "to serve" } },
        { "t": "text", "s": "." }
      ]
    }
  ]
}
''';

/// A weeknight page of our own — "Peanut Tofu Stir-Fry" — carrying the bands
/// the REAL cascade returns for it against the seeded vocabulary.
///
/// The recipe is written here, not transcribed from a book, so the repo
/// carries no cookbook text; the bands and candidates come from running
/// `matchLines` over these lines with the in-memory matcher built from
/// `supabase/seed/snapshot.jsonl`. Nothing is hand-picked to make a screen
/// look good — the page is written in a British kitchen's words and the
/// vocabulary is stored in an American one's, which is exactly the review
/// screen's hardest real input.
///
/// **Which band each line landed in, and why** — the part that is otherwise
/// invisible once the payload is JSON:
///
/// - **0 pak choi — `none`.** No row and no alias comes near it; the
///   household's nearest thing is `Napa Cabbage`, which shares no trigram.
/// - **1 groundnut oil — `none`.** `Peanut Oil` is the same bottle, but the
///   only shared word is `oil`, well under the trigram floor.
/// - **2 extra firm tofu — `auto`.** Exact `match_text` hit.
/// - **3 coriander — `suggest`.** The herb is stored as `Cilantro`, which
///   shares no letters; `Ground Coriander` scores 0.588 on the shared word,
///   so the one chip offered is the wrong jar.
/// - **4 peanut butter / 5 tamari — `auto`.** Exact hits.
/// - **6 sugar snap peas — `none`.** `Peas` and `Frozen Peas` both sit under
///   the floor once `sugar snap` is in the phrase.
/// - **7 lime juice — `auto`.** Exact hit.
/// - **8 Sea salt / 9 black pepper — `auto`.** Exact hits, one per half of
///   the compound split. Both carry `unit: "to_taste"` with
///   `unit_mappable: false`, which is what the extractor really returns for an
///   imprecise word (it is a catalog id AND not a measurable unit) — the page
///   prints no "to taste", so the unit is the extractor's, not the page's.
///
/// Four lines want the human: three `none` lines to find or create, and one
/// `suggest` line whose right answer — `Cilantro` — is not the chip on offer
/// and is reached through the sheet's search.
const peanutStirFryPayloadJson = '''
{
  "title": "Peanut Tofu Stir-Fry",
  "servings_base": 2,
  "servings_raw": "Serves 2",
  "yield_raw": null,
  "total_time_seconds": 1500,
  "cook_time_seconds": null,
  "truncated": false,
  "image_quality": "ok",
  "parse_warnings": [
    "The hot water for the sauce is named in the method only — not listed as a line."
  ],
  "groups": [
    {
      "name": null,
      "lines": [
        {
          "raw": { "qty": 200, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "pak choi",
            "notes": "leaves separated, stalks sliced", "raw_amount": "200g",
            "optional": false, "confidence": 0.95 },
          "band": "none",
          "candidates": []
        },
        {
          "raw": { "qty": 1, "qty_low": null, "qty_high": null, "unit": "tbsp",
            "unit_mappable": true, "ingredient_text": "groundnut oil",
            "notes": null, "raw_amount": "1 tbsp", "optional": false,
            "confidence": 0.95 },
          "band": "none",
          "candidates": []
        },
        {
          "raw": { "qty": 400, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "extra firm tofu",
            "notes": "pressed and torn into chunks", "raw_amount": "400g",
            "optional": false, "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-extra-firm-tofu",
              "canonical_name": "Extra Firm Tofu", "score": 1.0 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "handful", "unit_mappable": true,
            "ingredient_text": "coriander", "notes": "leaves picked, to serve",
            "raw_amount": "A small handful", "optional": false,
            "confidence": 0.9 },
          "band": "suggest",
          "candidates": [
            { "ingredient_id": "vocab-ground-coriander",
              "canonical_name": "Ground Coriander", "score": 0.588 }
          ]
        },
        {
          "raw": { "qty": 3, "qty_low": null, "qty_high": null, "unit": "tbsp",
            "unit_mappable": true, "ingredient_text": "peanut butter",
            "notes": null, "raw_amount": "3 tbsp", "optional": false,
            "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-peanut-butter",
              "canonical_name": "Peanut Butter", "score": 1.0 }
          ]
        },
        {
          "raw": { "qty": 2, "qty_low": null, "qty_high": null, "unit": "tbsp",
            "unit_mappable": true, "ingredient_text": "tamari",
            "notes": null, "raw_amount": "2 tbsp", "optional": false,
            "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-tamari", "canonical_name": "Tamari",
              "score": 1.0 }
          ]
        },
        {
          "raw": { "qty": 150, "qty_low": null, "qty_high": null, "unit": "g",
            "unit_mappable": true, "ingredient_text": "sugar snap peas",
            "notes": "halved lengthways", "raw_amount": "150g",
            "optional": false, "confidence": 0.95 },
          "band": "none",
          "candidates": []
        },
        {
          "raw": { "qty": 2, "qty_low": null, "qty_high": null, "unit": "tbsp",
            "unit_mappable": true, "ingredient_text": "lime juice",
            "notes": null, "raw_amount": "2 tbsp", "optional": false,
            "confidence": 0.95 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-lime-juice",
              "canonical_name": "Lime Juice", "score": 1.0 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "to_taste", "unit_mappable": false,
            "ingredient_text": "Sea salt", "notes": null,
            "raw_amount": "Sea salt", "optional": false, "confidence": 0.9 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-sea-salt", "canonical_name": "Sea Salt",
              "score": 1.0 }
          ]
        },
        {
          "raw": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": "to_taste", "unit_mappable": false,
            "ingredient_text": "black pepper", "notes": null,
            "raw_amount": "black pepper", "optional": false,
            "confidence": 0.9 },
          "band": "auto",
          "candidates": [
            { "ingredient_id": "vocab-black-pepper",
              "canonical_name": "Black Pepper", "score": 1.0 }
          ]
        }
      ]
    }
  ],
  "steps": [
    {
      "tokens": [
        { "t": "text", "s": "Press the " },
        { "t": "ref", "refs": [2], "label": "tofu", "mention": "new",
          "portion": null },
        { "t": "text", "s": " between two plates for " },
        { "t": "timer", "low_seconds": 600, "high_seconds": 600 },
        { "t": "text",
          "s": " while you prep everything else, then tear it into rough chunks." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Whisk the " },
        { "t": "ref", "refs": [4], "label": "peanut butter", "mention": "new",
          "portion": null },
        { "t": "text", "s": ", " },
        { "t": "ref", "refs": [5], "label": "tamari", "mention": "new",
          "portion": null },
        { "t": "text", "s": " and " },
        { "t": "ref", "refs": [7], "label": "lime juice", "mention": "new",
          "portion": null },
        { "t": "text",
          "s": " with 4 tablespoons of hot water until smooth and pourable." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Heat the " },
        { "t": "ref", "refs": [1], "label": "groundnut oil", "mention": "new",
          "portion": null },
        { "t": "text", "s": " in a wok over a high heat. Fry the " },
        { "t": "ref", "refs": [2], "label": "tofu", "mention": "rementioned",
          "portion": null },
        { "t": "text", "s": " for " },
        { "t": "timer", "low_seconds": 480, "high_seconds": 600 },
        { "t": "text",
          "s": ", turning now and then, until golden on every side. Season with a pinch of " },
        { "t": "ref", "refs": [8, 9], "label": "salt and pepper",
          "mention": "new",
          "portion": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": null, "qualifier": "a pinch" } },
        { "t": "text", "s": "." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Add the " },
        { "t": "ref", "refs": [0], "label": "pak choi", "mention": "new",
          "portion": null },
        { "t": "text", "s": " and " },
        { "t": "ref", "refs": [6], "label": "sugar snap peas",
          "mention": "new", "portion": null },
        { "t": "text", "s": " and stir-fry for " },
        { "t": "timer", "low_seconds": 120, "high_seconds": 180 },
        { "t": "text", "s": " until just tender. Pour in the " },
        { "t": "ref", "refs": [4, 5, 7], "label": "peanut sauce",
          "mention": "new", "portion": null },
        { "t": "text", "s": " and toss until everything is coated." }
      ]
    },
    {
      "tokens": [
        { "t": "text", "s": "Serve straight away, scattered with the " },
        { "t": "ref", "refs": [3], "label": "coriander", "mention": "new",
          "portion": { "qty": null, "qty_low": null, "qty_high": null,
            "unit": null, "qualifier": "to serve" } },
        { "t": "text", "s": " and a grind of " },
        { "t": "ref", "refs": [9], "label": "black pepper",
          "mention": "fraction", "portion": null },
        { "t": "text", "s": "." }
      ]
    }
  ]
}
''';
