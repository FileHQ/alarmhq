import 'package:alarmhq/widgets/time_picker_scroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('infinite wheel helpers', () {
    test('hourValueAt cycles 1..12 forever', () {
      expect(hourValueAt(0), 1);
      expect(hourValueAt(11), 12);
      expect(hourValueAt(12), 1);
      expect(hourValueAt(13), 2);
      // centered start used by the picker
      expect(hourValueAt(kHourWheelCount ~/ 2), 1);
      expect(hourValueAt(kHourWheelCount ~/ 2 + 11), 12);
      expect(hourValueAt(kHourWheelCount ~/ 2 + 12), 1);
    });

    test('minuteValueAt cycles 0..59 forever', () {
      expect(minuteValueAt(0), 0);
      expect(minuteValueAt(59), 59);
      expect(minuteValueAt(60), 0);
      expect(minuteValueAt(61), 1);
      expect(minuteValueAt(kMinuteWheelCount ~/ 2), 0);
      expect(minuteValueAt(kMinuteWheelCount ~/ 2 + 59), 59);
      expect(minuteValueAt(kMinuteWheelCount ~/ 2 + 60), 0);
    });

    test('isAmAt alternates AM/PM', () {
      expect(isAmAt(0), isTrue);
      expect(isAmAt(1), isFalse);
      expect(isAmAt(2), isTrue);
      expect(isAmAt(kAmPmWheelCount ~/ 2), isTrue);
      expect(isAmAt(kAmPmWheelCount ~/ 2 + 1), isFalse);
    });

    test('hourWrapTogglesAmPm only at the 12 <-> 1 boundary', () {
      expect(hourWrapTogglesAmPm(12, 1), isTrue); // forward wrap
      expect(hourWrapTogglesAmPm(1, 12), isTrue); // backward wrap
      expect(hourWrapTogglesAmPm(11, 12), isFalse);
      expect(hourWrapTogglesAmPm(1, 2), isFalse);
      expect(hourWrapTogglesAmPm(5, 6), isFalse);
      expect(hourWrapTogglesAmPm(6, 5), isFalse);
    });

    test('nearestHourIndex finds the closest matching row', () {
      // from virtual index 6000 (shows hour 1)
      expect(nearestHourIndex(6000, 1), 6000);
      expect(nearestHourIndex(6000, 3), 6002);
      expect(nearestHourIndex(6000, 12), 6011);
      // typing the current hour keeps the same row (no wrap, no AM/PM flip)
      expect(nearestHourIndex(6011, 12), 6011);
    });

    test('nearestMinuteIndex finds the closest matching row', () {
      expect(nearestMinuteIndex(60000, 0), 60000);
      expect(nearestMinuteIndex(60000, 30), 60030);
      expect(nearestMinuteIndex(60030, 0), 60060); // wraps forward past 59
      expect(nearestMinuteIndex(60030, 30), 60030);
    });
  });
}
