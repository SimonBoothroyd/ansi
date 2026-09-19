-- 0047_receipt_line_name_printed.sql — the paper's words for the thing, kept
-- on the line, so the household's own answers can be read back.
--
-- The first real receipt — a 29-line Trader Joe's strip — matched none of its
-- 29 lines. Not because the vocabulary was missing the food, but because
-- `ORG TRICOLOR QUINOA` scored under the suggest floor against `Quinoa`: a
-- whole-string trigram cannot see one word inside four of a store's
-- abbreviations. No amount of tuning fixes that in general, because the
-- abbreviations are a store's and not a language's.
--
-- What does fix it is the household. Once somebody has said, on one receipt,
-- that `ORG TRICOLOR QUINOA` is Quinoa, the next receipt does not need to
-- guess. So the receipt door now REMEMBERS the answers this household has
-- already given, per printed name — and the memory is not a new table. It is
-- the saved receipt lines, which already hold the answer beside the words it
-- answers.
--
-- ---------------------------------------------------------------------------
-- This is NOT an alias, and must never become one
-- ---------------------------------------------------------------------------
--
-- A receipt's words are one store's abbreviations, and the vocabulary is the
-- household's own language (plan 0049, owner). Teaching the vocabulary
-- `TJ SRIRACHA` would put a store's shorthand into every recipe import, every
-- picker and every search. So nothing here is written to the vocabulary's
-- alias table, the matcher never sees these words, and
-- `functions/import-receipt/no_alias.test.ts` holds that structurally rather
-- than by this paragraph. The recall is a SELECT over this household's own
-- receipt lines and nothing else.
--
-- Two things fall out of the memory being the lines themselves, and both are
-- the reason it is shaped this way:
--
--   * **There is no second list to maintain.** A receipt IS the record of what
--     was said about it.
--   * **A mistake is corrected where it was made.** A saved receipt is
--     editable, and the most recently said answer wins (the recall orders by
--     the line's `updated_at`), so correcting an old receipt corrects the
--     memory. The owner asked for exactly this: "we need a way to remove from
--     this probably in case of mistake matching".
--
-- ---------------------------------------------------------------------------
-- The column
-- ---------------------------------------------------------------------------
--
-- `printed_text` is the whole line, figures and all — `TJ ORG BANANAS  3.49`.
-- It is the paper's own words and it is what the review shows under every card
-- so a reader can check what was read, and it is useless as a key: the same
-- item at a different price is a different string. `name_printed` is the same
-- line with the figures taken off, which is the part that names the thing, and
-- it is already what the wire carries and what the match cascade is given.
-- Nullable: a hand-typed price has no paper to have printed anything, and a
-- line written by a client that predates this column has none either.

alter table receipt_line
  add column name_printed text;

comment on column receipt_line.name_printed is
  'The paper''s words for the THING, with the figures taken off — the part of '
  'printed_text that names what was bought. The receipt door recalls this '
  'household''s own past answers by it (latest updated_at wins), which is why '
  'it is stored trimmed and compared case-insensitively. It is not a '
  'vocabulary word and is never learned as one: a receipt teaches the '
  'vocabulary nothing.';

-- What the recall reads, and the only shape it reads in: this household's
-- lines, by the upper-cased printed name. The expression must be spelled the
-- same way in the query for the index to be used — see
-- `functions/_shared/receipt_memory.ts`.
create index receipt_line_name_printed_idx
  on receipt_line (household_id, upper(name_printed));

-- Grants and RLS are unchanged: both are on the TABLE (0044), so the new
-- column arrives under the policies and the grants the table already has.
-- The PowerSync publication is unchanged for the same reason, and both receipt
-- sync rules are `select *`, so the column reaches a device with the
-- migration — once the sync container is recreated from a checkout that holds
-- it.

-- ---------------------------------------------------------------------------
-- Backfill: the name every photographed line was printed with
-- ---------------------------------------------------------------------------
--
-- A till prints the money last, so the name is the line with a trailing money
-- figure taken off it. That is a text operation on a string the database
-- already holds — nothing is re-read, re-modelled or invented, and a row that
-- has no `printed_text` (every hand-typed price) is left alone.
--
-- It is deliberately literal-minded, and two kinds of line come out of it as a
-- string that will simply never equal anything:
--
--   * a line SOLD BY WEIGHT, whose printed text carries its own arithmetic —
--     `YELLOW ONIONS  1.32 lb @ 1.99/lb  2.63` backfills as
--     `YELLOW ONIONS  1.32 lb @ 1.99/lb`;
--   * a line whose figure the reader could not make out, which printed no
--     money figure to strip.
--
-- Neither is a fault to correct here. The recall is an EXACT match, so a name
-- that equals nothing recalls nothing and the line is matched by the cascade
-- exactly as it is today. The value earns itself back the first time that
-- receipt is opened and re-saved, because Save writes what the review holds.
update receipt_line l
   set name_printed = nullif(
         btrim(regexp_replace(l.printed_text, '\s*-?\$?[0-9]+\.[0-9]{2}\s*$', '')),
         ''
       )
  from receipt r
 where r.id = l.receipt_id
   and r.source = 'photo'
   and l.printed_text is not null
   and l.name_printed is null;
