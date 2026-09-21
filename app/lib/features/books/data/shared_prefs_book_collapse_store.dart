/// [BookCollapseStore] over [SharedPreferences]: one prefixed key per folded
/// book, swept on sign-out with [DevicePrefs.sweptOnSignOut].
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/sync/device_prefs.dart';
import '../domain/book_collapse_store.dart';

class SharedPrefsBookCollapseStore implements BookCollapseStore {
  static const _prefix = DevicePrefs.bookCollapsedPrefix;

  @override
  Future<Set<String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in prefs.getKeys())
        if (key.startsWith(_prefix) && (prefs.getBool(key) ?? false))
          key.substring(_prefix.length),
    };
  }

  @override
  Future<void> write(String bookId, {required bool collapsed}) async {
    final prefs = await SharedPreferences.getInstance();
    // Expanded is stored as the absence of a key.
    if (collapsed) {
      await prefs.setBool('$_prefix$bookId', true);
    } else {
      await prefs.remove('$_prefix$bookId');
    }
  }
}
