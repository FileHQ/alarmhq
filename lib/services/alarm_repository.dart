import 'dart:convert';

import '../models/alarm.dart';
import 'native_bridge.dart';
import 'next_occurrence.dart';
import 'prefs_service.dart';

/// Owns the alarm list: persistence (via PrefsService) and keeping the
/// native scheduler in sync after every change.
class AlarmRepository {
  static const _alarmsKey = 'alarmhq_alarms_v1';
  static const _nextIdKey = 'alarmhq_next_id';

  List<AlarmModel> alarms = [];
  int _nextId = 1;

  Future<void> load() async {
    final raw = await PrefsService.getString(_alarmsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        alarms = list
            .map((e) => AlarmModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        alarms = [];
      }
    }
    final idRaw = await PrefsService.getString(_nextIdKey);
    _nextId = int.tryParse(idRaw ?? '') ?? 1;
    if (_nextId < 1) _nextId = 1;
  }

  Future<void> _save() async {
    await PrefsService.putString(
        _alarmsKey, jsonEncode(alarms.map((a) => a.toJson()).toList()));
    await PrefsService.putString(_nextIdKey, '$_nextId');
  }

  int _allocId() => _nextId++;

  /// Add a new alarm, persist, and schedule it natively. Returns the alarm.
  Future<AlarmModel> add(AlarmModel draft) async {
    final alarm = draft.copyWith(id: _allocId());
    alarms.add(alarm);
    alarms.sort(_byTime);
    await _save();
    await reschedule(alarm);
    await refreshWidget();
    return alarm;
  }

  Future<void> update(AlarmModel alarm) async {
    final i = alarms.indexWhere((a) => a.id == alarm.id);
    if (i < 0) return;
    alarms[i] = alarm;
    alarms.sort(_byTime);
    await _save();
    await reschedule(alarm);
    await refreshWidget();
  }

  Future<void> remove(int id) async {
    alarms.removeWhere((a) => a.id == id);
    await _save();
    await NativeBridge.cancelAlarm(id);
    await refreshWidget();
  }

  Future<void> setEnabled(AlarmModel alarm, bool enabled) async {
    await update(alarm.copyWith(enabled: enabled));
  }

  /// "Skip next only": record the upcoming trigger as skipped and reschedule
  /// to the following occurrence. The alarm stays enabled.
  Future<void> skipNext(AlarmModel alarm) async {
    final next = NextOccurrence.nextTrigger(alarm, DateTime.now());
    if (next == null) return;
    await update(alarm.copyWith(skipNextDate: () => next));
  }

  /// (Re)schedule one alarm natively from its next trigger.
  Future<void> reschedule(AlarmModel alarm) async {
    // v2.15: diagnostic logging to trace scheduling issues.
    // ignore: avoid_print
    print('AlarmHQ reschedule(id=${alarm.id}, enabled=${alarm.enabled})');
    await NativeBridge.cancelAlarm(alarm.id);
    if (!alarm.enabled) return;
    final next = NextOccurrence.nextTrigger(alarm, DateTime.now());
    if (next == null) {
      // ignore: avoid_print
      print('AlarmHQ reschedule(id=${alarm.id}): nextTrigger=null, not scheduling');
      // One-time alarm already fired (or weekly with no days): retire it in
      // the list too, so it doesn't linger as "enabled" forever.
      if (alarm.mode == AlarmRepeatMode.once) {
        final i = alarms.indexWhere((a) => a.id == alarm.id);
        if (i >= 0) {
          alarms[i] = alarm.copyWith(enabled: false);
          await _save();
        }
      }
      return;
    }
    // ignore: avoid_print
    print('AlarmHQ reschedule(id=${alarm.id}): scheduling for $next');
    final ok = await NativeBridge.scheduleAlarm(
      alarm.id,
      next.millisecondsSinceEpoch,
      alarm.toJson(),
    );
    // ignore: avoid_print
    print('AlarmHQ reschedule(id=${alarm.id}): native schedule result=$ok');
  }

  /// Recompute every native schedule (used after boot-prompt flows).
  Future<void> rescheduleAll() async {
    for (final a in alarms) {
      await reschedule(a);
    }
    await refreshWidget();
  }

  /// Push the nearest upcoming ring time to the home-screen widget.
  Future<void> refreshWidget() async {
    DateTime? best;
    final now = DateTime.now();
    for (final a in alarms) {
      if (!a.enabled) continue;
      final t = NextOccurrence.nextTrigger(a, now);
      if (t != null && (best == null || t.isBefore(best))) best = t;
    }
    if (best == null) {
      await NativeBridge.updateWidget('');
    } else {
      final hh = best.hour.toString().padLeft(2, '0');
      final mm = best.minute.toString().padLeft(2, '0');
      await NativeBridge.updateWidget('${_weekdayShort(best.weekday)} $hh:$mm');
    }
  }

  static int _byTime(AlarmModel a, AlarmModel b) {
    final c = a.hour.compareTo(b.hour);
    return c != 0 ? c : a.minute.compareTo(b.minute);
  }

  static String _weekdayShort(int w) =>
      const ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][w];
}
