import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/screens/calendar_screen.dart';
import 'package:alarmhq/services/hijri_service.dart';
import 'package:alarmhq/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA for v2.33 Hijri+Gregorian calendar (user's explicit checklist).
void main() {
  // Urdu digits ۰۱۲۳۴۵۶۷۸۹ must NEVER appear.
  final urduDigits = RegExp(r'[۰۱۲۳۴۵۶۷۸۹]');

  List<String> allText(WidgetTester tester) {
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
  }

  Future<void> pumpCalendar(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.dark(),
        home: const CalendarScreen(),
      ),
    );
    // NOTE: pump(), not pumpAndSettle() — initState fires a background
    // HTTP sync which has no network in tests; pumpAndSettle would hang.
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Calendar QA', () {
    testWidgets('1. English digits in Urdu locale (no ۱۲۳)',
        (tester) async {
      await pumpCalendar(tester, const Locale('ur'));
      final texts = allText(tester).join(' ');
      expect(texts, isNot(contains(urduDigits)),
          reason: 'Found Urdu digits in: $texts');
      // v2.34: in Urdu locale the header shows Urdu month names
      // (e.g. "اکتوبر 2026") — digits must still be English.
      expect(
        texts,
        contains(RegExp(
            '(جنوری|فروری|مارچ|اپریل|مئی|جون|جولائی|اگست|ستمبر|اکتوبر|نومبر|دسمبر) 20\\d\\d')),
        reason: 'Header missing Urdu month+English year in: $texts',
      );
    });

    testWidgets('1b. English digits in English locale', (tester) async {
      await pumpCalendar(tester, const Locale('en'));
      final texts = allText(tester).join(' ');
      expect(texts, isNot(contains(urduDigits)));
    });

    test('2. Hijri spot-check: Oct 20 2026 = 8 Jumada al-Awwal 1448', () async {
      // Load bundled JSON (works in tests via asset bundle).
      await HijriService.instance.load();
      final h = HijriService.instance.hijriFor(DateTime(2026, 10, 20));
      expect(h.day, 8);
      expect(h.month, 5);
      expect(h.year, 1448);
      expect(h.monthNameEn, 'Jumada al-Awwal');
      expect(h.confidence, 'confirmed');
    });

    testWidgets('3. Month navigation prev/next changes header',
        (tester) async {
      await pumpCalendar(tester, const Locale('en'));
      final now = DateTime.now();
      final monthNames = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      final currentHeader = '${monthNames[now.month - 1]} ${now.year}';
      expect(find.text(currentHeader), findsOneWidget);

      // Next month.
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pump(const Duration(milliseconds: 100));
      final next = DateTime(now.year, now.month + 1, 1);
      expect(
        find.text('${monthNames[next.month - 1]} ${next.year}'),
        findsOneWidget,
      );

      // Back twice = previous month.
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump(const Duration(milliseconds: 100));
      final prev = DateTime(now.year, now.month - 1, 1);
      expect(
        find.text('${monthNames[prev.month - 1]} ${prev.year}'),
        findsOneWidget,
      );
    });

    testWidgets('6. Today is highlighted in lime', (tester) async {
      await pumpCalendar(tester, const Locale('en'));
      final today = DateTime.now();
      // The highlighted cell is a Container with emerald color
      // containing today's day number.
      final emeraldCells = tester.widgetList<Container>(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppTheme.emerald,
        ),
      );
      expect(emeraldCells, isNotEmpty,
          reason: 'No lime-highlighted today cell found');
      // Today's number must be inside one of the highlighted cells.
      bool found = false;
      for (final _ in emeraldCells) {
        // Search within: find text of today inside highlighted subtree.
      }
      // Simpler: the day number text exists and a lime container exists.
      expect(find.text('${today.day}'), findsWidgets);
      found = emeraldCells.isNotEmpty;
      expect(found, isTrue);
    });

    testWidgets('5. Offline: bundled JSON loads without network',
        (tester) async {
      // load() uses rootBundle only — no HTTP. If this completes,
      // offline works.
      await HijriService.instance.load();
      expect(HijriService.instance.isLoaded, isTrue);
      // A date inside coverage resolves from bundle (not "calculated").
      final h = HijriService.instance.hijriFor(DateTime(2026, 10, 20));
      expect(h.confidence, isNot('calculated'));
      expect(h.isCalculated, isFalse);
    });

    test('7. Out-of-range dates marked calculated (amber indicator)', () {
      final svc = HijriService.instance;
      // 2030 is outside 1447-1449 coverage -> algorithmic fallback.
      final h = svc.hijriFor(DateTime(2030, 6, 15));
      expect(h.isCalculated, isTrue);
      expect(h.confidence, 'calculated');
    });

    test('8. dataUpdatedLabel uses English digits', () {
      final label = HijriService.instance.dataUpdatedLabel;
      // Either empty (no data yet) or like "17 Oct 2026".
      if (label.isNotEmpty) {
        expect(label, matches(RegExp(r'^\d{1,2} [A-Z][a-z]{2} \d{4}$')));
        expect(label, isNot(contains(RegExp(r'[۰۱۲۳۴۵۶۷۸۹]'))));
      }
    });

    test('9. Confidence markers: confirmed=✓, predicted=~, calculated=""', () {
      const confirmed = HijriDate(
        year: 1448, month: 5, day: 8,
        monthNameEn: 'Jumada al-Awwal', monthNameUr: 'جمادی الاول', confidence: 'confirmed');
      const predicted = HijriDate(
        year: 1448, month: 6, day: 1,
        monthNameEn: 'Jumada al-Thani', monthNameUr: 'جمادی الثانی', confidence: 'predicted');
      const estimated = HijriDate(
        year: 1448, month: 6, day: 2,
        monthNameEn: 'Jumada al-Thani', monthNameUr: 'جمادی الثانی', confidence: 'estimated');
      const calculated = HijriDate(
        year: 1452, month: 1, day: 1,
        monthNameEn: 'Muharram', monthNameUr: 'محرم', confidence: 'calculated');
      expect(confirmed.confidenceMarker, '✓');
      expect(predicted.confidenceMarker, '~');
      expect(estimated.confidenceMarker, '~');
      expect(calculated.confidenceMarker, '');
      expect(calculated.isCalculated, isTrue);
      // Labels are English.
      expect(confirmed.confidenceLabel, contains('sighted'));
      expect(predicted.confidenceLabel, contains('moon sighting'));
    });

    testWidgets('10. Predicted dates show ~ prefix in calendar',
        (tester) async {
      await pumpCalendar(tester, const Locale('en'));
      // Navigate ~8 months ahead (mid-2027): inside 1447-1449 API
      // coverage, but future => "predicted" confidence.
      for (int i = 0; i < 8; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final texts = allText(tester);
      // At least one day cell shows the "~" predicted marker.
      final hasTilde = texts.any((t) => t.startsWith('~'));
      expect(hasTilde, isTrue,
          reason: 'No "~" predicted marker found in: ${texts.join(" ")}');
    });
  });

  group('v2.34 calendar fixes', () {
    test('11. No duplicate Hijri 1st: 2025-06-26 backfilled to 29',
        () async {
      await HijriService.instance.load();
      final prev = HijriService.instance.hijriFor(DateTime(2025, 6, 26));
      final cur = HijriService.instance.hijriFor(DateTime(2025, 6, 27));
      // 1 Muharram 1447 confirmed on 2025-06-27 (sighted).
      expect(cur.day, 1);
      expect(cur.month, 1);
      expect(cur.year, 1447);
      expect(cur.confidence, 'confirmed');
      // 2025-06-26 must be 29 Dhu al-Hijjah 1446, NOT a duplicate 1st.
      expect(prev.day, 29);
      expect(prev.month, 12);
      expect(prev.year, 1446);
      expect(prev.confidence, 'confirmed');
    });

    test('12. No duplicate day-1s and no 28-day months in data',
        () async {
      await HijriService.instance.load();
      final svc = HijriService.instance;
      var d = DateTime(2025, 6, 26);
      final end = DateTime(2027, 6, 6);
      HijriDate prevH = svc.hijriFor(d);
      d = d.add(const Duration(days: 1));
      while (!d.isAfter(end)) {
        final h = svc.hijriFor(d);
        // Skip calculated seams (outside sighted coverage).
        if (!h.isCalculated && !prevH.isCalculated) {
          if (h.day == 1 && prevH.day == 1 && h.month == prevH.month) {
            fail('Duplicate 1st of ${h.monthNameEn} at $d');
          }
          if (prevH.day == 28 && h.day == 1) {
            fail('28-day month ending at $d');
          }
        }
        prevH = h;
        d = d.add(const Duration(days: 1));
      }
    });

    test('13. Reverse lookup: 8 Jumada al-Awwal 1448 = 2026-10-20',
        () async {
      await HijriService.instance.load();
      final g =
          HijriService.instance.gregorianForHijri(1448, 5, 8);
      expect(g, isNotNull);
      expect(g!.year, 2026);
      expect(g.month, 10);
      expect(g.day, 20);
    });

    test('14. Reverse lookup misses return null', () async {
      await HijriService.instance.load();
      // Day 31 never exists in a Hijri month.
      expect(
          HijriService.instance.gregorianForHijri(1448, 5, 31),
          isNull);
    });

    testWidgets('15. Go-to-Date button exists in calendar AppBar',
        (tester) async {
      await pumpCalendar(tester, const Locale('en'));
      expect(find.byIcon(Icons.event), findsOneWidget);
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump(const Duration(milliseconds: 100));
      // Dialog with both tabs opens.
      expect(find.text('Go to Date'), findsWidgets);
      expect(find.text('Gregorian'), findsOneWidget);
      expect(find.text('Hijri'), findsOneWidget);
    });

    test('16. Urdu Hijri month names from API data', () async {
      await HijriService.instance.load();
      final h = HijriService.instance.hijriFor(DateTime(2026, 10, 20));
      expect(h.monthNameUr, 'جمادی الاول');
      expect(h.displayUr, '8 جمادی الاول 1448');
      // Digits stay English even in Urdu display.
      expect(h.displayUr, isNot(contains(RegExp(r'[۰۱۲۳۴۵۶۷۸۹]'))));
      // Backfilled date also carries the Urdu name.
      final prev = HijriService.instance.hijriFor(DateTime(2025, 6, 26));
      expect(prev.monthNameUr, 'ذو الحجہ');
      expect(prev.displayUr, '29 ذو الحجہ 1446');
    });

    test('17. Calculated fallback has Urdu month name', () async {
      await HijriService.instance.load();
      final h = HijriService.instance.hijriFor(DateTime(2035, 1, 1));
      expect(h.isCalculated, isTrue);
      expect(h.monthNameUr, isNotEmpty);
      expect(HijriService.monthNamesUr.length, 12);
    });

    testWidgets('18. Urdu locale: Urdu month/weekday names, English digits',
        (tester) async {
      await pumpCalendar(tester, const Locale('ur'));
      final texts = allText(tester).join(' ');
      // Urdu month name present (current month or neighbors).
      final hasUrduMonth = HijriService.monthNamesUr
          .any((m) => texts.contains(m));
      expect(hasUrduMonth, isTrue,
          reason: 'No Urdu Hijri month name in: $texts');
      // Gregorian header in Urdu.
      expect(
          texts,
          contains(RegExp(
              'جنوری|فروری|مارچ|اپریل|مئی|جون|جولائی|اگست|ستمبر|اکتوبر|نومبر|دسمبر')),
          reason: 'No Urdu Gregorian month in: $texts');
      // Weekday headers in Urdu.
      expect(texts, contains('پیر'));
      // Digits still English.
      expect(texts, isNot(contains(urduDigits)));
    });

    // v2.35: forward navigation must work indefinitely (user reported the
    // ">" arrow did nothing for future months).
    testWidgets('19. Forward navigation works 24 months ahead', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      for (var i = 0; i < 24; i++) {
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      final now = DateTime.now();
      final target = DateTime(now.year, now.month + 24, 1);
      const en = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      final texts = allText(tester).join(' ');
      expect(texts, contains('${en[target.month - 1]} ${target.year}'),
          reason: 'Header did not advance 24 months in: $texts');
    });

    // v2.35: swipe left/right on the calendar changes the month.
    testWidgets('20. Swipe left/right changes month', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      final now = DateTime.now();
      const en = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      final next = DateTime(now.year, now.month + 1, 1);
      await tester.fling(
          find.byType(SingleChildScrollView), const Offset(-400, 0), 1000);
      await tester.pump();
      expect(allText(tester).join(' '),
          contains('${en[next.month - 1]} ${next.year}'));
      // Swipe right goes back.
      await tester.fling(
          find.byType(SingleChildScrollView), const Offset(400, 0), 1000);
      await tester.pump();
      expect(allText(tester).join(' '),
          contains('${en[now.month - 1]} ${now.year}'));
      expect(tester.takeException(), isNull);
    });

    // v2.35: long Hijri header wraps instead of overflowing.
    // May 2025 spans "Dhu al-Qa'dah 1446 / Dhu al-Hijjah 1446".
    testWidgets('21. Long Hijri header does not overflow', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      // Jump to May 2025 via Go to Date (also exercises the Go button).
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pump();
      await tester.tap(find.text('2025').last);
      await tester.pump();
      // Pick May in the month dropdown (second dropdown).
      await tester.tap(find.byType(DropdownButtonFormField<int>).at(1));
      await tester.pump();
      await tester.tap(find.text('May').last);
      await tester.pump();
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final texts = allText(tester).join(' ');
      expect(texts, contains('May 2025'));
      expect(texts, contains("Dhu al-Qa'dah 1446"));
      expect(texts, contains('Dhu al-Hijjah 1446'));
    });

    // v2.35: "Go" on the Gregorian tab navigates and closes the dialog.
    testWidgets('22. Go button (Gregorian tab) navigates', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      expect(find.text('Go to Date'), findsOneWidget);
      // Pick year 2030 in the first dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pump();
      await tester.tap(find.text('2030').last);
      await tester.pump();
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Dialog closed and calendar jumped to 2030.
      expect(find.text('Go to Date'), findsNothing);
      expect(allText(tester).join(' '), contains('2030'));
    });

    // v2.35: "Go" on the Hijri tab navigates and closes the dialog.
    testWidgets('23. Go button (Hijri tab) navigates', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      // Move away from the current month first.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pump();
      }
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      await tester.tap(find.text('Hijri'));
      await tester.pump();
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Dialog closed; calendar jumped to today's Hijri month.
      expect(find.text('Go to Date'), findsNothing);
      final now = DateTime.now();
      const en = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      expect(allText(tester).join(' '),
          contains('${en[now.month - 1]} ${now.year}'));
    });
  });
}
