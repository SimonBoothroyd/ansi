/// The phone's Health Connect, as Ansi uses it: write-only. Pure Dart.
library;

import 'health_meal.dart';

/// Whether Health Connect can be used on this phone at all.
enum HealthAvailability {
  /// Installed and ready.
  available,

  /// Present but needs an update from the Play Store first.
  needsUpdate,

  /// Not on this phone (or not Android).
  unavailable,
}

abstract interface class HealthGateway {
  Future<HealthAvailability> availability();

  /// Whether Ansi may write nutrition.
  Future<bool> canWrite();

  /// Asks for permission to write nutrition; true when granted.
  Future<bool> requestWrite();

  /// Writes [meals], each replacing the record with its id.
  Future<void> write(List<HealthMeal> meals);

  /// Takes back the records with these ids.
  Future<void> delete(List<String> ids);

  /// Opens Health Connect's own page for Ansi, where its data can be deleted.
  Future<void> openSettings();
}

/// What this phone remembers about Health Connect: whether it is switched on,
/// and what it last sent (`record id → contentKey`). Never synced.
abstract interface class HealthSendLog {
  Future<bool> enabled();
  Future<void> setEnabled({required bool on});
  Future<Map<String, String>> sent();
  Future<void> setSent(Map<String, String> sent);
}
