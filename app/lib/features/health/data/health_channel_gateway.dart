/// [HealthGateway] over the Android bridge in `MainActivity.kt`, which speaks
/// to Health Connect through Google's own client. Android only; everywhere
/// else Health Connect is [HealthAvailability.unavailable].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/health_gateway.dart';
import '../domain/health_meal.dart';

/// Whether this build can talk to Health Connect at all.
bool get healthSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class ChannelHealthGateway implements HealthGateway {
  const ChannelHealthGateway();

  static const _channel = MethodChannel('io.ansi.app/health');

  @override
  Future<HealthAvailability> availability() async {
    if (!healthSupported) return HealthAvailability.unavailable;
    return switch (await _channel.invokeMethod<String>('availability')) {
      'available' => HealthAvailability.available,
      'needs_update' => HealthAvailability.needsUpdate,
      _ => HealthAvailability.unavailable,
    };
  }

  @override
  Future<bool> canWrite() async =>
      healthSupported &&
      (await _channel.invokeMethod<bool>('canWrite') ?? false);

  @override
  Future<bool> requestWrite() async =>
      healthSupported &&
      (await _channel.invokeMethod<bool>('requestWrite') ?? false);

  @override
  Future<void> write(List<HealthMeal> meals) async {
    if (meals.isEmpty) return;
    // A version that only grows, so Health Connect replaces the record.
    final version = DateTime.now().millisecondsSinceEpoch;
    await _channel.invokeMethod<void>('write', [
      for (final m in meals)
        {
          'id': m.id,
          'version': version,
          'name': m.name,
          'at': m.at.millisecondsSinceEpoch,
          'mealType': m.mealType.name,
          'kcal': m.macros.kcal,
          'protein': m.macros.protein,
          'carb': m.macros.carb,
          'fat': m.macros.fat,
          if (m.macros.fiber != null) 'fiber': m.macros.fiber,
        },
    ]);
  }

  @override
  Future<void> delete(List<String> ids) async {
    if (ids.isEmpty) return;
    await _channel.invokeMethod<void>('delete', ids);
  }

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');
}
