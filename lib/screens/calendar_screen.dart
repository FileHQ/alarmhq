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

  // v2.37: the date the user jumped to via "Go to Date" — highlighted in
  // lime so she can see "we arrived here". Cleared on manual month change
  // or when another date is tapped.
  DateTime? _jumpedDate;

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

  // v2.38: abbreviated month names for the Go-to-Date steppers —
  // "November" wrapped mid-word ("Novembe r") on narrow screens.
  static const List<String> _monthNamesEnShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // v2.34: Urdu month names for Urdu locale. Digits stay English.
  static const List<String> _monthNamesUr = [
    'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
    'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
  ];

  static const List<String> _dowEn = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  // v2.34: Urdu weekday names.
  static const List<String> _dowUr = [
    'پیر', 'منگل', 'بدھ', 'جمعرات', 'جمعہ', 'ہفتہ', 'اتوار'
  ];

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
      // v2.37: manual navigation clears the jump highlight.
      _jumpedDate = null;
    });
  }

  // v2.38: "Today" button — jump back to the current month.
  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month, 1);
      _jumpedDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // v2.34: month/weekday NAMES follow the locale; digits stay English.
    final isUrdu = l10n.localeName == 'ur';
    final monthNames = isUrdu ? _monthNamesUr : _monthNamesEn;
    final dow = isUrdu ? _dowUr : _dowEn;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(_month.year, _month.month, 1);
    // English digits guaranteed: hardcoded names + toString().
    final monthTitle =
        '${monthNames[monthStart.month - 1]} ${monthStart.year}';

    // Monday-first offset.
    final leading = (monthStart.weekday - 1) % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_month.year, _month.month, d),
    ];

    // v2.34: header shows EVERY Hijri month visible in the grid
    // (e.g. "Zil-Hajj 1446 / Muharram 1447"), like the mockup.
    // Urdu locale uses Urdu month names; digits stay English.
    final hijriMonths = <String>[];
    for (final cell in cells) {
      if (cell == null) continue;
      final h = HijriService.instance.hijriFor(cell);
      final my = isUrdu ? h.monthYearUr : h.monthYear;
      if (!hijriMonths.contains(my)) hijriMonths.add(my);
    }
    final hijriHeader = hijriMonths.join(' / ');

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.calendar),
        centerTitle: false,
        actions: [
          // v2.38: "Today" — jump back to the current month.
          TextButton(
            onPressed: _goToToday,
            child: Text(l10n.todayBtn,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          // v2.34: "Go to Date" — jump via Gregorian or Hijri date.
          IconButton(
            icon: const Icon(Icons.event),
            tooltip: l10n.goToDate,
            onPressed: () => _showGoToDate(context),
          ),
        ],
      ),
      // v2.35: swipe left/right on the calendar card to change months
      // (in addition to the arrow buttons).
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          if (v < 0) {
            _changeMonth(1); // swipe left -> next month
          } else if (v > 0) {
            _changeMonth(-1); // swipe right -> previous month
          }
        },
        child: SingleChildScrollView(
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
                  // v2.35: header wraps to 2 lines so long Hijri month
                  // names (e.g. "Zil-Qadah 1446 / Zil-Hajj 1446")
                  // are never cut off at the screen edge.
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          monthTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hijriHeader,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          softWrap: true,
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
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
                      // v2.41: FittedBox prevents جمعرات wrapping to 2 lines.
                      // Jameel Noori is tall; scale down to fit one line.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(h,
                            maxLines: 1,
                            style: const TextStyle(
                                color: Colors.white38,
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ),
                    ),
                  for (final cell in cells)
                    if (cell == null)
                      const SizedBox.shrink()
                    else
                      _dayCell(cell, today),
                ],
              ),
              const SizedBox(height: 8),
              // v2.41: localized calendar hint (Urdu: "اوپر: عیسوی • ...").
              // v2.42: reduced by 2sp per user request.
              Text(
                l10n.calendarHint,
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: isUrdu ? 12 : 9),
              ),
              const SizedBox(height: 2),
              // v2.38: confidence legend — localized per user decision.
              // v2.41: larger size for Urdu (Jameel Noori unreadable at 11).
              // v2.42: " • " separators between items per user request.
              // v2.43: real visual spacing (Wrap with spacing, not just dots).
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 24,
                runSpacing: 4,
                children: [
                  Text(
                    l10n.legendConfirmed,
                    style: TextStyle(
                        fontSize: isUrdu ? 15 : 11, color: Colors.white38),
                  ),
                  Text(
                    l10n.legendPredicted,
                    style: TextStyle(
                        fontSize: isUrdu ? 15 : 11, color: Colors.white38),
                  ),
                  Text(
                    l10n.legendCalculated,
                    style: TextStyle(
                        fontSize: isUrdu ? 15 : 11,
                        color: Colors.amber.shade300),
                  ),
                ],
              ),
              if (HijriService.instance.dataUpdatedLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    // v2.38: "Data update: 17 Oct 2026" /
                    // "ڈیٹا اپڈیٹ: 17 اکتوبر 2026".
                    // v2.41: larger for Urdu readability.
                    '${l10n.dataUpdate} ${isUrdu ? HijriService.instance.dataUpdatedLabelUr : HijriService.instance.dataUpdatedLabel}',
                    style: TextStyle(
                        color: Colors.white24,
                        fontSize: isUrdu ? 14 : 10),
                  ),
                ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// v2.34: "Go to Date" dialog — jump the calendar via a Gregorian
  /// or Hijri date. All digits English (toString only).
  ///
  /// v2.37: DROPDOWNS REMOVED. They rendered blank on the user's Realme
  /// (v2.35/v2.36 fixes didn't stick on device), so the dialog now uses
  /// [-] value [+] steppers and [<] month [>] arrows — nothing that can
  /// go blank. Also sets _jumpedDate so the landed date gets a lime
  /// outline (today keeps its full fill).
  void _showGoToDate(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // v2.34: month names follow locale; digits stay English.
    // v2.38: abbreviated Gregorian names in steppers ("November"
    // wrapped mid-word as "Novembe r" on her phone).
    final isUrdu = l10n.localeName == 'ur';
    final gMonthNames = isUrdu ? _monthNamesUr : _monthNamesEnShort;
    final hMonthNames = isUrdu
        ? HijriService.monthNamesUr
        : HijriService.monthNamesEn;
    final now = DateTime.now();
    // v2.43: wide year range 1900–2100 (calculated fallback covers it).
    int gYear = now.year.clamp(1900, 2100),
        gMonth = now.month,
        gDay = now.day;
    int hYear = 1448, hMonth = 5, hDay = 8;
    try {
      final h = HijriService.instance.hijriFor(now);
      hYear = h.year.clamp(1318, 1525);
      hMonth = h.month.clamp(1, 12);
      hDay = h.day.clamp(1, 30);
    } catch (_) {}

    // v2.35: track the selected Go-to-Date tab directly (DefaultTabController
    // is a child of the dialog builder's ctx, so .of() returns null).
    int tabIndex = 0;

    int gDaysIn(int y, int m) => DateTime(y, m + 1, 0).day;

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        // v2.37: StatefulBuilder so stepper taps repaint the dialog.
        child: StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            /// One stepper row: label | [-] value [+] .
            /// v2.43: the value is tappable — opens a numeric field so the
            /// user can type directly (in addition to the +/- buttons).
            Widget stepper({
              required String label,
              required String value,
              required VoidCallback onMinus,
              required VoidCallback onPlus,
              required VoidCallback onTapValue,
            }) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(label,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: onMinus,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: onTapValue,
                        child: Text(
                          // English digits only — plain toString().
                          value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: onPlus,
                    ),
                  ],
                ),
              );
            }

            /// v2.43: numeric input dialog for tap-to-type on stepper values.
            /// Returns the validated (clamped) number, or null if cancelled.
            Future<int?> promptNumber({
              required String title,
              required int current,
              required int min,
              required int max,
            }) {
              final ctrl = TextEditingController(text: '$current');
              int? parse() {
                final n = int.tryParse(ctrl.text.trim());
                if (n == null) return null;
                return n.clamp(min, max);
              }

              return showDialog<int>(
                context: dialogCtx,
                builder: (c) => AlertDialog(
                  title: Text(title),
                  content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    // English digits only.
                    decoration: InputDecoration(
                      hintText: '$min – $max',
                      helperText: '$min – $max',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(),
                      child: Text(l10n.cancel),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(c).pop(parse()),
                      child: Text(l10n.go),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: Text(l10n.goToDate),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TabBar(
                      onTap: (i) => tabIndex = i,
                      tabs: [
                        Tab(text: l10n.gregorian),
                        Tab(text: l10n.hijri)
                      ],
                    ),
                    SizedBox(
                      height: 220,
                      child: TabBarView(
                        children: [
                          // Gregorian tab — steppers, no dropdowns.
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              children: [
                                stepper(
                                  label: l10n.yearLabel,
                                  value: '$gYear',
                                  onMinus: () => setDialogState(() {
                                    if (gYear > 1900) gYear--;
                                    gDay = gDay.clamp(
                                        1, gDaysIn(gYear, gMonth));
                                  }),
                                  onPlus: () => setDialogState(() {
                                    if (gYear < 2100) gYear++;
                                    gDay = gDay.clamp(
                                        1, gDaysIn(gYear, gMonth));
                                  }),
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.yearLabel,
                                      current: gYear,
                                      min: 1900,
                                      max: 2100,
                                    );
                                    if (v != null) {
                                      setDialogState(() {
                                        gYear = v;
                                        gDay = gDay.clamp(
                                            1, gDaysIn(gYear, gMonth));
                                      });
                                    }
                                  },
                                ),
                                stepper(
                                  label: l10n.monthLabel,
                                  value: gMonthNames[gMonth - 1],
                                  onMinus: () => setDialogState(() {
                                    gMonth = gMonth == 1 ? 12 : gMonth - 1;
                                    gDay = gDay.clamp(
                                        1, gDaysIn(gYear, gMonth));
                                  }),
                                  onPlus: () => setDialogState(() {
                                    gMonth = gMonth == 12 ? 1 : gMonth + 1;
                                    gDay = gDay.clamp(
                                        1, gDaysIn(gYear, gMonth));
                                  }),
                                  // v2.43: type the month number 1–12.
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.monthLabel,
                                      current: gMonth,
                                      min: 1,
                                      max: 12,
                                    );
                                    if (v != null) {
                                      setDialogState(() {
                                        gMonth = v;
                                        gDay = gDay.clamp(
                                            1, gDaysIn(gYear, gMonth));
                                      });
                                    }
                                  },
                                ),
                                stepper(
                                  label: l10n.dayLabel,
                                  value: '$gDay',
                                  onMinus: () => setDialogState(() {
                                    final max =
                                        gDaysIn(gYear, gMonth);
                                    gDay = gDay == 1 ? max : gDay - 1;
                                  }),
                                  onPlus: () => setDialogState(() {
                                    final max =
                                        gDaysIn(gYear, gMonth);
                                    gDay = gDay == max ? 1 : gDay + 1;
                                  }),
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.dayLabel,
                                      current: gDay,
                                      min: 1,
                                      max: gDaysIn(gYear, gMonth),
                                    );
                                    if (v != null) {
                                      setDialogState(() => gDay = v);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          // Hijri tab — steppers, no dropdowns.
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Column(
                              children: [
                                stepper(
                                  label: l10n.yearLabel,
                                  value: '$hYear',
                                  onMinus: () => setDialogState(() {
                                    if (hYear > 1318) hYear--;
                                  }),
                                  onPlus: () => setDialogState(() {
                                    if (hYear < 1525) hYear++;
                                  }),
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.yearLabel,
                                      current: hYear,
                                      min: 1318,
                                      max: 1525,
                                    );
                                    if (v != null) {
                                      setDialogState(() => hYear = v);
                                    }
                                  },
                                ),
                                stepper(
                                  label: l10n.monthLabel,
                                  value: hMonthNames[hMonth - 1],
                                  onMinus: () => setDialogState(() {
                                    hMonth = hMonth == 1 ? 12 : hMonth - 1;
                                  }),
                                  onPlus: () => setDialogState(() {
                                    hMonth = hMonth == 12 ? 1 : hMonth + 1;
                                  }),
                                  // v2.43: type the month number 1–12.
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.monthLabel,
                                      current: hMonth,
                                      min: 1,
                                      max: 12,
                                    );
                                    if (v != null) {
                                      setDialogState(() => hMonth = v);
                                    }
                                  },
                                ),
                                stepper(
                                  label: l10n.dayLabel,
                                  value: '$hDay',
                                  onMinus: () => setDialogState(() {
                                    hDay = hDay == 1 ? 30 : hDay - 1;
                                  }),
                                  onPlus: () => setDialogState(() {
                                    hDay = hDay == 30 ? 1 : hDay + 1;
                                  }),
                                  onTapValue: () async {
                                    final v = await promptNumber(
                                      title: l10n.dayLabel,
                                      current: hDay,
                                      min: 1,
                                      max: 30,
                                    );
                                    if (v != null) {
                                      setDialogState(() => hDay = v);
                                    }
                                  },
                                ),
                                const SizedBox(height: 4),
                                // v2.43: localized (was hardcoded English).
                                Text(
                                  l10n.predictedNote,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    final tab = tabIndex;
                    Navigator.of(dialogCtx).pop();
                    if (tab == 0) {
                      // v2.37: jump + lime-highlight the landed date.
                      final target = DateTime(gYear, gMonth,
                          gDay.clamp(1, gDaysIn(gYear, gMonth)));
                      setState(() {
                        _month =
                            DateTime(target.year, target.month, 1);
                        _jumpedDate = target;
                      });
                    } else {
                      final target =
                          HijriService.instance.gregorianForHijri(
                              hYear, hMonth, hDay);
                      if (target != null) {
                        setState(() {
                          _month =
                              DateTime(target.year, target.month, 1);
                          _jumpedDate = DateTime(target.year,
                              target.month, target.day);
                        });
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(l10n.dateNotFound)),
                        );
                      }
                    }
                  },
                  child: Text(l10n.go),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Tap a date → detail dialog with full Hijri date + confidence.
  void _showDateDetail(BuildContext context, DateTime cell) {
    final l10n = AppLocalizations.of(context)!;
    final isUrdu = l10n.localeName == 'ur';
    final hijri = HijriService.instance.hijriFor(cell);
    // v2.34: month names follow locale; digits stay English.
    final monthNames = isUrdu ? _monthNamesUr : _monthNamesEn;
    // v2.43: Urdu uses day-first Pakistani format: "21 اکتوبر 2026".
    final gregorian = isUrdu
        ? '${cell.day} ${monthNames[cell.month - 1]} ${cell.year}'
        : '${monthNames[cell.month - 1]} ${cell.day}, ${cell.year}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gregorian),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUrdu ? hijri.displayUr : hijri.display,
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
                    // v2.43: Urdu label in Urdu locale.
                    isUrdu ? hijri.confidenceLabelUr : hijri.confidenceLabel,
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
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime cell, DateTime today) {
    final isToday = cell.year == today.year &&
        cell.month == today.month &&
        cell.day == today.day;
    // v2.37: jumped-to date (via Go to Date) gets a lime OUTLINE only —
    // today keeps its full lime fill, so the two are distinguishable.
    final isJumped = !isToday &&
        _jumpedDate != null &&
        cell.year == _jumpedDate!.year &&
        cell.month == _jumpedDate!.month &&
        cell.day == _jumpedDate!.day;
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
      onTap: () {
        // v2.37: tapping another date clears the jump highlight.
        if (!isJumped) {
          setState(() => _jumpedDate = null);
        }
        _showDateDetail(context, cell);
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: isToday ? AppTheme.emerald : Colors.transparent,
          border: isJumped
              ? Border.all(color: AppTheme.emerald, width: 2)
              : null,
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
              // v2.38: "✓8" on confirmed (sighted) dates, "~8" on
              // predicted — matches the legend the user asked for.
              // Calculated dates show a plain amber number.
              '$marker${hijri.day}',
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
