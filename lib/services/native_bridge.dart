import 'dart:convert';

import 'package:flutter/services.dart';

/// Calls into the hand-written native Android layer
/// (android/app/src/main/kotlin/com/technoon/alarmhq/*.kt).
class NativeBridge {
  static const MethodChannel _alarm =
      MethodChannel('com.technoon.alarmhq/alarm');

  /// Schedule [triggerAtMillis] (epoch ms, device-local) for alarm [id].
  /// [alarmJson] is the AlarmModel JSON string — the native side stores it so
  /// it can reschedule repeats and survive reboots without Dart running.
  static Future<bool> scheduleAlarm(
      int id, int triggerAtMillis, Map<String, dynamic> alarmJson) async {
    return await _alarm.invokeMethod<bool>('scheduleAlarm', {
          'id': id,
          'triggerAtMillis': triggerAtMillis,
          'alarmJson': jsonEncode(alarmJson),
        }) ??
        false;
  }

  static Future<bool> cancelAlarm(int id) async =>
      await _alarm.invokeMethod<bool>('cancelAlarm', {'id': id}) ?? false;

  static Future<bool> cancelAllAlarms() async =>
      await _alarm.invokeMethod<bool>('cancelAllAlarms') ?? false;

  static Future<bool> hasExactAlarmPermission() async =>
      await _alarm.invokeMethod<bool>('hasExactAlarmPermission') ?? false;

  static Future<void> openExactAlarmSettings() async =>
      await _alarm.invokeMethod('openExactAlarmSettings');

  static Future<bool> isIgnoringBatteryOptimizations() async =>
      await _alarm.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
      false;

  static Future<void> openBatteryOptimizationSettings() async =>
      await _alarm.invokeMethod('openBatteryOptimizationSettings');

  /// Returns a content:// URI string, or null when the user cancels.
  static Future<String?> pickAudioFile() async =>
      await _alarm.invokeMethod<String>('pickAudioFile');

  static Future<String?> getSystemDefaultAlarmUri() async =>
      await _alarm.invokeMethod<String>('getSystemDefaultAlarmUri');

  /// Play [toneUri] once for preview at [volume] 0.0..1.0.
  static Future<void> playTonePreview(String toneUri, double volume) async =>
      await _alarm.invokeMethod('playTonePreview', {
        'toneUri': toneUri,
        'volume': volume,
      });

  static Future<void> stopTonePreview() async =>
      await _alarm.invokeMethod('stopTonePreview');

  /// Update the home-screen widget text (e.g. "Next: Fri 07:00").
  static Future<void> updateWidget(String text) async =>
      await _alarm.invokeMethod('updateWidget', {'text': text});
}
