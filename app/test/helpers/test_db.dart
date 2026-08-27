/// An in-process SQLite database for repository tests.
///
/// Mirrors the columns the local PowerSync schema (`core/sync/schema.dart`)
/// declares — including the implicit `id` TEXT primary key PowerSync adds — so
/// the repositories' SQL runs against the same shape they see on-device.
library;

import 'dart:io';

import 'package:sqlite_async/sqlite_async.dart';

/// Opens a fresh temp-file database with the step-2 tables created. Returns the
/// db and its temp dir; call [closeTestDb] to dispose both.
Future<(SqliteDatabase, Directory)> openTestDb() async {
  final dir = Directory.systemTemp.createTempSync('mise_test');
  final db = SqliteDatabase(path: '${dir.path}/test.db');
  await db.initialize();

  await db.execute('''
    CREATE TABLE book (
      id TEXT PRIMARY KEY, household_id TEXT, name TEXT, sort_order INTEGER,
      created_at TEXT, updated_at TEXT, deleted_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE book_section (
      id TEXT PRIMARY KEY, household_id TEXT, book_id TEXT, name TEXT,
      sort_order INTEGER, created_at TEXT, updated_at TEXT, deleted_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE recipe (
      id TEXT PRIMARY KEY, household_id TEXT, title TEXT, servings_base REAL,
      steps TEXT, keeps_for_days INTEGER, freezable INTEGER, freezer_days INTEGER,
      book_id TEXT, section_id TEXT,
      created_at TEXT, updated_at TEXT, deleted_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE ingredient_group (
      id TEXT PRIMARY KEY, household_id TEXT, recipe_id TEXT, name TEXT,
      sort_order INTEGER, created_at TEXT, updated_at TEXT, deleted_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE recipe_line_item (
      id TEXT PRIMARY KEY, household_id TEXT, group_id TEXT, ingredient_id TEXT,
      quantity REAL, unit TEXT, note TEXT, sort_order INTEGER,
      created_at TEXT, updated_at TEXT, deleted_at TEXT
    )''');
  await db.execute('''
    CREATE TABLE ingredient (
      id TEXT PRIMARY KEY, household_id TEXT, canonical_name TEXT, category TEXT,
      default_unit TEXT, density_g_per_ml REAL, status TEXT, source TEXT,
      match_text TEXT
    )''');
  await db.execute('''
    CREATE TABLE ingredient_alias (
      id TEXT PRIMARY KEY, ingredient_id TEXT, alias_text TEXT, match_text TEXT
    )''');

  return (db, dir);
}

Future<void> closeTestDb(SqliteDatabase db, Directory dir) async {
  await db.close();
  dir.deleteSync(recursive: true);
}
