import 'package:alarmhq/models/alarm.dart';
import 'package:alarmhq/services/next_occurrence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AlarmModel base({
    AlarmRepeatMode mode = AlarmRepeatMode.interval,
    int hour = 7,
    int minute = 0,
    List<int> weekDays = const [1, 2, 3, 4, 5],
    DateTime? onceDate,
    int intervalDays = 5,
    DateTime? intervalStart,
  }) =>
      AlarmModel(
        id: 1,
        hour: hour,
        minute: minute,
        mode: mode,
        weekDays: weekDays,
        onceDate: onceDate,
        intervalDays: intervalDays,
        intervalStart: intervalStart,
      );

  group('interval mode (every N days)', () {
    test('rings on the start date itself', () {
      final a = base(intervalStart: DateTime(2026, 10, 14), intervalDays: 5);
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 6, 0));
      expect(t, DateTime(2026, 10, 14, 7, 0));
    });

    test('every 5 days: Oct 14 -> Oct 19 -> Oct 24', () {
      final a = base(intervalStart: DateTime(2026, 10, 14), intervalDays: 5);
      final ts = NextOccurrence.nextTriggers(a, DateTime(2026, 10, 14, 8, 0), 3);
      expect(ts, [
        DateTime(2026, 10, 19, 7, 0),
        DateTime(2026, 10, 24, 7, 0),
        DateTime(2026, 10, 29, 7, 0),
      ]);
    });

    test('every 6 days lands on the 6th day', () {
      final a = base(intervalStart: DateTime(2026, 10, 14), intervalDays: 6);
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 15, 12, 0));
      expect(t, DateTime(2026, 10, 20, 7, 0));
    });

    test('mid-cycle query jumps to the next ring, not a past one', () {
      final a = base(intervalStart: DateTime(2026, 10, 14), intervalDays: 5);
      // Oct 21 is between rings (Oct 19 and Oct 24).
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 21, 12, 0));
      expect(t, DateTime(2026, 10, 24, 7, 0));
    });

    test('invalid config returns null', () {
      final a = base(intervalStart: null, intervalDays: 0);
      expect(NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14)), isNull);
    });
  });

  group('weekly mode', () {
    test('picks the next selected weekday', () {
      // 2026-10-14 is a Wednesday.
      final a = base(mode: AlarmRepeatMode.weekly, weekDays: [1, 5]); // Mon, Fri
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 6, 0));
      expect(t, DateTime(2026, 10, 16, 7, 0)); // Friday
    });

    test('same-day time already passed rolls to next week', () {
      final a = base(mode: AlarmRepeatMode.weekly, weekDays: [3]); // Wednesday
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 8, 0));
      expect(t, DateTime(2026, 10, 21, 7, 0));
    });

    test('no days selected returns null', () {
      final a = base(mode: AlarmRepeatMode.weekly, weekDays: []);
      expect(NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14)), isNull);
    });

    test('v2.16: time 60s in the past rolls to next week (no grace)', () {
      final a = base(mode: AlarmRepeatMode.weekly, weekDays: [3]); // Wednesday
      // Alarm for 7:00, now is 7:01 — no grace, so next week.
      final t = NextOccurrence.nextTrigger(
          a, DateTime(2026, 10, 14, 7, 1, 0));
      expect(t, DateTime(2026, 10, 21, 7, 0));
    });

    test('v2.16: time 5min in the past rolls to next week', () {
      final a = base(mode: AlarmRepeatMode.weekly, weekDays: [3]); // Wednesday
      // Alarm for 7:00, now is 7:05 — beyond grace, next week.
      final t = NextOccurrence.nextTrigger(
          a, DateTime(2026, 10, 14, 7, 5, 0));
      expect(t, DateTime(2026, 10, 21, 7, 0));
    });
  });

  group('one-time mode', () {
    test('future date rings, past date returns null', () {
      final future = base(mode: AlarmRepeatMode.once, onceDate: DateTime(2026, 10, 20));
      expect(
        NextOccurrence.nextTrigger(future, DateTime(2026, 10, 14, 12, 0)),
        DateTime(2026, 10, 20, 7, 0),
      );
      final past = base(mode: AlarmRepeatMode.once, onceDate: DateTime(2026, 10, 10));
      expect(
        NextOccurrence.nextTrigger(past, DateTime(2026, 10, 14, 12, 0)),
        isNull,
      );
    });

    test('v2.16: one-time 60s in the past returns null (no grace)', () {
      final a = base(
        mode: AlarmRepeatMode.once,
        onceDate: DateTime(2026, 10, 14),
        hour: 7,
        minute: 0,
      );
      // Alarm for 7:00 today, now is 7:01 — no grace, so null.
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 7, 1, 0));
      expect(t, isNull);
    });

    test('v2.16: one-time 5min in the past returns null', () {
      final a = base(
        mode: AlarmRepeatMode.once,
        onceDate: DateTime(2026, 10, 14),
        hour: 7,
        minute: 0,
      );
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 7, 5, 0));
      expect(t, isNull);
    });
  });

  group('specific dates mode', () {
    AlarmModel datesBase(List<DateTime> ds) => AlarmModel(
          id: 1,
          hour: 7,
          minute: 0,
          mode: AlarmRepeatMode.specificDates,
          specificDates: ds,
        );

    test('picks the next future date', () {
      final a = datesBase([
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 23),
        DateTime(2026, 11, 5),
      ]);
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0));
      expect(t, DateTime(2026, 10, 15, 7, 0));
    });

    test('skips past dates', () {
      final a = datesBase([
        DateTime(2026, 10, 10),
        DateTime(2026, 10, 23),
      ]);
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0));
      expect(t, DateTime(2026, 10, 23, 7, 0));
    });

    test('all past dates returns null', () {
      final a = datesBase([DateTime(2026, 10, 10)]);
      expect(
        NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0)),
        isNull,
      );
    });

    test('empty list returns null', () {
      final a = datesBase([]);
      expect(
        NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0)),
        isNull,
      );
    });
  });

  group('skip next', () {
    test('skipped trigger is bypassed', () {
      final a = AlarmModel(
        id: 1,
        hour: 7,
        minute: 0,
        mode: AlarmRepeatMode.weekly,
        weekDays: [1, 2, 3, 4, 5, 6, 7],
        skipNextDate: DateTime(2026, 10, 15, 7, 0),
      );
      // Next would be Oct 15 07:00, but it's skipped -> Oct 16.
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0));
      expect(t, DateTime(2026, 10, 16, 7, 0));
    });

    test('past skip date is ignored', () {
      final a = AlarmModel(
        id: 1,
        hour: 7,
        minute: 0,
        mode: AlarmRepeatMode.weekly,
        weekDays: [1, 2, 3, 4, 5, 6, 7],
        skipNextDate: DateTime(2026, 10, 10, 7, 0),
      );
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 12, 0));
      expect(t, DateTime(2026, 10, 15, 7, 0));
    });
  });

  test('model survives a JSON round-trip', () {
    final a = base(
      intervalStart: DateTime(2026, 10, 14),
      onceDate: DateTime(2026, 10, 20),
    ).copyWith(
      label: 'فجر',
      toneUri: 'content://media/1',
      specificDates: [DateTime(2026, 10, 25), DateTime(2026, 11, 1)],
      skipNextDate: () => DateTime(2026, 10, 15, 7, 0),
    );
    final b = AlarmModel.fromJson(a.toJson());
    expect(b.label, 'فجر');
    expect(b.intervalDays, 5);
    expect(b.intervalStart, DateTime(2026, 10, 14));
    expect(b.toneUri, 'content://media/1');
    expect(b.specificDates,
        [DateTime(2026, 10, 25), DateTime(2026, 11, 1)]);
    expect(b.skipNextDate, DateTime(2026, 10, 15, 7, 0));
  });

  group('cycle mode (ring X days, skip Y days)', () {
    AlarmModel cycle({
      int hour = 7,
      int minute = 0,
      int ringDays = 5,
      int skipDays = 1,
      DateTime? cycleStart,
    }) =>
        AlarmModel(
          id: 2,
          hour: hour,
          minute: minute,
          mode: AlarmRepeatMode.cycle,
          ringDays: ringDays,
          skipDays: skipDays,
          cycleStart: cycleStart ?? DateTime(2026, 10, 12), // a Monday
        );

    test('rings on a ring day at the alarm time', () {
      // Oct 14 = 2 days after start -> position 2 < 5 -> rings.
      final a = cycle();
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 6, 0));
      expect(t, DateTime(2026, 10, 14, 7, 0));
    });

    test('skips the silent days', () {
      // Oct 17 = 5 days after start -> position 5 >= 5 -> silent.
      // Next ring day is Oct 18 (position 0 of next cycle).
      final a = cycle();
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 17, 6, 0));
      expect(t, DateTime(2026, 10, 18, 7, 0));
    });

    test('same-day alarm time already passed -> next ring day', () {
      final a = cycle();
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 8, 0));
      expect(t, DateTime(2026, 10, 15, 7, 0));
    });

    test('start date in the future', () {
      final a = cycle(cycleStart: DateTime(2026, 10, 20));
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 6, 0));
      expect(t, DateTime(2026, 10, 20, 7, 0));
    });

    test('skipDays = 0 means ring every day', () {
      final a = cycle(skipDays: 0);
      final t = NextOccurrence.nextTrigger(a, DateTime(2026, 10, 14, 8, 0));
      expect(t, DateTime(2026, 10, 15, 7, 0));
    });

    test('JSON round-trip keeps cycle fields', () {
      final a = cycle(ringDays: 3, skipDays: 2);
      final b = AlarmModel.fromJson(a.toJson());
      expect(b.mode, AlarmRepeatMode.cycle);
      expect(b.ringDays, 3);
      expect(b.skipDays, 2);
      expect(b.cycleStart, DateTime(2026, 10, 12));
    });
  });
}
