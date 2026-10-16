import 'dart:async';

import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../models/alarm.dart';
import '../services/alarm_repository.dart';
import '../services/app_settings.dart';
import '../services/native_bridge.dart';
import '../services/next_occurrence.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import 'alarm_edit_screen.dart';

/// Main screen: Alarmy-style alarm cards with countdown, 12-hour time,
/// colorful icons and lime-green accents.
class AlarmListScreen extends StatefulWidget {
  final AlarmRepository repo;
  final AppSettings settings;

  const AlarmListScreen({super.key, required this.repo, required this.settings});

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen>
    with WidgetsBindingObserver {
  /// Pending snooze triggers (alarm id -> trigger time), refreshed from
  /// native. Used to show an accurate countdown while an alarm is snoozed.
  final Map<int, DateTime> _snoozeTriggers = {};
  // v2.23: snooze count per alarm for the "N left" badge text.
  final Map<int, int> _snoozeCounts = {};

  /// Periodic timer to keep countdowns fresh (and pick up snooze triggers
  /// set from the full-screen activity or in-app dialog).
  Timer? _refreshTimer;

  /// v2.24: last time the app came back to the foreground. A snooze issued
  /// from the native full-screen activity lands right before a resume, so
  /// if a refresh right after a resume finds no triggers, retry once —
  /// the native persist may still have been in flight.
  DateTime? _lastResumedAt;

  /// v2.17: true when the full-screen-intent permission is needed but not
  /// granted — shows a prominent banner that opens the settings page.
  bool _showFsBanner = false;

  /// v2.22: true on ColorOS/Realme devices — shows a persistent banner
  /// reminding the user to enable "Show on Lock screen" in
  /// Settings → Apps → AlarmHQ. Cannot be checked via API, so it stays
  /// visible on ColorOS (the toggle is off by default and the app can
  /// never turn it on itself).
  bool _showLockBanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSnoozeTriggers();
    _checkFsPermission();
    _checkColorOs();
    // Refresh every 30s so "Rings in Xm" never goes stale.
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refreshSnoozeTriggers();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lastResumedAt = DateTime.now();
      _refreshSnoozeTriggers();
      _checkFsPermission();
    }
  }

  /// v2.17: show the full-screen-permission banner when it's needed
  /// (Android 14+) but not granted.
  Future<void> _checkFsPermission() async {
    try {
      final needs = await NativeBridge.needsFullScreenIntentCard();
      final granted =
          needs ? await NativeBridge.canUseFullScreenIntent() : true;
      if (mounted) setState(() => _showFsBanner = needs && !granted);
    } catch (_) {
      // Best effort only.
    }
  }

  /// v2.22: ColorOS devices need the "Show on Lock screen" toggle flipped
  /// manually in Settings → Apps → AlarmHQ. The app cannot check or set
  /// it, so the banner stays up on ColorOS as a persistent reminder.
  Future<void> _checkColorOs() async {
    try {
      final isColorOs = await NativeBridge.isColorOsDevice();
      if (mounted) setState(() => _showLockBanner = isColorOs);
    } catch (_) {
      // Best effort only.
    }
  }

  /// Query native for pending snooze triggers (e.g. after returning from
  /// the full-screen alarm where the user may have snoozed).
  /// v2.24: if no triggers are found within 5s of an app resume, retry
  /// once after 500ms — the native persist may still be in flight.
  Future<void> _refreshSnoozeTriggers({bool retried = false}) async {
    final map = <int, DateTime>{};
    final counts = <int, int>{};
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final a in widget.repo.alarms) {
      try {
        final ms = await NativeBridge.getSnoozeTrigger(a.id);
        // v2.23: diagnostic — the user reported the badge never shows.
        // ignore: avoid_print
        print('AlarmHQ snoozeCheck(id=${a.id}): trigger=$ms now=$nowMs');
        if (ms != null && ms > nowMs) {
          map[a.id] = DateTime.fromMillisecondsSinceEpoch(ms);
          try {
            counts[a.id] = await NativeBridge.getSnoozeCount(a.id);
          } catch (_) {
            // Best effort only.
          }
          continue;
        }
      } catch (_) {
        // Best effort: a missing trigger just falls back to normal countdown.
      }
      // v2.21: Dart-prefs backup (mirrored by native scheduleSnooze) —
      // belt and suspenders if the native read ever misses.
      bool found = false;
      try {
        final backup =
            await PrefsService.getString('dart_snooze_trigger_${a.id}');
        final bms = int.tryParse(backup ?? '');
        if (bms != null && bms > nowMs) {
          map[a.id] = DateTime.fromMillisecondsSinceEpoch(bms);
          found = true;
        }
      } catch (_) {
        // Best effort only.
      }
      // v2.26: final fallback — ask native to read the snooze_trigger_$id
      // key directly from the "alarmhq_prefs" backup file. If that also
      // misses, log the queried id so a logcat shows the dead end.
      if (!found) {
        try {
          final fb = await NativeBridge.getSnoozeTriggerBackup(a.id);
          if (fb != null && fb > nowMs) {
            map[a.id] = DateTime.fromMillisecondsSinceEpoch(fb);
            found = true;
            // ignore: avoid_print
            print('AlarmHQ snoozeCheck(id=${a.id}): fallback HIT trigger=$fb');
          } else {
            // ignore: avoid_print
            print('AlarmHQ snoozeCheck(id=${a.id}): NO trigger found '
                '(native=null, prefsBackup=null, directBackup=$fb)');
          }
        } catch (_) {
          // Best effort only.
        }
      }
      // v2.26: fetch the snooze count whenever any path found a trigger,
      // so the "N left" badge text is accurate.
      if (found && !counts.containsKey(a.id)) {
        try {
          counts[a.id] = await NativeBridge.getSnoozeCount(a.id);
        } catch (_) {
          // Best effort only.
        }
      }
    }
    if (mounted) {
      setState(() {
        _snoozeTriggers
          ..clear()
          ..addAll(map);
        _snoozeCounts
          ..clear()
          ..addAll(counts);
      });
    }
    // v2.24: one retry shortly after a resume, when a native snooze write
    // may still be in flight.
    if (!retried && map.isEmpty && _lastResumedAt != null) {
      final sinceResume =
          DateTime.now().difference(_lastResumedAt!).inSeconds;
      if (sinceResume < 5) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) await _refreshSnoozeTriggers(retried: true);
      }
    }
  }
  Future<void> _openEditor({AlarmModel? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AlarmEditScreen(
          repo: widget.repo,
          settings: widget.settings,
          existing: existing,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  /// Delete confirmation (long-press on card).
  Future<void> _confirmDelete(AlarmModel alarm) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.deleteAlarmTitle),
        content: Text(l10n.deleteAlarmBody(alarm.label.isEmpty
            ? _timeText12(alarm.hour, alarm.minute)
            : alarm.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.confirmDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.remove(alarm.id);
      if (mounted) setState(() {});
    }
  }

  /// Toggle-off dialog: "Skip next only" vs "Turn off completely".
  Future<void> _confirmTurnOff(AlarmModel alarm) async {
    final l10n = AppLocalizations.of(context)!;
    final next = NextOccurrence.nextTrigger(alarm, DateTime.now());
    final when = next == null
        ? ''
        : '${next.day}/${next.month} ${_timeText12(next.hour, next.minute)}';
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.turnOffAlarmTitle),
        content: Text(l10n.turnOffAlarmBody(
          alarm.label.isEmpty ? _timeText12(alarm.hour, alarm.minute) : alarm.label,
          when,
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'skip'),
            child: Text(l10n.skipNextOnly,
                style: const TextStyle(color: AppTheme.emerald)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(c, 'off'),
            child: Text(l10n.turnOffCompletely),
          ),
        ],
      ),
    );
    if (choice == 'off') {
      await widget.repo.setEnabled(alarm, false);
    } else if (choice == 'skip') {
      await widget.repo.skipNext(alarm);
    }
    if (mounted) setState(() {});
  }

  /// 12-hour "6:32 PM" text.
  String _timeText12(int hour24, int minute) {
    final ampm = hour24 < 12 ? 'AM' : 'PM';
    var h = hour24 % 12;
    if (h == 0) h = 12;
    return '$h:${minute.toString().padLeft(2, '0')} $ampm';
  }

  /// "6:32" and "PM" separately for styled display.
  (String, String) _timeParts(int hour24, int minute) {
    final ampm = hour24 < 12 ? 'AM' : 'PM';
    var h = hour24 % 12;
    if (h == 0) h = 12;
    return ('$h:${minute.toString().padLeft(2, '0')}', ampm);
  }

  String _repeatSummary(AppLocalizations l10n, AlarmModel a) {
    switch (a.mode) {
      case AlarmRepeatMode.once:
        return l10n.onceSummary;
      case AlarmRepeatMode.interval:
        return l10n.everyNDaysSummary(a.intervalDays);
      case AlarmRepeatMode.specificDates:
        return l10n.repeatSpecificDates;
      case AlarmRepeatMode.weekly:
        final names = [
          l10n.weekdayMon,
          l10n.weekdayTue,
          l10n.weekdayWed,
          l10n.weekdayThu,
          l10n.weekdayFri,
          l10n.weekdaySat,
          l10n.weekdaySun,
        ];
        final days = a.weekDays.map((w) => names[w - 1]).join(' · ');
        return l10n.weeklySummary(days);
      case AlarmRepeatMode.cycle:
        return l10n.cycleSummary(a.ringDays, a.skipDays);
    }
  }

  /// "Rings in 2d 14h 22m" countdown text, or empty when none.
  /// While an alarm is snoozed, shows the time until the snooze fires.
  String _countdownText(AppLocalizations l10n, AlarmModel a) {
    if (!a.enabled) return '';
    // v2.4: a pending snooze trigger takes precedence over the regular
    // schedule, so "Rings in 10m" is accurate after snoozing.
    final snoozed = _snoozeTriggers[a.id];
    final next = snoozed ?? NextOccurrence.nextTrigger(a, DateTime.now());
    if (next == null) return '';
    final diff = next.difference(DateTime.now());
    if (diff.isNegative) return '';
    final d = diff.inDays;
    final h = diff.inHours % 24;
    final m = diff.inMinutes % 60;
    String dur;
    if (d > 0) {
      dur = '${d}d ${h}h ${m}m';
    } else if (h > 0) {
      dur = '${h}h ${m}m';
    } else {
      dur = '${m}m';
    }
    return l10n.ringsIn(dur);
  }

  String _nextLine(AppLocalizations l10n, AlarmModel a) {
    if (!a.enabled) return l10n.alarmOff;
    final snoozed = _snoozeTriggers[a.id];
    final next = snoozed ?? NextOccurrence.nextTrigger(a, DateTime.now());
    if (next == null) return l10n.disabled;
    return l10n.nextRing(
        '${next.day}/${next.month} ${_timeText12(next.hour, next.minute)}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final alarms = widget.repo.alarms;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⏰ '),
            Text(l10n.alarms),
          ],
        ),
      ),
      body: Column(
        children: [
          // v2.17: prominent banner when the full-screen permission is off —
          // without it the alarm can't pop up on the lock screen.
          if (_showFsBanner)            Padding(
              padding:
                  const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await NativeBridge.openFullScreenIntentSettings();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2222),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.redAccent, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Text('⚠️',
                          style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.fsBannerTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.fsBannerBody,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.redAccent),
                    ],
                  ),
                ),
              ),
            ),
          // v2.22: persistent ColorOS reminder — "Show on Lock screen"
          // lives in Settings → Apps → AlarmHQ and is OFF by default.
          // The app can't check or flip it, so the banner stays up.
          if (_showLockBanner)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await NativeBridge.openAppDetailsSettings();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2222),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: Colors.redAccent, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Text('⚠️',
                          style: TextStyle(fontSize: 26)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.lockBannerTitle,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.lockBannerBody,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Colors.redAccent),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: alarms.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⏰',
                              style: TextStyle(fontSize: 64)),
                          const SizedBox(height: 16),
                          Text(l10n.noAlarms,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge),
                          const SizedBox(height: 8),
                          Text(l10n.noAlarmsHint,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    itemCount: alarms.length,
                    itemBuilder: (c, i) {
                      final a = alarms[i];
                      return _alarmCard(context, l10n, a);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.addAlarm,
        backgroundColor: AppTheme.emerald,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  Widget _alarmCard(
      BuildContext context, AppLocalizations l10n, AlarmModel a) {
    final (time, ampm) = _timeParts(a.hour, a.minute);
    final countdown = _countdownText(l10n, a);
    final dimmed = !a.enabled;
    // v2.17: when snoozed, show it prominently — the user couldn't tell
    // the alarm was snoozed from the card.
    final snoozedUntil = _snoozeTriggers[a.id];
    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.charcoalCard,
          borderRadius: BorderRadius.circular(18),
          border: Border(
            left: BorderSide(
              color: a.enabled ? AppTheme.emerald : Colors.white24,
              width: 4,
            ),
          ),
          boxShadow: a.enabled
              ? [
                  BoxShadow(
                    color: AppTheme.emerald.withAlpha(40),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _openEditor(existing: a),
          onLongPress: () => _confirmDelete(a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: time,
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            TextSpan(
                              text: ' $ampm',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.emerald,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (a.label.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(a.label,
                            style: const TextStyle(
                                fontSize: 14, color: Colors.white70)),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: a.enabled
                              ? AppTheme.emerald
                              : Colors.white12,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _repeatSummary(l10n, a),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: a.enabled ? Colors.black : Colors.white60,
                          ),
                        ),
                      ),
                      if (countdown.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          '⏳ $countdown',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.emerald,
                          ),
                        ),
                      ],
                      // v2.17: prominent snoozed indicator.
                      // v2.23: also show how many snoozes are left.
                      if (snoozedUntil != null && a.enabled) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.emerald.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color:
                                  AppTheme.emerald.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Builder(
                            builder: (context) {
                              final used = _snoozeCounts[a.id] ?? 0;
                              final max = a.maxSnoozes;
                              final timeStr = _timeText12(snoozedUntil.hour,
                                  snoozedUntil.minute);
                              final text = (max < 0 || max == 0)
                                  ? l10n.snoozedUntil(timeStr)
                                  : l10n.snoozedUntilLeft(
                                      (max - used).clamp(0, max).toString(),
                                      timeStr);
                              return Text(
                                '⏰ $text',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.emerald,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _nextLine(l10n, a),
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: a.enabled,
                  activeThumbColor: AppTheme.emerald,
                  onChanged: (v) async {
                    if (v) {
                      await widget.repo.setEnabled(a, true);
                      if (mounted) setState(() {});
                    } else {
                      await _confirmTurnOff(a);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
