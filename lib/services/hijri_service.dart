import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'prefs_service.dart';

/// A single Hijri date.
class HijriDate {
  const HijriDate({
    required this.year,
    required this.month,
    required this.day,
    required this.monthNameEn,
    required this.monthNameUr,
    required this.confidence,
  });

  final int year;
  final int month;
  final int day;

  /// English month name, e.g. "Jamadi-ul-Awwal".
  final String monthNameEn;

  /// Urdu month name from the API, e.g. "جمادی الاول".
  final String monthNameUr;

  /// "confirmed" | "estimated" | "predicted" | "unconfirmed" | "calculated".
  final String confidence;

  /// True when this date came from the arithmetical fallback rather
  /// than sighted data — shown with a "calculated" indicator in UI.
  bool get isCalculated => confidence == 'calculated';

  /// Short marker for day cells: "✓" = sighted-confirmed,
  /// "~" = estimated/predicted (until moon sighting).
  /// Calculated dates use amber color instead (no marker).
  String get confidenceMarker {
    switch (confidence) {
      case 'confirmed':
        return '✓';
      case 'estimated':
      case 'predicted':
      case 'unconfirmed':
        return '~';
      default:
        return '';
    }
  }

  /// Human-readable confidence for detail views. Always English.
  String get confidenceLabel {
    switch (confidence) {
      case 'confirmed':
        return 'Confirmed (moon sighted)';
      case 'estimated':
        return 'Estimated (no verified sighting record)';
      case 'predicted':
        return 'Predicted (until moon sighting)';
      case 'unconfirmed':
        return 'Unconfirmed (sighting pending)';
      case 'calculated':
        return 'Calculated (arithmetical, not sighted)';
      default:
        return confidence;
    }
  }

  /// "8 Jamadi-ul-Awwal 1448" — always English digits.
  String get display => '$day $monthNameEn $year';

  /// "8 جمادی الاول 1448" — Urdu name, still English digits.
  String get displayUr => '$day $monthNameUr $year';

  /// "Jamadi-ul-Awwal 1448" — always English digits.
  String get monthYear => '$monthNameEn $year';

  /// "جمادی الاول 1448" — Urdu name, still English digits.
  String get monthYearUr => '$monthNameUr $year';
}

/// Offline Hijri calendar backed by bundled sighted data
/// (hijri-api, Pakistan) with an arithmetical fallback for
/// out-of-coverage dates.
///
/// When online, [syncFromNetwork] silently refreshes the data from the
/// hijri-api and caches it locally; offline it uses the cache, else the
/// bundled copy.
class HijriService {
  HijriService._();

  static final HijriService instance = HijriService._();

  /// v2.36: Pakistani spellings (user-specified 2026-10-20).
  static const List<String> monthNamesEn = [
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
  ];

  /// v2.34: Urdu month names (match the API's month_name.ur).
  static const List<String> monthNamesUr = [
    'محرم',
    'صفر',
    'ربیع الاول',
    'ربیع الثانی',
    'جمادی الاول',
    'جمادی الثانی',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدہ',
    'ذو الحجہ',
  ];

  static const String _apiBase = 'https://shaheeranser.github.io/hijri-api';
  static const List<int> _years = [1447, 1448, 1449];

  final Map<String, HijriDate> _byGregorian = {};
  bool _loaded = false;

  /// ISO timestamp from the data's `generated_at` ("" if unknown).
  String _generatedAt = '';

  /// "cached" when synced data is in use, else "bundled".
  String _dataSource = 'bundled';

  bool get isLoaded => _loaded;

