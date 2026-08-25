/// PowerSync client-side schema (the local SQLite mirror).
///
// TODO(step-7): declare tables mirroring the synced Supabase tables
/// (household, household_member, ingredient, ingredient_alias, recipe, …).
/// Only resolved/human-readable data syncs to the device (ADR-0004/0005):
/// `usda_food` and match indexes stay server-side and are NOT declared here.
library;

// import 'package:powersync/powersync.dart';
//
// final schema = Schema([
//   // Table('ingredient', [Column.text('canonical_name'), ...]),
// ]);
