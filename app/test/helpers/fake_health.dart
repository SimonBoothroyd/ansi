/// A fake phone for Health Connect, and a fake memory of what was sent.
library;

import 'package:ansi/features/health/domain/health_gateway.dart';
import 'package:ansi/features/health/domain/health_meal.dart';

class FakeHealthGateway implements HealthGateway {
  HealthAvailability available = HealthAvailability.available;
  bool granted = true;

  /// What a permission request answers.
  bool grantsOnRequest = true;
  int requests = 0;
  int settingsOpened = 0;
  final written = <HealthMeal>[];
  final deleted = <String>[];

  /// What Health Connect holds: a write replaces the record with its id, a
  /// delete removes it.
  final records = <String, HealthMeal>{};

  /// Record ids a write refuses, failing the whole call as Health Connect
  /// fails a whole batch.
  final refuses = <String>{};

  /// While true, every write fails, as when Health Connect cannot be reached.
  bool unreachable = false;

  @override
  Future<HealthAvailability> availability() async => available;

  @override
  Future<bool> canWrite() async => granted;

  @override
  Future<bool> requestWrite() async {
    requests++;
    return granted = grantsOnRequest;
  }

  @override
  Future<void> write(List<HealthMeal> meals) async {
    if (unreachable) throw Exception('Health Connect is not available');
    if (meals.any((m) => refuses.contains(m.id))) {
      throw Exception('a record was refused');
    }
    written.addAll(meals);
    for (final m in meals) {
      records[m.id] = m;
    }
  }

  @override
  Future<void> delete(List<String> ids) async {
    deleted.addAll(ids);
    ids.forEach(records.remove);
  }

  @override
  Future<void> openSettings() async => settingsOpened++;
}

class FakeHealthSendLog implements HealthSendLog {
  bool on = false;
  Map<String, String> log = {};

  @override
  Future<bool> enabled() async => on;

  @override
  Future<void> setEnabled({required bool on}) async => this.on = on;

  @override
  Future<Map<String, String>> sent() async => {...log};

  @override
  Future<void> setSent(Map<String, String> sent) async => log = {...sent};
}
