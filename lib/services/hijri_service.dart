import 'dart:convert';

import 'package:flutter/services.dart';

/// A single Hijri date.
class HijriDate {
  const HijriDate({
    required this.year,
    required this.month,
    required this.day,
    required this.monthNameEn,
    required this.confidence,
  });

  final int year;
  final int month;
  final int day;

  /// English month name, e.g. "Jumada al-Awwal".
  final String monthNameEn;

  /// "confirmed" | "estimated" | "predicted" | "unconfirmed" | "calculated".
  final String confidence;

  /// "8 Jumada al-Awwal 1448" — always English digits.
  String get display => '$day $monthNameEn $year';

  /// "Jumada al-Awwal 1448" — always English digits.
  String get monthYear => '$monthNameEn $year';
}

/// Offline Hijri calendar backed by bundled sighted data
/// (hijri-api, Pakistan) with an arithmetical fallback for
/// out-of-coverage dates.
class HijriService {
  HijriService._();

  static final HijriService instance = HijriService._();

  static const List<String> monthNamesEn = [
    'Muharram',
    'Safar',
    'Rabi al-Awwal',
    'Rabi al-Thani',
    'Jumada al-Awwal',
    'Jumada al-Thani',
    'Rajab',
    "Sha'ban",
    'Ramadan',
    'Shawwal',
    "Dhu al-Qa'dah",
    'Dhu al-Hijjah',
  ];

  final Map<String, HijriDate> _byGregorian = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Load bundled JSON once at startup. Safe to call multiple times.
  Future<void> load() async {
    if (_loaded) return;
    for (final year in [1447, 1448, 1449]) {
      try {
        final raw =
            await rootBundle.loadString('assets/hijri/$year.json');
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final days = decoded['days'] as Map<String, dynamic>;
        for (final entry in days.entries) {
          final v = entry.value as Map<String, dynamic>;
          final monthName =
              (v['month_name'] as Map<String, dynamic>)['en'] as String;
          _byGregorian[entry.key] = HijriDate(
            year: (v['year'] as num).toInt(),
            month: (v['month'] as num).toInt(),
            day: (v['day'] as num).toInt(),
            monthNameEn: monthName,
            confidence: v['confidence'] as String? ?? 'estimated',
          );
        }
      } catch (_) {
        // Best effort: a missing year just means the algorithmic
        // fallback covers those dates.
      }
    }
    _loaded = true;
  }

  /// Key used in the bundled data: "YYYY-MM-DD".
  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Hijri date for [date]. Uses bundled sighted data when available,
  /// otherwise the arithmetical (Kuwaiti) algorithm. Never returns null.
  HijriDate hijriFor(DateTime date) {
    final key = _key(DateTime(date.year, date.month, date.day));
    final known = _byGregorian[key];
    if (known != null) return known;
    return _calculate(date);
  }

  /// Arithmetical Hijri conversion (Kuwaiti algorithm). Approximate
  /// (±1 day vs sighting) — marked "calculated".
  HijriDate _calculate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    var jd = _gregorianToJd(d.year, d.month, d.day);
    var l = jd - 1948440 + 10632;
    final n = (l - 1) ~/ 10631;
    l = l - 10631 * n + 354;
    final j = ((10985 - l) ~/ 5316) * ((50 * l) ~/ 17719) +
        (l ~/ 5670) * ((43 * l) ~/ 15238);
    l = l -
        ((30 - j) ~/ 15) * ((17719 * j) ~/ 50) -
        (j ~/ 16) * ((15238 * j) ~/ 43) +
        29;
    final month = (24 * l) ~/ 709;
    final day = l - (709 * month) ~/ 24;
    final year = 30 * n + j - 30;
    final m = month.clamp(1, 12);
    return HijriDate(
      year: year,
      month: m,
      day: day.clamp(1, 30),
      monthNameEn: monthNamesEn[m - 1],
      confidence: 'calculated',
    );
  }

  /// Julian day number for a Gregorian date.
  int _gregorianToJd(int y, int m, int d) {
    final a = (14 - m) ~/ 12;
    final yy = y + 4800 - a;
    final mm = m + 12 * a - 3;
    return d +
        ((153 * mm + 2) ~/ 5) +
        365 * yy +
        (yy ~/ 4) -
        (yy ~/ 100) +
        (yy ~/ 400) -
        32045;
  }
}
