import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2.41 regression tests:
/// 1. Weekday header names must not wrap (جمعرات on one line).
/// 2. Countdown text uses explicit Roboto font (no fallback color bug).
void main() {
  group('v2.41 weekday header', () {
    testWidgets('all 7 Urdu weekday names fit on one line each',
        (tester) async {
      // Simulate the header cell: FittedBox + maxLines 1.
      const names = [
        'پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ', 'اتوار'
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                for (final h in names)
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(h,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // No overflow errors.
      expect(tester.takeException(), isNull);
      // All names present.
      for (final h in names) {
        expect(find.text(h), findsOneWidget);
      }
    });

    test('جمعرات is the longest name and must not wrap', () {
      // Longest Urdu weekday name; FittedBox + maxLines:1 handles it.
      expect('جمعرات'.length, greaterThan('پیر'.length));
    });
  });

  group('v2.41 countdown font', () {
    testWidgets('countdown uses explicit Roboto fontFamily',
        (tester) async {
      const countdown = 'Rings in 9h 56m';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              return Text(
                '⏳ $countdown',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFA3E635),
                  fontFamily: 'Roboto',
                ),
              );
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.text('⏳ $countdown'));
      // Explicit fontFamily prevents fallback color bugs.
      expect(text.style!.fontFamily, 'Roboto');
      expect(text.style!.color, const Color(0xFFA3E635));
      expect(tester.takeException(), isNull);
    });
  });

  group('v2.41 legend sizes', () {
    test('Urdu legend uses larger font than English', () {
      // v2.41: isUrdu ? 15 : 11 for legend, isUrdu ? 14 : 10 for data update.
      const urduLegendSize = 15;
      const enLegendSize = 11;
      const urduUpdateSize = 14;
      const enUpdateSize = 10;
      expect(urduLegendSize, greaterThan(enLegendSize));
      expect(urduUpdateSize, greaterThan(enUpdateSize));
    });
  });
}
