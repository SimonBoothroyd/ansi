/// [CookTimerStore] over [SharedPreferences]: one JSON list under one key,
/// swept on sign-out with [DevicePrefs.sweptOnSignOut].
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/sync/device_prefs.dart';
import '../domain/cook_timer.dart';
import '../domain/timer_platform.dart';

class SharedPrefsCookTimerStore implements CookTimerStore {
  static const _key = '${DevicePrefs.cookTimersPrefix}v1';

  @override
  Future<List<CookTimer>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final json in jsonDecode(raw) as List<Object?>)
          CookTimer.fromJson((json! as Map).cast<String, Object?>()),
      ];
      // A list written by an older shape is dropped rather than half-read:
      // a timer that cannot say when it ends is not one.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      await prefs.remove(_key);
      return const [];
    }
  }

  @override
  Future<void> write(List<CookTimer> timers) async {
    final prefs = await SharedPreferences.getInstance();
    if (timers.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        jsonEncode([for (final t in timers) t.toJson()]),
      );
    }
  }
}
