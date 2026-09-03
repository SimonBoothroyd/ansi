-- 0026_portion_factor.sql — a usual portion per person (exec plan 0027, front
-- P; board section "A usual portion per person", owner rulings P-D1/D3/D6).
--
-- "My wife eats ¾ what I do" is a fact about a person, not about Tuesday's
-- curry, so it lives on `household_member`: a usual portion as a multiple of
-- one recipe serving. The app spends it wherever a head-count was spent —
-- demand = Σ factors of an entry's eaters (the whole-number `plan_entry.
-- portions` override still wins), the cook plan's batch math, the shopping
-- list's scale, the per-person macro lens. Additive and row-preserving
-- (docs/cloud-setup.md §2c): every existing member reads `1`, which is exactly
-- what the head-count always meant, so no number anywhere changes until
-- someone taps (P-D6).
--
-- The range check is the segment's (P-D2): ×½ · ×¾ · ×1 · ×1¼ · ×1½ and a
-- custom value in quarter steps from ¼ to 3. The step itself is the app's
-- rule (`isValidPortionFactor`); the column refuses only what no segment
-- could produce.

alter table household_member
  add column portion_factor numeric(4,2) not null default 1
    constraint household_member_portion_factor_range
    check (portion_factor >= 0.25 and portion_factor <= 3);

comment on column household_member.portion_factor is
  'The person''s usual portion as a multiple of one recipe serving (plan 0027 '
  'P-D1). Demand for a planned meal = Σ of its eaters'' factors unless the '
  'entry''s whole-number portions override is set. Quarter steps, 0.25–3.';

-- P-D3: set from the Household sheet, and either member may set either's.
-- The client had never written a member row — 0001 ships a read policy and
-- a `select` grant only — so this is the one UPDATE door it gains: scoped to
-- the caller's household by the same `current_household_id()` anchor every
-- table uses, and column-narrow. The connector PATCHes exactly the columns a
-- local UPDATE touched (`portion_factor`, `updated_at`), so those two are
-- granted and nothing else: `display_name` and `auth_user_id` stay
-- server-owned.
create policy household_member_update on household_member
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

grant update (portion_factor, updated_at) on household_member to authenticated;
