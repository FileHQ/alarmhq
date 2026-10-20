import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../services/hijri_service.dart';
import '../theme/app_theme.dart';

/// Monthly calendar tab showing Gregorian dates with Hijri dates below.
/// All numbers are rendered with plain toString() — English digits only.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    // v2.33: silent background sync — never blocks the UI.
    HijriService.instance.syncFromNetwork().then((_) {
      if (mounted) setState(() {});
    });
  }

  // v2.33: English month names hardcoded so the header ALWAYS shows
  // English digits (e.g. "October 2026"), even in Urdu locale where
  // MaterialLocalizations would render Urdu digits (۲۰۲۶).
  static const List<String> _monthNamesEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(_month.year, _month.month, 1);
    // English digits guaranteed: hardcoded English names + toString().
    final monthTitle =
        '${_monthNamesEn[monthStart.month - 1]} ${monthStart.year}';

    // Monday-first offset.
    final leading = (monthStart.weekday - 1) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];

    // Hijri month/year for the 1st — representative for the header.
    final hijriFirst = HijriService.instance.hijriFor(monthStart);

    final dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.calendar),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.charcoalCard,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                  ),
                  Column(
                    children: [
                      Text(
                        monthTitle,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hijriFirst.monthYear,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeMonth(1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.85,
                children: [
                  for (final h in dow)
                    Center(
                      child: Text(h,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  for (final cell in cells)
                    if (cell == null)
                      const SizedBox.shrink()
                    else
                      _dayCell(cell, today),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Top: Gregorian  •  Bottom: Hijri (tap a date for detail)',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 2),
              // v2.33: confidence legend — user asked for visible markers.
              RichText(
                text: TextSpan(
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white38),
                  children: [
                    const TextSpan(text: '✓ confirmed (sighted)  '),
                    const TextSpan(text: '~ predicted (estimated)  '),
                    TextSpan(
                      text: 'Amber = calculated',
                      style: TextStyle(color: Colors.amber.shade300),
                    ),
                  ],
                ),
              ),
              if (HijriService.instance.dataUpdatedLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Hijri data: ${HijriService.instance.dataUpdatedLabel}',
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tap a date → detail dialog with full Hijri date + confidence.
  void _showDateDetail(BuildContext context, DateTime cell) {
    final hijri = HijriService.instance.hijriFor(cell);
    final gregorian =
        '${_monthNamesEn[cell.month - 1]} ${cell.day}, ${cell.year}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gregorian),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hijri.display,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  hijri.confidenceMarker,
                  style: TextStyle(
                    fontSize: 16,
                    color: hijri.isCalculated
                        ? Colors.amber.shade300
                        : AppTheme.emerald,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    hijri.confidenceLabel,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime cell, DateTime today) {
    final isToday = cell.year == today.year &&
        cell.month == today.month &&
        cell.day == today.day;
    final hijri = HijriService.instance.hijriFor(cell);
    // v2.33: amber Hijri number marks arithmetical "calculated" dates
    // (outside sighted-data coverage), so the user knows the difference.
    // "~" marks predicted/estimated (until moon sighting).
    final hijriColor = isToday
        ? Colors.black87
        : hijri.isCalculated
            ? Colors.amber.shade300
            : Colors.white38;
    final marker = hijri.confidenceMarker;
    return GestureDetector(
      onTap: () => _showDateDetail(context, cell),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isToday ? AppTheme.emerald : Colors.transparent,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              // English digits only — plain toString().
              '${cell.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                fontSize: 16,
                color: isToday ? Colors.black : Colors.white,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              // "~8" for predicted, "✓8" hidden — marker only for "~".
              // Confirmed dates show plain number (legend explains).
              '${marker == '~' ? '~' : ''}${hijri.day}',
              style: TextStyle(
                fontSize: 10,
                color: hijriColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
