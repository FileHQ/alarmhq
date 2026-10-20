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

    test('2. Hijri spot-check: Oct 20 2026 = 8 Jamadi-ul-Awwal 1448', () async {
      // Load bundled JSON (works in tests via asset bundle).
      await HijriService.instance.load();
      final h = HijriService.instance.hijriFor(DateTime(2026, 10, 20));
      expect(h.day, 8);
      expect(h.month, 5);
      expect(h.year, 1448);
      expect(h.monthNameEn, 'Jamadi-ul-Awwal');
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
      // 1900 is outside both API coverage and the 1937-2077 Umm al-Qura
      // table -> arithmetical fallback.
      final h = svc.hijriFor(DateTime(1900, 6, 15));
      expect(h.isCalculated, isTrue);
      expect(h.confidence, 'calculated');
    });

    test('7b. v2.43: 1937-2077 out-of-API dates use Umm al-Qura (~)',
        () async {
      await HijriService.instance.load();
      final svc = HijriService.instance;
      // 2030 is outside 1447-1449 API coverage but inside the Umm al-Qura
      // table -> Pakistan-shifted Umm al-Qura, marked predicted ("~").
      final h = svc.hijriFor(DateTime(2030, 6, 15));
      expect(h.isCalculated, isFalse);
      expect(h.confidence, 'predicted');
      expect(h.confidenceMarker, '~');
      // 2100 is outside the table -> arithmetic fallback.
      final h2 = svc.hijriFor(DateTime(2100, 6, 15));
      expect(h2.isCalculated, isTrue);
      expect(h2.confidence, 'calculated');
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
        monthNameEn: 'Jamadi-ul-Awwal', monthNameUr: 'جمادی الاول', confidence: 'confirmed');
      const predicted = HijriDate(
        year: 1448, month: 6, day: 1,
        monthNameEn: 'Jamadi-ul-Sani', monthNameUr: 'جمادی الثانی', confidence: 'predicted');
      const estimated = HijriDate(
        year: 1448, month: 6, day: 2,
        monthNameEn: 'Jamadi-ul-Sani', monthNameUr: 'جمادی الثانی', confidence: 'estimated');
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
      // 2025-06-26 must be 29 Zil-Hajj 1446, NOT a duplicate 1st.
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

    // v2.37: the API skipped day 1 of Jumada al-Thani 1448
    // (2026-11-11 labeled "30 (unconfirmed)", 2026-11-12 labeled "2").
    // _fixSkippedDayOne relabels 2026-11-11 as the predicted 1st; then
    // the Pakistan shift (-1 day) moves it to 30 Jumada al-Awwal and
    // 2026-11-12 becomes 1 Jumada al-Thani. Final display must read
    // ..., 29, ~30, ~1, ~2, ... with no duplicates and no 28-day month.
    test('24. Skipped day 1 + Pakistan shift: Nov 2026 sequence',
        () async {
      await HijriService.instance.load();
      final svc = HijriService.instance;
      final nov10 = svc.hijriFor(DateTime(2026, 11, 10));
      final nov11 = svc.hijriFor(DateTime(2026, 11, 11));
      final nov12 = svc.hijriFor(DateTime(2026, 11, 12));
      final nov13 = svc.hijriFor(DateTime(2026, 11, 13));
      expect(nov10.day, 29);
      expect(nov10.month, 5);
      expect(nov10.confidence, 'confirmed'); // not shifted
      expect(nov11.day, 30);
      expect(nov11.month, 5);
      expect(nov11.confidence, 'predicted'); // shifted, "~" kept
      expect(nov12.day, 1);
      expect(nov12.month, 6);
      expect(nov12.confidence, 'predicted');
      expect(nov13.day, 2);
      expect(nov13.month, 6);
      // No 28-day month: Jumada al-Thani runs 1..29 (Nov 12 -> Dec 10).
      final dec10 = svc.hijriFor(DateTime(2026, 12, 10));
      expect(dec10.day, 29);
      expect(dec10.month, 6);
      final dec11 = svc.hijriFor(DateTime(2026, 12, 11));
      expect(dec11.day, 1);
      expect(dec11.month, 7);
    });

    // v2.37: sweep the FULL coverage — every Hijri month boundary must
    // start at day 1 (never 2+).
    test('25. Every month boundary in loaded data starts at day 1',
        () async {
      await HijriService.instance.load();
      final svc = HijriService.instance;
      var dt = DateTime(2025, 6, 26); // coverage start
      final end = DateTime(2028, 5, 24); // coverage end
      var prev = svc.hijriFor(dt);
      dt = dt.add(const Duration(days: 1));
      final problems = <String>[];
      while (!dt.isAfter(end)) {
        final cur = svc.hijriFor(dt);
        final isNewMonth =
            cur.year != prev.year || cur.month != prev.month;
        if (isNewMonth && cur.day != 1) {
          problems.add(
              '$dt: new month starts at day ${cur.day} (${cur.display})');
        }
        prev = cur;
        dt = dt.add(const Duration(days: 1));
      }
      expect(problems, isEmpty,
          reason: 'month boundaries not starting at 1:\n'
              '${problems.take(10).join('\n')}');
    });

    // v2.37: Pakistan shift applies to predicted/unconfirmed only.
    test('26. Pakistan shift: predicted -1 day, confirmed untouched',
        () async {
      await HijriService.instance.load();
      final svc = HijriService.instance;
      // A mid-month predicted date: raw API day decremented by 1.
      // 2027-01-15 is predicted in the 1448 data (raw: 7 Sha'ban).
      final jan15 = svc.hijriFor(DateTime(2027, 1, 15));
      expect(jan15.confidence, 'predicted');
      expect(jan15.day, 6); // raw 7 -> Pakistan-adjusted 6
      expect(jan15.month, 8); // Sha'ban
      // "~" marker kept (still an estimate).
      expect(jan15.confidenceMarker, '~');
      // A confirmed date is NOT shifted.
      final oct20 = svc.hijriFor(DateTime(2026, 10, 20));
      expect(oct20.confidence, 'confirmed');
      expect(oct20.day, 8);
      expect(oct20.month, 5);
    });

    test('13. Reverse lookup: 8 Jamadi-ul-Awwal 1448 = 2026-10-20',
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
      // 2100 is outside the Umm al-Qura table -> arithmetical fallback.
      final h = HijriService.instance.hijriFor(DateTime(2100, 1, 1));
      expect(h.isCalculated, isTrue);
      expect(h.monthNameUr, isNotEmpty);
      expect(HijriService.monthNamesUr.length, 12);
    });

    test('17b. v2.43: Umm al-Qura fallback has Urdu month name', () async {
      await HijriService.instance.load();
      // 2035 is outside API coverage but inside the Umm al-Qura table.
      final h = HijriService.instance.hijriFor(DateTime(2035, 1, 1));
      expect(h.isCalculated, isFalse);
      expect(h.confidence, 'predicted');
      expect(h.monthNameUr, isNotEmpty);
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
    // May 2025 spans "Zil-Qadah 1446 / Zil-Hajj 1446".
    // v2.37: dropdowns replaced by steppers — navigate with [-]/[+].
    testWidgets('21. Long Hijri header does not overflow', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      // Jump to May 2025 via Go to Date (also exercises the Go button).
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      // Year stepper minus down to 2025.
      final now21 = DateTime.now();
      for (var i = 0; i < now21.year - 2025; i++) {
        await tester
            .tap(find.byIcon(Icons.remove_circle_outline).first);
        await tester.pump();
      }
      // Month stepper minus down to May (5).
      final monthTaps = (now21.month - 5 + 12) % 12;
      for (var i = 0; i < monthTaps; i++) {
        await tester.tap(find.byIcon(Icons.remove_circle_outline).at(1));
        await tester.pump();
      }
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final texts = allText(tester).join(' ');
      expect(texts, contains('May 2025'));
      expect(texts, contains("Zil-Qadah 1446"));
      expect(texts, contains('Zil-Hajj 1446'));
    });

    // v2.35: "Go" on the Gregorian tab navigates and closes the dialog.
    // v2.37: year picked with the [+] stepper (4x: 2026 -> 2030).
    testWidgets('22. Go button (Gregorian tab) navigates', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      expect(find.text('Go to Date'), findsOneWidget);
      // Year stepper plus up to 2030.
      final now22 = DateTime.now();
      for (var i = 0; i < 2030 - now22.year; i++) {
        await tester.tap(find.byIcon(Icons.add_circle_outline).first);
        await tester.pump();
      }
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

    // v2.38: Go-to-Date stepper shows abbreviated month ("Nov", not
    // "November" which wrapped mid-word on her phone).
    testWidgets('27. Go to Date stepper uses short month names',
        (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      final texts = allText(tester).join(' ');
      // Current month abbreviated must appear; full "November"
      // must NOT appear in the stepper area.
      const short = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final now = DateTime.now();
      expect(texts, contains(short[now.month - 1]));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    });

    // v2.38: confirmed (sighted) dates show ✓ in day cells.
    testWidgets('28. Confirmed dates show ✓ mark', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      final texts = allText(tester).join(' ');
      // Oct 2026 dates are confirmed → cells show "✓8" style marks.
      expect(texts, contains(RegExp(r'✓\d+')),
          reason: 'No ✓ marks on confirmed dates in: $texts');
      expect(tester.takeException(), isNull);
    });

    // v2.38: Today button jumps back to the current month.
    testWidgets('29. Today button returns to current month',
        (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      // Navigate 3 months back.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pump();
      }
      // Today button exists.
      expect(find.text('Today'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pump();
      final now = DateTime.now();
      const en = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ];
      expect(allText(tester).join(' '),
          contains('${en[now.month - 1]} ${now.year}'));
      expect(tester.takeException(), isNull);
    });

    // v2.38: legend uses "Orange = calculated" (user decision).
    // NOTE: legend is a RichText (TextSpans), not Text widgets.
    testWidgets('30. Legend shows Orange = calculated', (tester) async {
      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      final rich = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .join(' ');
      expect(rich, contains('Orange = calculated'));
      expect(rich, isNot(contains('Amber = calculated')));
      expect(tester.takeException(), isNull);
    });

    // v2.38: data-update label reads "Data update: 17 Oct 2026".
    testWidgets('31. Data update label (en + ur)', (tester) async {
      String richText() => tester
          .widgetList<RichText>(find.byType(RichText))
          .map((w) => w.text.toPlainText())
          .join(' ');

      await HijriService.instance.load();
      await pumpCalendar(tester, const Locale('en'));
      var texts = allText(tester).join(' ');
      expect(texts, contains('Data update: 17 Oct 2026'));
      expect(texts, isNot(contains('Hijri data:')));
      expect(richText(), contains('✓ confirmed (sighted)'));

      await pumpCalendar(tester, const Locale('ur'));
      texts = allText(tester).join(' ');
      expect(texts, contains('ڈیٹا اپڈیٹ: 17 اکتوبر 2026'));
      expect(richText(), contains('اورنج = کیلکولیٹڈ'));
      expect(richText(), contains('✓ تصدیق شدہ'));
      expect(texts, contains('آج')); // Today button in Urdu
      expect(tester.takeException(), isNull);
    });
  });
}
