import 'package:alarmhq/services/hijri_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HijriService', () {
    test('month names list has 12 English names', () {
      expect(HijriService.monthNamesEn.length, 12);
      expect(HijriService.monthNamesEn[0], 'Muharram');
      expect(HijriService.monthNamesEn[8], 'Ramadan');
    });

    test('algorithmic fallback returns valid date for out-of-coverage', () {
      // Without loading JSON, hijriFor uses the Kuwaiti algorithm.
      final svc = HijriService.instance;
      final h = svc.hijriFor(DateTime(2030, 1, 15));
      expect(h.year, greaterThan(1400));
      expect(h.year, lessThan(1600));
      expect(h.month, inInclusiveRange(1, 12));
      expect(h.day, inInclusiveRange(1, 30));
      expect(h.confidence, 'calculated');
      // Display uses English digits only.
      expect(RegExp(r'^[0-9]').hasMatch(h.display), isTrue);
      expect(h.display.contains(RegExp(r'[۰-۹]')), isFalse);
    });

    test('known conversion: 2026-10-20 is 8 Jamadi-ul-Awwal 1448 (approx)', () {
      final svc = HijriService.instance;
      final h = svc.hijriFor(DateTime(2026, 10, 20));
      // Algorithmic may differ by a day from sighting; allow 7-9.
      expect(h.day, inInclusiveRange(7, 9));
      expect(h.month, 5); // Jamadi-ul-Awwal
      expect(h.year, 1448);
    });
  });
}
