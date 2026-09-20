-- pgTAP: the receipt door's recall, run for real (0047).
--
-- The statement below is a copy of RECALL_SQL in
-- `functions/_shared/receipt_memory.ts`, and `receipt_memory.test.ts` fails if
-- the two drift. The function runs it as service-role, where RLS narrows
-- nothing, so the household predicates are the whole fence — asserted here
-- with a second household holding the newest answer of all.
--
-- Run by `supabase test db`.

begin;
select plan(3);

prepare recall(uuid, text[]) as
  select distinct on (q.name)
         q.name as name,
         l.kind as kind,
         i.id::text as ingredient_id
  from unnest($2::text[]) as q(name)
  join receipt_line l
    on l.household_id = $1
   and l.deleted_at is null
   and l.kind in ('item', 'not_food')
   and upper(l.name_printed) = q.name
  left join ingredient i
    on i.id = l.ingredient_id
   and i.household_id = $1
   and i.deleted_at is null
  where l.kind = 'not_food' or i.id is not null
  order by q.name, l.updated_at desc, l.id desc;

insert into household (id, name) values
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','House A'),
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','House B');

insert into ingredient (id, household_id, canonical_name, default_unit, match_text) values
 ('aaaaaaaa-0000-0000-0000-000000000401','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Quinoa','g','quinoa'),
 ('aaaaaaaa-0000-0000-0000-000000000402','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Quinoa, Red','g','quinoa red'),
 ('bbbbbbbb-0000-0000-0000-000000000401','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Quinoa','g','quinoa');

insert into receipt (id, household_id, store, purchased_at, source) values
 ('aaaaaaaa-0000-0000-0000-000000000501','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','TJ''s','2026-09-13T17:20:00Z','photo'),
 ('bbbbbbbb-0000-0000-0000-000000000501','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','TJ''s','2026-09-13T17:20:00Z','photo');

insert into receipt_line
  (household_id, receipt_id, name_printed, kind, ingredient_id, cents,
   updated_at, deleted_at) values
 -- Said twice: the later answer wins.
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','ORG TRICOLOR QUINOA','item',
  'aaaaaaaa-0000-0000-0000-000000000401',449,'2026-09-01T00:00:00Z',null),
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','ORG TRICOLOR QUINOA','item',
  'aaaaaaaa-0000-0000-0000-000000000402',449,'2026-09-10T00:00:00Z',null),
 -- Matched once, folded later: the fold is the answer.
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','PAPER TOWELS','item',
  'aaaaaaaa-0000-0000-0000-000000000401',699,'2026-09-01T00:00:00Z',null),
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','PAPER TOWELS','not_food',
  null,699,'2026-09-10T00:00:00Z',null),
 -- Stored as the paper cased it; compared upper-cased.
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','Tj Hummus','item',
  'aaaaaaaa-0000-0000-0000-000000000401',399,'2026-09-01T00:00:00Z',null),
 -- A tombstoned line and a never-matched one are not answers.
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','TJ SRIRACHA','item',
  'aaaaaaaa-0000-0000-0000-000000000401',399,'2026-09-10T00:00:00Z',now()),
 ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-0000-0000-0000-000000000501','TJ SRIRACHA','item',
  null,399,'2026-09-11T00:00:00Z',null),
 -- House B said something newer about the same words.
 ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','bbbbbbbb-0000-0000-0000-000000000501','ORG TRICOLOR QUINOA','item',
  'bbbbbbbb-0000-0000-0000-000000000401',449,'2026-09-20T00:00:00Z',null);

select results_eq(
  $$ execute recall('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       array['ORG TRICOLOR QUINOA','PAPER TOWELS','TJ HUMMUS','TJ SRIRACHA',
             'NEVER SEEN']) $$,
  $$ values
     ('ORG TRICOLOR QUINOA'::text,'item'::text,
      'aaaaaaaa-0000-0000-0000-000000000402'::text),
     ('PAPER TOWELS','not_food',null),
     ('TJ HUMMUS','item','aaaaaaaa-0000-0000-0000-000000000401') $$,
  'the latest live answer per name, from this household alone'
);

select results_eq(
  $$ execute recall('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
       array['ORG TRICOLOR QUINOA','PAPER TOWELS']) $$,
  $$ values ('ORG TRICOLOR QUINOA'::text,'item'::text,
             'bbbbbbbb-0000-0000-0000-000000000401'::text) $$,
  'and the other household hears only its own'
);

update ingredient set deleted_at = now()
 where id = 'aaaaaaaa-0000-0000-0000-000000000402';

select results_eq(
  $$ execute recall('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       array['ORG TRICOLOR QUINOA']) $$,
  $$ values ('ORG TRICOLOR QUINOA'::text,'item'::text,
             'aaaaaaaa-0000-0000-0000-000000000401'::text) $$,
  'a retired row is no answer: the older one that still stands is used'
);

select finish();
rollback;
