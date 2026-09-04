-- seed_usda_index.sql — build the USDA search index (plan 0029).
--
-- Migrations run BEFORE seeds, so `usda_search_*` is created empty and stays
-- empty until seed_usda.sql has loaded the 8,204-row reference set. This runs
-- immediately after it, and must: `usda_probe()` raises rather than returning
-- a silently empty short-list when the index has never been built.
--
-- Re-run it after ANY change to usda_food. It truncates and rebuilds in well
-- under a second, so there is never a reason to skip it.
select usda_rebuild_search_index();
