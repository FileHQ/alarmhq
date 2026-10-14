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

  /// Play a short audible tick (native ToneGenerator) for the time picker.
  static Future<void> playTick() async =>
      await _alarm.invokeMethod('playTick');

  static Future<bool> hasNotificationPermission() async =>
      await _alarm.invokeMethod<bool>('hasNotificationPermission') ?? false;

  /// Shows the one-tap system permission dialog (Android 13+).
  /// Returns true when granted.
  static Future<bool> requestNotificationPermission() async =>
      await _alarm.invokeMethod<bool>('requestNotificationPermission') ??
      false;

  static Future<void> openNotificationSettings() async =>
      await _alarm.invokeMethod('openNotificationSettings');

  static Future<bool> canDrawOverlays() async =>
      await _alarm.invokeMethod<bool>('canDrawOverlays') ?? false;

  static Future<void> openOverlaySettings() async =>
      await _alarm.invokeMethod('openOverlaySettings');

  /// Android 14+: USE_FULL_SCREEN_INTENT must be granted or the alarm
  /// won't appear on the lock screen (v2.11, critical).
  static Future<bool> canUseFullScreenIntent() async =>
      await _alarm.invokeMethod<bool>('canUseFullScreenIntent') ?? true;

  /// True only on Android 14+ where the user must grant the above.
  static Future<bool> needsFullScreenIntentCard() async =>
      await _alarm.invokeMethod<bool>('needsFullScreenIntentCard') ?? false;

  static Future<void> openFullScreenIntentSettings() async =>
      await _alarm.invokeMethod('openFullScreenIntentSettings');

  /// Open the manufacturer's autostart settings (Xiaomi/Oppo/Vivo/Huawei).
  /// No API exists to check this permission; it never blocks Continue.
  static Future<void> openAutostartSettings() async =>
      await _alarm.invokeMethod('openAutostartSettings');

  /// Device manufacturer (e.g. "realme", "Xiaomi") — v2.10.
  static Future<String> getManufacturer() async =>
      (await _alarm.invokeMethod<String>('getManufacturer')) ?? '';

  // ---- in-app ringing dialog support ----

  /// True while AlarmService is currently sounding an alarm.
  static Future<bool> isAlarmRinging() async =>
      await _alarm.invokeMethod<bool>('isAlarmRinging') ?? false;

  /// {'alarmJson': String, 'snoozeCount': int} or null when not ringing.
  static Future<Map<String, dynamic>?> getRingingAlarm() async {
    final m = await _alarm.invokeMethod<Map>('getRingingAlarm');
    if (m == null) return null;
    return {
      'alarmJson': m['alarmJson'] as String,
      'snoozeCount': (m['snoozeCount'] as num).toInt(),
    };
  }

  /// Stop the currently-ringing alarm sound.
  static Future<bool> dismissAlarm() async =>
      await _alarm.invokeMethod<bool>('dismissAlarm') ?? false;

  /// Snooze the currently-ringing alarm. Returns false when no snoozes left.
  static Future<bool> snoozeAlarm() async =>
      await _alarm.invokeMethod<bool>('snoozeAlarm') ?? false;

  /// Epoch-ms of a pending snooze trigger for alarm [id], or null when none.
  /// Used to show an accurate "Rings in Xm" countdown while snoozed.
  static Future<int?> getSnoozeTrigger(int id) async =>
      await _alarm.invokeMethod<int>('getSnoozeTrigger', {'id': id});
}
