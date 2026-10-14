import 'package:flutter/services.dart';

/// String key-value storage backed by Android SharedPreferences through a
/// tiny hand-written platform channel (no third-party plugin needed).
class PrefsService {
  static const MethodChannel _prefs =
      MethodChannel('com.technoon.alarmhq/prefs');

  static Future<String?> getString(String key) async =>
      await _prefs.invokeMethod<String>('getString', {'key': key});

  static Future<bool> putString(String key, String value) async =>
      await _prefs.invokeMethod<bool>('putString', {
        'key': key,
        'value': value,
      }) ??
      false;

  static Future<bool> remove(String key) async =>
      await _prefs.invokeMethod<bool>('remove', {'key': key}) ?? false;
}
