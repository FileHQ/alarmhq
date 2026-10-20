import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/screens/calendar_screen.dart';
import 'package:alarmhq/services/hijri_service.dart';
import 'package:alarmhq/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpCalendar(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: const CalendarScreen(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> openGoToDate(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.event));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Day cells with the lime "jumped here" outline: transparent fill +
/// a Border whose color is AppTheme.emerald.
Finder jumpedOutlineCells(WidgetTester tester) {
  return find.byWidgetPredicate((w) {
    if (w is! Container) return false;
    final d = w.decoration;
    if (d is! BoxDecoration) return false;
    final border = d.border;
    if (border is! Border) return false;
    return border.top.color == AppTheme.emerald &&
        (d.color == null || d.color == Colors.transparent);
  });
}

void main() {
  testWidgets('v2.37: Go to Date steppers show year/month/day (never blank)',
      (tester) async {
    await pumpCalendar(tester);
    await openGoToDate(tester);

    final now = DateTime.now();
    // The stepper values are plain Text — always painted, cannot go blank.
    // (Scoped to the dialog: the calendar grid behind shows the same day.)
    final dialog = find.byType(AlertDialog);
    Finder inDialog(String s) =>
        find.descendant(of: dialog, matching: find.text(s));
    expect(inDialog('${now.year}'), findsOneWidget,
        reason: 'year stepper value missing');
    expect(inDialog('${now.day}'), findsOneWidget,
        reason: 'day stepper value missing');

    // Year "+" repaints with the incremented year.
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();
    expect(inDialog('${now.year + 1}'), findsOneWidget,
        reason: 'year stepper did not repaint after +');

    // Year "-" brings it back.
    await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
    await tester.pump();
    expect(inDialog('${now.year}'), findsOneWidget,
        reason: 'year stepper did not repaint after -');
  });

  testWidgets('v2.37: Go highlights jumped date with lime OUTLINE (not fill)',
      (tester) async {
    await pumpCalendar(tester);
    await openGoToDate(tester);

    // Move the day stepper forward so the target is NOT today
    // (today keeps its fill; jumped date gets outline only).
    await tester.tap(find.byIcon(Icons.add_circle_outline).at(2));
    await tester.pump();

    // Go.
    await tester.tap(find.text('Go'));
    await tester.pump(const Duration(milliseconds: 300));

    // Exactly one cell has the lime outline with transparent fill.
    expect(jumpedOutlineCells(tester), findsOneWidget,
        reason: 'jumped-to date should have a lime outline');

    // Manually changing month clears the highlight.
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(jumpedOutlineCells(tester), findsNothing,
        reason: 'manual month change should clear the jump highlight');
  });

  test('v2.36: Pakistani Hijri month spellings', () async {
    expect(HijriService.monthNamesEn, [
      'Muharram',
      'Safar',
      'Rabi-ul-Awwal',
      'Rabi-ul-Sani',
      'Jamadi-ul-Awwal',
      'Jamadi-ul-Sani',
      'Rajab',
      'Shaban',
      'Ramadan',
      'Shawwal',
      'Zil-Qadah',
      'Zil-Hajj',
    ]);
    await HijriService.instance.load();
    // API-loaded date must use Pakistani spelling, not the API string.
    final h = HijriService.instance.hijriFor(DateTime(2026, 10, 20));
    expect(h.display, '8 Jamadi-ul-Awwal 1448');
    expect(h.display, isNot(contains('Jumada')));
  });
}
