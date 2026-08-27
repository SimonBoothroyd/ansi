import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'app.dart';
import 'core/sync/database.dart';
import 'features/books/data/book_repository_impl.dart';
import 'features/ingredients/data/vocab_seeder.dart';
import 'features/planning/data/planning_repository_impl.dart';

/// Boots the app inside a guarded zone with a single [ProviderScope] root.
///
/// Step 2 opens the local PowerSync database and seeds the bundled ingredient
/// vocab before the first frame, then injects the open database into the
/// provider graph. No `.connect()` — sync is step 7.
void bootstrap() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final db = await openMiseDatabase();
      await VocabSeeder(db).ensureSeeded();
      // Ensure a default book exists and adopt any pre-step-3 recipes into it,
      // so the Library is never empty of books (step 3). Idempotent.
      await SqliteBookRepository(db).ensureDefaultBook();
      // Seed two local household members so meal eaters default to the whole
      // household (step 4). Local-only until step 7 syncs real members.
      await SqlitePlanningRepository(db).ensureMembers();
      runApp(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: const MiseApp(),
        ),
      );
    },
    (error, stack) {
      // TODO(observability): route to real error reporting.
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
