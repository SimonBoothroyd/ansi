/// [HealthSendLog] over this phone's `SharedPreferences`.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/sync/device_prefs.dart';
import '../domain/health_gateway.dart';

class PrefsHealthSendLog implements HealthSendLog {
  const PrefsHealthSendLog();

  static const _enabled = '${DevicePrefs.healthPrefix}enabled';
  static const _sent = '${DevicePrefs.healthPrefix}sent';

  @override
  Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(_enabled) ?? false;

  @override
  Future<void> setEnabled({required bool on}) async =>
      (await SharedPreferences.getInstance()).setBool(_enabled, on);

  @override
  Future<Map<String, String>> sent() async {
    final raw = (await SharedPreferences.getInstance()).getString(_sent);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> setSent(Map<String, String> sent) async =>
      (await SharedPreferences.getInstance()).setString(
        _sent,
        jsonEncode(sent),
      );
}
