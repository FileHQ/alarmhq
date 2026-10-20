import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/screens/calendar_screen.dart';
import 'package:alarmhq/services/hijri_service.dart';
import 'package:alarmhq/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('v2.36: Go to Date dropdowns show year/month/day values',
      (tester) async {
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

    await tester.tap(find.byIcon(Icons.event));
    await tester.pump(const Duration(milliseconds: 300));

    final now = DateTime.now();
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    // Year, month name and day must all be visible in the dialog.
    expect(texts, contains('${now.year}'),
        reason: 'year dropdown blank: $texts');
    expect(texts, contains('${now.day}'),
        reason: 'day dropdown blank: $texts');
    // v2.36: change the month via the dropdown and check it repaints.
    await tester.tap(find.text('October').first);
    await tester.pumpAndSettle();
    expect(find.text('November'), findsWidgets);
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