  /// "17 Oct 2026" — English digits, for the "last updated" indicator.
  /// Empty string when unknown.
  String get dataUpdatedLabel {
    if (_generatedAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(_generatedAt).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String get dataSource => _dataSource;

  /// Load cached data if present, else bundled JSON. Safe to call
  /// multiple times.
  Future<void> load() async {
    if (_loaded) return;
    await _loadData();
    _loaded = true;
  }

  Future<void> _loadData() async {
    _byGregorian.clear();
    _generatedAt = '';
    _dataSource = 'bundled';
    for (final year in _years) {
      String? raw = await _cached(year);
      if (raw != null) _dataSource = 'cached';
      raw ??= await _bundled(year);
      if (raw == null) continue;
      _parseYear(raw);
    }
    // v2.34: consistency pass — a confirmed/predicted month start must not
    // leave a duplicate 1st or a 28-day month behind it.
    _enforceMonthBoundaries();
    // If any year came from cache, the whole set is "cached".
    // (Sync always writes all three together.)
  }

  /// Cached JSON from a previous sync. Null on miss or when the
  /// platform channel is unavailable (e.g. widget tests).
  Future<String?> _cached(int year) async {
    try {
      return await PrefsService.getString('hijri_cache_$year');
    } catch (_) {
      return null;
    }
  }

  Future<String?> _bundled(int year) async {
    try {
      return await rootBundle.loadString('assets/hijri/$year.json');
    } catch (_) {
      return null;
    }
  }

  void _parseYear(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final gen = decoded['generated_at'] as String? ?? '';
      if (gen.compareTo(_generatedAt) > 0) _generatedAt = gen;
      final days = decoded['days'] as Map<String, dynamic>;
      for (final entry in days.entries) {
        final v = entry.value as Map<String, dynamic>;
        // v2.36: derive the English month name from the month NUMBER via
        // the Pakistani-spelling static list — never trust the API's
        // month_name.en string (it uses different transliterations).
        final monthNum = ((v['month'] as num).toInt()).clamp(1, 12);
        final monthName = monthNamesEn[monthNum - 1];
        // v2.34: Urdu month name from the API for Urdu locale.
        final monthNameUr =
            (v['month_name'] as Map<String, dynamic>)['ur'] as String? ??
                monthNamesUr[(monthNum - 1).clamp(0, 11)];
        _byGregorian[entry.key] = HijriDate(
          year: (v['year'] as num).toInt(),
          month: (v['month'] as num).toInt(),
          day: (v['day'] as num).toInt(),
          monthNameEn: monthName,
          monthNameUr: monthNameUr,
          confidence: v['confidence'] as String? ?? 'estimated',
        );
      }
    } catch (_) {
      // Corrupt entry — algorithmic fallback covers those dates.
    }
  }

  /// Silently check the hijri-api for newer data and cache it locally.
  /// Never throws; never blocks the UI (call without await).
  Future<void> syncFromNetwork() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final indexBody = await _get(client, '$_apiBase/hijri/index.json',
            const Duration(seconds: 15));
        if (indexBody == null) return;
        final index = jsonDecode(indexBody) as Map<String, dynamic>;
        final remoteGen = index['generated_at'] as String? ?? '';
        if (remoteGen.isEmpty || remoteGen.compareTo(_generatedAt) <= 0) {
          return; // Nothing newer.
        }
        // Download all years; abort (keep old data) on any failure.
        final bodies = <int, String>{};
        for (final year in _years) {
          final body = await _get(
              client,
              '$_apiBase/hijri/calendar/$year.json',
              const Duration(seconds: 30));
          if (body == null) return;
          // Validate before caching.
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          if (!decoded.containsKey('days')) return;
          bodies[year] = body;
        }
        for (final e in bodies.entries) {
          await PrefsService.putString('hijri_cache_${e.key}', e.value);
        }
        await _loadData();
      } finally {
        client.close();
      }
    } catch (_) {
      // Offline or failed — keep current data silently.
    }
  }

  Future<String?> _get(HttpClient client, String url, Duration timeout) async {
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      return await resp.transform(utf8.decoder).join().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// Key used in the bundled data: "YYYY-MM-DD".
  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// v2.34: month-boundary consistency pass over the loaded sighted data.
  ///
  /// The hijri-api baseline can predict a month start one day before the
  /// confirmed sighting (e.g. 2025-06-26 was baseline "1 Muharram" but the
  /// Ruet-e-Hilal sighting confirmed 2025-06-27). That leaves a duplicate
  /// 1st — or, equivalently, a 28-day month — in the grid.
  ///
  /// Rule: if date D is the 1st of Hijri month M, then D-1 MUST be the
  /// 29th or 30th of the previous month. A 28-day Islamic month is
  /// impossible. When the 1st is sighted-confirmed, the previous day is
  /// logically certain too (the confirmed start proves the old month
  /// ended), so it is marked confirmed as well.
  void _enforceMonthBoundaries() {
    final keys = _byGregorian.keys.toList()..sort();
    for (var i = 1; i < keys.length; i++) {
      final prevDate = DateTime.tryParse(keys[i - 1]);
      final curDate = DateTime.tryParse(keys[i]);
      if (prevDate == null ||
          curDate == null ||
          curDate.difference(prevDate).inDays != 1) {
        continue; // Not consecutive days — leave alone.
      }
      final cur = _byGregorian[keys[i]]!;
      if (cur.day != 1) continue;
      final prevMonth = cur.month == 1 ? 12 : cur.month - 1;
      final prevYear = cur.month == 1 ? cur.year - 1 : cur.year;
      final prev = _byGregorian[keys[i - 1]]!;
      final ok = prev.year == prevYear &&
          prev.month == prevMonth &&
          (prev.day == 29 || prev.day == 30);
      if (!ok) {
        _byGregorian[keys[i - 1]] = HijriDate(
          year: prevYear,
          month: prevMonth,
          day: 29,
          monthNameEn: monthNamesEn[prevMonth - 1],
          monthNameUr: monthNamesUr[prevMonth - 1],
          confidence:
              cur.confidence == 'confirmed' ? 'confirmed' : prev.confidence,
        );
      }
    }
  }

  /// Gregorian date for a Hijri (year, month, day), or null when not
  /// found. Searches the loaded sighted data first, then scans a bounded
  /// calculated range (2020-01-01 .. 2032-12-31). Used by "Go to Date".
  DateTime? gregorianForHijri(int year, int month, int day) {
    for (final entry in _byGregorian.entries) {
      final h = entry.value;
      if (h.year == year && h.month == month && h.day == day) {
        return DateTime.tryParse(entry.key);
      }
    }
    var dt = DateTime(2020, 1, 1);
    final end = DateTime(2032, 12, 31);
    while (!dt.isAfter(end)) {
      final h = _calculate(dt);
      if (h.year == year && h.month == month && h.day == day) return dt;
      dt = dt.add(const Duration(days: 1));
    }
    return null;
  }

  /// Hijri date for [date]. Uses cached/bundled sighted data when
  /// available, otherwise the arithmetical (Kuwaiti) algorithm marked
  /// "calculated". Never returns null.
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
      monthNameUr: monthNamesUr[m - 1],
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
