import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../models/alarm.dart';
import '../services/native_bridge.dart';
import '../theme/app_theme.dart';

/// Full-screen in-app ringing dialog.
///
/// Shown when an alarm fires while the user is inside the app
/// (the native full-screen activity covers the lock-screen case).
/// Dismiss / Snooze actually stop the native [AlarmService].
///
/// v2.85: the dialog used to close ONLY via its own buttons
/// (barrierDismissible: false, canPop: false, no outside signal),
/// so stopping/snoozing from the NOTIFICATION left it stuck on
/// screen even though the sound had stopped. It now polls the
/// native ringing state and pops itself the moment ringing ends,
/// whatever stopped it.
class RingingOverlay extends StatefulWidget {
  const RingingOverlay({
    super.key,
    required this.alarm,
    required this.snoozeCount,
  });

  final AlarmModel alarm;
  final int snoozeCount;

  /// Checks the native side and shows the overlay when an alarm is ringing.
  /// Returns immediately when nothing is ringing.
  static Future<void> showIfRinging(BuildContext context) async {
    if (!context.mounted) return;
    final ringing = await NativeBridge.isAlarmRinging();
    if (!ringing || !context.mounted) return;
    final data = await NativeBridge.getRingingAlarm();
    if (data == null || !context.mounted) return;
    AlarmModel alarm;
    try {
      alarm = AlarmModel.fromJson(
          jsonDecode(data['alarmJson'] as String) as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RingingOverlay(
        alarm: alarm,
        snoozeCount: data['snoozeCount'] as int,
      ),
    );
  }

  @override
  State<RingingOverlay> createState() => _RingingOverlayState();
}

class _RingingOverlayState extends State<RingingOverlay> {
  Timer? _watchdog;

  @override
  void initState() {
    super.initState();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      final ringing = await NativeBridge.isAlarmRinging();
      if (!mounted) return;
      if (!ringing) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  AlarmModel get alarm => widget.alarm;
  int get snoozeCount => widget.snoozeCount;

  String _time12h() {
    final h12 = alarm.hour % 12 == 0 ? 12 : alarm.hour % 12;
    final mm = alarm.minute.toString().padLeft(2, '0');
    final ap = alarm.hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  Future<void> _dismiss(BuildContext context) async {
    // v2.88: never leave the dialog stuck on a native error — the
    // old code skipped pop() when dismissAlarm() threw.
    try {
      await NativeBridge.dismissAlarm();
    } catch (_) {
      // Sound path is the service's job; the dialog must still close.
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context) async {
    // v2.88: same stuck-dialog guard for a native snooze error
    // (the ok == false path below still stays + shows its note).
    bool ok;
    try {
      ok = await NativeBridge.snoozeAlarm();
    } catch (_) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }
    if (!context.mounted) return;
    if (!ok) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noMoreSnoozes)),
      );
      return;
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // maxSnoozes: 0 = no snooze, -1 = unlimited.
    final canSnooze = alarm.maxSnoozes != 0 &&
        (alarm.maxSnoozes < 0 || snoozeCount < alarm.maxSnoozes);
    final snoozeLabel = alarm.maxSnoozes > 0
        ? '${l10n.snooze} (${snoozeCount + 1}/${alarm.maxSnoozes})'
        : l10n.snooze;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.charcoal,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('⏰', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 24),
                Text(
                  l10n.alarmRinging,
                  style: const TextStyle(
                    color: AppTheme.emerald,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _time12h(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 72,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (alarm.label.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    alarm.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _dismiss(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.emerald,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      l10n.dismiss,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed:
                        canSnooze ? () => _snooze(context) : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.emerald,
                      side: const BorderSide(
                          color: AppTheme.emerald, width: 2),
                      padding:
                          const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      snoozeLabel,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
