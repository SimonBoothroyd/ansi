-- 0004_books.sql — recipe books + user-defined sections (roadmap step 3).
--
-- A `book` is a named collection of recipes ("Our Cookbook"). Within a book,
-- recipes are grouped under `book_section`s the user names freely ("Weeknight",
-- "Slow Sundays") — NOT a fixed preset enum (spec §3). Sections are their own
-- rows, not a label on the recipe, so they carry `sort_order` (reorder), rename
-- in one place, and can exist empty — matching the design board's ordered
-- sections and "+ new section, name it anything" affordance.
--
-- A recipe lives in one book (v1 assumption; multi-book many-to-many stays an
-- open question, spec §8). `recipe.book_id` / `recipe.section_id` are added here
-- as NULLABLE FKs: step 2 (0003) deliberately left them out to avoid a dangling
-- FK before this table existed. A recipe with a null `section_id` renders under
-- an "Unsectioned" bucket the client synthesises (no row needed).
--
-- Still LOCAL-ONLY (no `.connect()` yet — sync is step 7). Like 0003, the RLS /
-- grants / publication below are authored now so Postgres and the client
-- `schema.dart` stay in lockstep and step 7 only has to call `.connect()`.

create table book (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  name          text not null,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz          -- soft-delete tombstone (spec §3)
);

-- A user-named section within a book ("Weeknight"). sort_order gives a stable
-- display order that survives last-write-wins field edits.
create table book_section (
  id            uuid primary key default gen_random_uuid(),
  household_id  uuid not null references household(id),
  book_id       uuid not null references book(id) on delete cascade,
  name          text not null,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

-- Place a recipe in a book + section. Both nullable: a recipe with no section
-- falls under the client's synthetic "Unsectioned" bucket, and a soft-deleted
-- section leaves its recipes there too (the library join filters deleted rows).
alter table recipe add column book_id    uuid references book(id);
alter table recipe add column section_id uuid references book_section(id);

-- Foreign-key lookup indexes.
create index book_household_idx         on book (household_id);
create index book_section_book_idx      on book_section (book_id);
create index book_section_household_idx on book_section (household_id);
create index recipe_book_idx            on recipe (book_id);
create index recipe_section_idx         on recipe (section_id);

-- RLS: household-scoped read/write; deletes are soft, so no delete policy
-- (same shape as 0001/0002/0003).
alter table book enable row level security;
alter table book_section enable row level security;

create policy book_read on book
  for select using (household_id = current_household_id());
create policy book_write on book
  for insert with check (household_id = current_household_id());
create policy book_update on book
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

create policy book_section_read on book_section
  for select using (household_id = current_household_id());
create policy book_section_write on book_section
  for insert with check (household_id = current_household_id());
create policy book_section_update on book_section
  for update using (household_id = current_household_id())
  with check (household_id = current_household_id());

-- Table privileges mirror the policies (no DELETE — soft delete). service_role
-- (edge functions, seed) bypasses RLS.
grant select, insert, update on book to authenticated;
grant select, insert, update on book_section to authenticated;
grant all on book, book_section to service_role;

-- Sync these down with the household's data (bucket wiring lands in step 7's
-- powersync.yaml). The new `recipe` columns publish automatically with the
-- table, already a publication member from 0003.
alter publication powersync add table book, book_section;
