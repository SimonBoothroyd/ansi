/// The fixed local household used before real auth (Google OAuth) lands in
/// step 7. It matches the household seeded by `supabase/seed.sql`
/// (`00000000-0000-0000-0000-0000000000aa`, "Home"), so locally-created rows
/// carry the same `household_id` the server seed uses. All of this is throwaway
/// dev scaffolding — step 7 replaces it with the signed-in user's household.
library;

const kDevHouseholdId = '00000000-0000-0000-0000-0000000000aa';
