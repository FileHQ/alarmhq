import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v2.39: Full Urdu weekday names must fit inside the pills (no overflow).
void main() {
  // Mirror of _weeklyPicker pill layout (full names + FittedBox).
  Widget buildPills(List<String> names) {
    return MaterialApp(
      locale: const Locale('ur'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: List.generate(7, (i) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(21),
                      color: i == 0 ? AppTheme.emerald : AppTheme.charcoalCard,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        names[i],
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  testWidgets('Urdu weekday pills: full names, no overflow', (tester) async {
    const names = ['پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ', 'اتوار'];
    // Phone-width viewport (narrow).
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildPills(names));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'Overflow error in weekday pills');
    for (final n in names) {
      expect(find.text(n), findsOneWidget, reason: 'Missing: $n');
    }
  });

  testWidgets('English weekday pills: full names, no overflow', (tester) async {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(buildPills(names));
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'Overflow error in weekday pills');
    for (final n in names) {
      expect(find.text(n), findsOneWidget, reason: 'Missing: $n');
    }
  });
}
