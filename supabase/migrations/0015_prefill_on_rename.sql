-- 0015_prefill_on_rename.sql — the USDA stub prefill also fires on a RENAME
-- (roadmap step 8.5, exec plan 0020 D7).
--
-- 0014 landed `ingredient_usda_prefill` as an AFTER INSERT trigger. D7's own
-- rationale asks for more than that: option (c) exists to cover "what (a)
-- can't: rows the trigram missed, and **renames** (you fix 'curry leafs' →
-- 'Curry leaves, fresh' and want the lookup re-run)". The flesh-out form
-- shipped saying exactly that on screen — a rename re-runs it — and a
-- trigger that only ever fired on insert made that copy a lie: a stub
-- created under a name the trigram missed could be renamed to the right one
-- and nothing would look again.
--
-- So the trigger is recreated as `after insert or update of canonical_name`.
-- Nothing else moves:
--
--   * **The WHEN guards are 0014's, verbatim** — and they are what makes the
--     new leg safe. `density_g_per_ml is null and macros is null` means only
--     a BARE stub is ever re-probed, so a rename can never clobber numbers a
--     human filled in or confirmed; `source in ('manual','import_stub')`
--     still excludes the seed's audited density tail and a barcode row's
--     Open Food Facts provenance (`off:<barcode>`), which the prefill's
--     wholesale `source` rewrite would otherwise replace with a USDA id.
--   * **The function is untouched.** Same single indexed trigram probe, same
--     0.5 floor, same swallow-and-log so a client's upload transaction can
--     never fail because of it, same rule that the row STAYS `status='stub'`
--     (D5: confirming is a human act). Only its comment is re-stated below,
--     so `\df+` no longer describes a trigger that has grown a second leg.
--
-- Two mechanics worth stating, because the update leg depends on them:
--
--   * `update of canonical_name` fires when that column appears in the
--     statement's SET list. The prefill's own UPDATE writes density, macros,
--     source and updated_at and never the name, so the trigger cannot
--     re-enter itself.
--   * The probe reads `new.match_text`, not the name. That is correct
--     because the rename hazard (D6) is already closed on both writers: the
--     app's `saveEdit` writes `canonical_name` and `match_text` in one
--     statement, and so does the server. A caller that renamed without
--     rewriting the match text would re-probe the old text — but such a
--     caller is already broken for matching, which is the bug D6 fixed.
--
-- 0014 is not edited (immutable-migrations convention): this file replaces
-- the trigger in place.

drop trigger if exists ingredient_usda_prefill on ingredient;
create trigger ingredient_usda_prefill
  after insert or update of canonical_name on ingredient
  for each row
  when (new.status = 'stub'
        and new.deleted_at is null
        and new.density_g_per_ml is null
        and new.macros is null
        and (new.source is null
             or new.source in ('manual', 'import_stub')))
  execute function ingredient_prefill_from_usda();

comment on function ingredient_prefill_from_usda() is
  'AFTER INSERT OR UPDATE OF canonical_name prefill of a stub ingredient '
  'from the server-only usda_food reference (ADR-0005; plan 0020 D7). Port '
  'of the deleted TypeScript prefillStubFromUsda. Runs inside the client '
  'upload transaction: one indexed trigram probe, and every error swallowed '
  'so the upload can never fail because of it. Fires only for a BARE stub '
  '(no density, no macros), so a rename never re-probes a row someone has '
  'filled in. The row stays status=''stub''.';
