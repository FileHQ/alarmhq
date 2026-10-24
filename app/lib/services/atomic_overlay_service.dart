import 'package:flutter/services.dart';
import 'package:system_alert_window/system_alert_window.dart';

/// v2.51: helpers for the floating atomic-clock overlay.
///
/// The overlay is shown on top of the system Date & Time settings so the
/// user can match the phone's clock to atomic (NTP) time by hand — Android
/// does not let a regular app change the system time directly.
class AtomicOverlayService {
  static const MethodChannel _alarm =
      MethodChannel('com.technoon.alarmhq/alarm');

  /// True when "Display over other apps" is granted.
  static Future<bool> ensurePermission() async {
    final granted = await SystemAlertWindow.checkPermissions(
      prefMode: SystemWindowPrefMode.OVERLAY,
    );
    if (granted == true) return true;
    final requested = await SystemAlertWindow.requestPermissions(
      prefMode: SystemWindowPrefMode.OVERLAY,
    );
    return requested == true;
  }

  /// Show the floating atomic clock (top of screen).
  /// The overlay UI is rendered by [overlayMain] in atomic_overlay.dart —
  /// note the native plugin hardcodes the entry-point name "overlayMain",
  /// which delegates to [atomicOverlayMain].
  static Future<bool> show() async {
    final ok = await SystemAlertWindow.showSystemWindow(
      gravity: SystemWindowGravity.TOP,
      // Full width, wrapped height — a slim bar under the status area.
      prefMode: SystemWindowPrefMode.OVERLAY,
      notificationTitle: 'AlarmHQ',
      notificationBody: 'Atomic clock overlay',
      layoutParamFlags: [SystemWindowFlags.FLAG_NOT_FOCUSABLE],
    );
    return ok == true;
  }

  /// Hide the floating atomic clock.
  static Future<bool> hide() async {
    final ok = await SystemAlertWindow.closeSystemWindow(
      prefMode: SystemWindowPrefMode.OVERLAY,
    );
    return ok == true;
  }

  /// Open the system Date & Time settings page.
  /// NOTE (Kotlin side): not yet implemented in native_bridge — needs
  /// `startActivity(Intent(Settings.ACTION_DATE_SETTINGS))` under the
  /// method name "openDateTimeSettings" on the com.technoon.alarmhq/alarm
  /// channel, following the existing open*Settings pattern.
  static Future<void> openDateTimeSettings() async {
    await _alarm.invokeMethod('openDateTimeSettings');
  }

  /// v2.66: Show atomic time as an ongoing notification (replaces overlay
  /// on Realme/ColorOS where system_alert_window doesn't work).
  static Future<bool> showAtomicTimeNotification(
      String timeText, String dateText) async {
    try {
      final ok = await _alarm.invokeMethod<bool>(
        'showAtomicTimeNotification',
        {'timeText': timeText, 'dateText': dateText},
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Hide the atomic time notification.
  static Future<void> hideAtomicTimeNotification() async {
    try {
      await _alarm.invokeMethod('hideAtomicTimeNotification');
    } catch (_) {
      // Best effort.
    }
  }
}
