/// The fold is a per-device viewing preference (Library v2 / D3), so what
/// pins it is the prefs round-trip and the "absent means expanded" default.
library;

import 'package:ansi/core/sync/device_prefs.dart';
import 'package:ansi/features/books/data/shared_prefs_book_collapse_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a book with no key is expanded', () async {
    final store = SharedPrefsBookCollapseStore();
    expect(await store.read(), isEmpty);
  });

  test('a fold survives a new store (the relaunch this buys)', () async {
    await SharedPrefsBookCollapseStore().write('b1', collapsed: true);

    expect(await SharedPrefsBookCollapseStore().read(), {'b1'});
  });

  test('opening a book removes the key rather than storing false', () async {
    final store = SharedPrefsBookCollapseStore();
    await store.write('b1', collapsed: true);
    await store.write('b1', collapsed: false);

    expect(await store.read(), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    // Expanded is the default, so nothing accumulates for books you only open.
    expect(
      prefs.getKeys().where(
        (k) => k.startsWith(DevicePrefs.bookCollapsedPrefix),
      ),
      isEmpty,
    );
  });

  test(
    'folds are namespaced, so an unrelated key is not read as one',
    () async {
      SharedPreferences.setMockInitialValues({
        '${DevicePrefs.householdIdPrefix}user-1': 'household-1',
        '${DevicePrefs.bookCollapsedPrefix}b1': true,
      });

      expect(await SharedPrefsBookCollapseStore().read(), {'b1'});
    },
  );
}
