-- 0018_fold_diacritics.sql — stored `match_text` folds its Latin diacritics
-- (search & matching v1, decision D5).
--
-- The shared normalizer (`functions/_shared/normalize.ts` and its Dart mirror)
-- now folds accented Latin letters onto their base letter, so "Jalapeño" is
-- written `jalapeno` and an import line — or a picker query — printed without
-- the tilde reaches the row that has it. Before this, `jalapeno` scored 0.500
-- against `jalapeño`, just under BAND_SUGGEST_MIN, so the line got no
-- candidates at all; the miss was silent and total, and it recurs with crème,
-- açaí and piment d'Espelette.
--
-- The seed files are regenerated with the new normalizer, so a fresh
-- `supabase db reset` needs nothing from this migration. It exists for
-- households that are ALREADY provisioned: onboarding clones the template
-- vocabulary at signup, so those copies carry the old spelling and no reseed
-- reaches them. Exactly one seeded row is affected today (Jalapeño) and the
-- number only grows, which is the whole argument for doing it now.
--
-- Idempotent by construction: `translate` over an already-folded string is the
-- identity, so re-running changes nothing. Only the MATCH text moves —
-- `canonical_name` and `alias_text` keep their accents, because they are what
-- a human reads. `updated_at` is deliberately NOT bumped: this is a
-- normalization repair, not a household edit, and touching it would push a
-- pointless sync delta at every device.

begin;

-- Lowercase Latin-1 Supplement + Latin Extended-A, matching the two
-- normalizer mirrors letter for letter. `match_text` is always lowercase, so
-- the uppercase halves are not needed here.
create or replace function fold_match_diacritics(t text)
returns text language sql immutable strict as $$
  select translate(
    t,
    'àáâãäåāăąçćĉċčďèéêëēĕėęěĝğġģĥìíîïĩīĭįĵķĺļľñńņňòóôõöōŏőŕŗřśŝşšţťùúûüũūŭůűųŵýÿŷźżž',
    'aaaaaaaaacccccdeeeeeeeeegggghiiiiiiiijklllnnnnoooooooorrrssssttuuuuuuuuuuwyyyzzz'
  );
$$;

update ingredient
   set match_text = fold_match_diacritics(match_text)
 where match_text <> fold_match_diacritics(match_text);

update ingredient_alias
   set match_text = fold_match_diacritics(match_text)
 where match_text <> fold_match_diacritics(match_text);

update usda_food
   set match_text = fold_match_diacritics(match_text)
 where match_text <> fold_match_diacritics(match_text);

-- A one-shot repair, not a new piece of schema: the normalizer owns this rule
-- and there must not be a second, drifting way to write the same text.
drop function fold_match_diacritics(text);

commit;
