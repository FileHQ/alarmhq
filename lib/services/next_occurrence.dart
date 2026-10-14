import '../models/alarm.dart';

/// Pure-Dart computation of the next ring time for an alarm.
/// The native Android scheduler (AlarmScheduler.kt) mirrors this logic;
/// both must agree. All times are device-local.
class NextOccurrence {
  /// Returns the next [DateTime] at/after [now] when [alarm] should ring,
  /// or null when there is no future occurrence (one-time alarm in the past,
  /// or weekly alarm with no days selected).
  static DateTime? nextTrigger(AlarmModel alarm, DateTime now) {
    final t = _nextTriggerInner(alarm, now);
    final skip = alarm.skipNextDate;
    // "Skip next only": if the computed trigger is the skipped one,
    // find the following occurrence instead. Use zero grace here so the
    // just-skipped time (1s in the past) isn't re-selected by the grace.
    if (t != null &&
        skip != null &&
        t.year == skip.year &&
        t.month == skip.month &&
        t.day == skip.day &&
        t.hour == skip.hour &&
        t.minute == skip.minute) {
      return _nextTriggerInner(
        alarm,
        t.add(const Duration(seconds: 1)),
        grace: Duration.zero,
      );
    }
    return t;
  }

  static DateTime? _nextTriggerInner(
    AlarmModel alarm,
    DateTime now, {
    Duration grace = const Duration(seconds: 120),
  }) {
    switch (alarm.mode) {
      case AlarmRepeatMode.weekly:
        return _nextWeekly(alarm, now, grace);
      case AlarmRepeatMode.once:
        return _nextOnce(alarm, now, grace);
      case AlarmRepeatMode.interval:
        return _nextInterval(alarm, now);
      case AlarmRepeatMode.specificDates:
        return _nextSpecificDates(alarm, now);
      case AlarmRepeatMode.cycle:
        return _nextCycle(alarm, now);
    }
  }

  /// Next [n] triggers (for the interval-mode preview). Empty when none.
  static List<DateTime> nextTriggers(AlarmModel alarm, DateTime now, int n) {
    final out = <DateTime>[];
    var cursor = now;
    var first = true;
    for (var i = 0; i < n; i++) {
      // Only the first lookup gets the grace period; subsequent ones use
      // zero grace so the cursor (1s past the last trigger) advances.
      final t = _nextTriggerInner(
        alarm,
        cursor,
        grace: first ? const Duration(seconds: 120) : Duration.zero,
      );
      if (t == null) break;
      out.add(t);
      // Move just past this trigger so the next search finds the following one.
      cursor = t.add(const Duration(seconds: 1));
      first = false;
    }
    return out;
  }

  static DateTime _at(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  static DateTime? _nextWeekly(AlarmModel alarm, DateTime now, Duration grace) {
    if (alarm.weekDays.isEmpty) return null;
    DateTime? best;
    final today = DateTime(now.year, now.month, now.day);
    // v2.15: grace period — if the user set the alarm for "right now", the
    // candidate may be a few seconds in the past by the time they save.
    final cutoff = now.subtract(grace);
    for (final wd in alarm.weekDays) {
      // wd: 1=Mon..7=Sun, matching DateTime.weekday.
      var delta = (wd - today.weekday) % 7;
      var candidate = _at(today.add(Duration(days: delta)), alarm.hour, alarm.minute);
      if (candidate.isBefore(cutoff)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      if (best == null || candidate.isBefore(best)) best = candidate;
    }
    return best;
  }

  static DateTime? _nextOnce(AlarmModel alarm, DateTime now, Duration grace) {
    final d = alarm.onceDate;
    if (d == null) return null;
    final t = _at(d, alarm.hour, alarm.minute);
    // v2.15: grace period — treat a just-passed time as "now", not "never".
    return t.isBefore(now.subtract(grace)) ? null : t;
  }

  static DateTime? _nextSpecificDates(AlarmModel alarm, DateTime now) {
    DateTime? best;
    for (final d in alarm.specificDates) {
      final t = _at(d, alarm.hour, alarm.minute);
      if (t.isBefore(now)) continue;
      if (best == null || t.isBefore(best)) best = t;
    }
    return best;
  }

  static DateTime? _nextInterval(AlarmModel alarm, DateTime now) {
    final start = alarm.intervalStart;
    final n = alarm.intervalDays;
    if (start == null || n < 1) return null;
    final origin = _at(start, alarm.hour, alarm.minute);
    if (!origin.isBefore(now)) return origin;
    final stepMs = n * 24 * 60 * 60 * 1000;
    final elapsed = now.millisecondsSinceEpoch - origin.millisecondsSinceEpoch;
    // smallest k >= 1 with origin + k*step >= now
    final k = (elapsed + stepMs - 1) ~/ stepMs;
    return origin.add(Duration(milliseconds: k * stepMs));
  }

  /// Ring/skip cycle: ring every day for [ringDays] days, then stay silent
  /// for [skipDays] days, repeating from [cycleStart]. Finds the next
  /// ring-day at/after [now].
  static DateTime? _nextCycle(AlarmModel alarm, DateTime now) {
    final start = alarm.cycleStart;
    final ring = alarm.ringDays;
    final skip = alarm.skipDays;
    if (start == null || ring < 1 || skip < 0) return null;
    final cycleLen = ring + skip;
    if (cycleLen < 1) return null;
    final startDay = DateTime(start.year, start.month, start.day);
    final today = DateTime(now.year, now.month, now.day);
    // Scan forward day by day (bounded: one year is plenty).
    for (var d = 0; d < 366; d++) {
      final day = today.add(Duration(days: d));
      final daysSinceStart = day.difference(startDay).inDays;
      if (daysSinceStart < 0) continue; // before the cycle start
      final pos = daysSinceStart % cycleLen;
      if (pos < ring) {
        final t = _at(day, alarm.hour, alarm.minute);
        if (!t.isBefore(now)) return t;
      }
    }
    return null;
  }
}
