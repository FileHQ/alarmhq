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
  /// "~" = estimated/predicted/calculated (until moon sighting).
  /// v2.49: calculated dates also use "~" (amber color removed per user).
  String get confidenceMarker {
    switch (confidence) {
      case 'confirmed':
        return '✓';
      case 'estimated':
      case 'predicted':
      case 'unconfirmed':
      case 'calculated':
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
        return 'Estimated (arithmetical)';
      default:
        return confidence;
    }
  }

  /// Urdu variant of [confidenceLabel] for the Urdu locale.
  /// Always English digits where digits appear.
  String get confidenceLabelUr {
    switch (confidence) {
      case 'confirmed':
        return 'تصدیق شدہ (چاند نظر آیا)';
      case 'estimated':
        return 'اندازاً (تصدیق شدہ ریکارڈ نہیں)';
      case 'predicted':
        return 'اندازاً (چاند نظر آنے تک)';
      case 'unconfirmed':
        return 'غیر تصدیق شدہ (چاند نظر آنا باقی)';
      case 'calculated':
        return 'اندازاً (حساب سے)';
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

  /// v2.43: Umm al-Qura month-start table (JDNs), 1937–2077, from
  /// assets/hijri/ummalqura.json. Empty when the asset is unavailable
  /// (widget tests) — the arithmetic fallback then covers everything.
  List<int> _uqStarts = [];
  int _uqStartHy = 0;
  int _uqStartHm = 0;

  /// v2.49: triple-verified Pakistan moon-sighting month starts
  /// (1424-12 → 1448-05), from assets/hijri/verified.json.
  /// Read directly from newspaper mastheads (Daily Express +
  /// Business Recorder); masthead is final authority. These take
  /// precedence over everything else and are always "confirmed".
  final List<_VerifiedMonth> _verified = [];

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

  /// v2.38: Urdu version — "17 اکتوبر 2026" (Urdu month name,
  /// English digits). Empty string when unknown.
  String get dataUpdatedLabelUr {
    if (_generatedAt.isEmpty) return '';
    try {
      final dt = DateTime.parse(_generatedAt).toLocal();
      const months = [
        'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
        'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
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
    // v2.37: the API's predicted data sometimes skips day 1 of a month
    // entirely (e.g. 2026-11-11 = 30 Jumada al-Awwal -> 2026-11-12 = 2
    // Jumada al-Thani). The grid must show a continuous sequence, so
    // relabel the mislabeled "30 (unconfirmed)" as the predicted 1st.
    _fixSkippedDayOne();
    // v2.37: Pakistan-adjust predictions (-1 day from Umm al-Qura).
    // Pakistani sightings typically lag Umm al-Qura by a day.
    _applyPakistanShift();
    // v2.43: Umm al-Qura month-start table for out-of-API dates.
    await _loadUmmalqura();
    // v2.49: triple-verified masthead data (confirmed, highest priority).
    await _loadVerified();
    // If any year came from cache, the whole set is "cached".
    // (Sync always writes all three together.)
  }

  /// Load the Umm al-Qura table; silently keep the arithmetic fallback
  /// when the asset can't be read (e.g. widget tests without binding).
  Future<void> _loadUmmalqura() async {
    _uqStarts = [];
    try {
      final raw =
          await rootBundle.loadString('assets/hijri/ummalqura.json');
      final d = jsonDecode(raw) as Map<String, dynamic>;
      _uqStartHy = (d['start_hy'] as num).toInt();
      _uqStartHm = (d['start_hm'] as num).toInt();
      _uqStarts = (d['month_start_jdns'] as List)
          .map((e) => (e as num).toInt())
          .toList();
    } catch (_) {
      _uqStarts = [];
    }
  }

  /// v2.49: load the triple-verified month starts
  /// (assets/hijri/verified.json, {"1424-12": "2004-01-24", ...}).
  /// Silently empty when the asset can't be read (widget tests).
  Future<void> _loadVerified() async {
    _verified.clear();
    try {
      final raw =
          await rootBundle.loadString('assets/hijri/verified.json');
      final d = jsonDecode(raw) as Map<String, dynamic>;
      for (final e in d.entries) {
        final keyParts = e.key.split('-');
        final dateParts = (e.value as String).split('-');
        _verified.add(_VerifiedMonth(
          DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
          ),
          int.parse(keyParts[0]),
          int.parse(keyParts[1]),
        ));
      }
      _verified.sort((a, b) => a.start.compareTo(b.start));
    } catch (_) {
      _verified.clear();
    }
  }

  /// v2.49: Hijri date from the verified month starts, or null when
  /// [date] is outside the verified range. Always "confirmed".
  HijriDate? _verifiedHijri(DateTime date) {
    if (_verified.length < 2) return null;
    final d = DateTime(date.year, date.month, date.day);
    if (d.isBefore(_verified.first.start)) return null;
    // Binary search: latest month start <= d.
    var lo = 0, hi = _verified.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (!_verified[mid].start.isAfter(d)) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (ans < 0) return null;
    final m = _verified[ans];
    // Month end = next month's start. v2.89: the last verified month
    // is capped at 29 days, NOT 30 — a Hijri 30th is never confirmed
    // in advance (if the new moon is sighted on the 29th, the next
    // day is the 1st, not the 30th). Day 30 of the last month falls
    // through to the predicted path (~30) until a later data update
    // verifies the next month's start, which then confirms it.
    final endExclusive = ans + 1 < _verified.length
        ? _verified[ans + 1].start
        : m.start.add(const Duration(days: 29));
    if (!d.isBefore(endExclusive)) return null;
    final day = d.difference(m.start).inDays + 1;
    return HijriDate(
      year: m.hy,
      month: m.hm,
      day: day,
      monthNameEn: monthNamesEn[m.hm - 1],
      monthNameUr: monthNamesUr[m.hm - 1],
      confidence: 'confirmed',
    );
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

  /// v2.37: fix a skipped day 1 caused by a mislabeled "30 (unconfirmed)".
  ///
  /// Observed in the API data: 2026-11-11 is labeled "30 Jumada al-Awwal
  /// (unconfirmed)" while 2026-11-12 is "2 Jumada al-Thani (predicted)" —
  /// the ~1 never appears. But the tail (2..29, then 1 Rajab on Dec 10)
  /// is self-consistent ONLY if 2026-11-11 is really the 1st: Jumada
  /// al-Thani then runs 1..29 (29 days) and Jumada al-Awwal ends at 29.
  /// (Renumbering the tail down instead would create an impossible
  /// 28-day month.) So relabel that day as the predicted 1st of the new
  /// month. Confirmed (sighted) entries are never touched, and the tail
  /// length is sanity-checked (28 -> 29-day month, 29 -> 30-day month);
  /// anything else is left alone rather than guessed at.
  void _fixSkippedDayOne() {
    final keys = _byGregorian.keys.toList()..sort();
    for (var i = 1; i < keys.length; i++) {
      final prevDate = DateTime.tryParse(keys[i - 1]);
      final curDate = DateTime.tryParse(keys[i]);
      if (prevDate == null ||
          curDate == null ||
          curDate.difference(prevDate).inDays != 1) {
        continue; // Not consecutive days — leave alone.
      }
      final prev = _byGregorian[keys[i - 1]]!;
      final cur = _byGregorian[keys[i]]!;
      final isNewMonth = cur.year != prev.year || cur.month != prev.month;
      final isMislabeledStart = isNewMonth &&
          prev.day == 30 &&
          cur.day == 2 &&
          prev.confidence != 'confirmed' &&
          cur.confidence != 'confirmed';
      if (!isMislabeledStart) continue;
      // Sanity-check the tail: it must run 2..29 (28 entries -> 29-day
      // month) or 2..30 (29 entries -> 30-day month).
      var tailLen = 0;
      var j = i;
      var expected = 2;
      while (j < keys.length) {
        final e = _byGregorian[keys[j]]!;
        if (e.year != cur.year ||
            e.month != cur.month ||
            e.day != expected) {
          break;
        }
        tailLen++;
        expected++;
        j++;
      }
      if (tailLen != 28 && tailLen != 29) continue;
      _byGregorian[keys[i - 1]] = HijriDate(
        year: cur.year,
        month: cur.month,
        day: 1,
        monthNameEn: cur.monthNameEn,
        monthNameUr: cur.monthNameUr,
        confidence: 'predicted',
      );
    }
  }

  /// v2.37: Pakistan-adjust predicted dates (-1 day from Umm al-Qura).
  ///
  /// Pakistani moon sightings typically lag Umm al-Qura by a day, so for
  /// every PREDICTED or UNCONFIRMED (future, non-sighted) date the
  /// displayed Hijri date is the Umm al-Qura date minus one Hijri day.
  /// "Confirmed" and "estimated" dates are already Pakistani and are not
  /// touched. The "~" marker is kept — these remain estimates.
  ///
  /// The subtraction is proper Hijri arithmetic, not a naive day-number
  /// decrement (which would break month continuity):
  /// - day > 1: decrement the day number.
  /// - day == 1: the previous Gregorian day's ORIGINAL entry is the
  ///   correct Umm al-Qura month end — unless it is confirmed/estimated
  ///   (the sighting fixed the month): then a 30-day confirmed month
  ///   means the API's 1st stands, while a 29-day one means Umm al-Qura
  ///   likely has 30, so the 30th is shown.
  void _applyPakistanShift() {
    final keys = _byGregorian.keys.toList()..sort();
    // Snapshot pre-shift values: the shift of G reads G-1's ORIGINAL.
    final original = Map<String, HijriDate>.from(_byGregorian);
    for (var i = 0; i < keys.length; i++) {
      final cur = original[keys[i]]!;
      if (cur.confidence != 'predicted' && cur.confidence != 'unconfirmed') {
        continue;
      }
      HijriDate shifted;
      if (cur.day > 1) {
        shifted = HijriDate(
          year: cur.year,
          month: cur.month,
          day: cur.day - 1,
          monthNameEn: cur.monthNameEn,
          monthNameUr: cur.monthNameUr,
          confidence: cur.confidence,
        );
      } else {
        if (i == 0) continue;
        final prevDate = DateTime.tryParse(keys[i - 1]);
        final curDate = DateTime.tryParse(keys[i]);
        if (prevDate == null ||
            curDate == null ||
            curDate.difference(prevDate).inDays != 1) {
          continue;
        }
        final prev = original[keys[i - 1]]!;
        if (prev.confidence == 'predicted' ||
            prev.confidence == 'unconfirmed') {
          shifted = HijriDate(
            year: prev.year,
            month: prev.month,
            day: prev.day,
            monthNameEn: prev.monthNameEn,
            monthNameUr: prev.monthNameUr,
            confidence: cur.confidence,
          );
        } else if (prev.day >= 30) {
          // Sighting fixed a 30-day month: the API's 1st stands.
          shifted = cur;
        } else {
          // 29-day confirmed month: Umm al-Qura likely has 30.
          shifted = HijriDate(
            year: prev.year,
            month: prev.month,
            day: 30,
            monthNameEn: prev.monthNameEn,
            monthNameUr: prev.monthNameUr,
            confidence: cur.confidence,
          );
        }
      }
      _byGregorian[keys[i]] = shifted;
    }
  }

  /// Gregorian date for a Hijri (year, month, day), or null when not
  /// found. Searches the verified data first, then the loaded sighted
  /// data, then scans a bounded calculated range (2020-01-01 ..
  /// 2032-12-31). Used by "Go to Date".
  DateTime? gregorianForHijri(int year, int month, int day) {
    // v2.49: verified months — exact, no scan needed.
    for (var i = 0; i < _verified.length; i++) {
      final m = _verified[i];
      if (m.hy == year && m.hm == month) {
        final endExclusive = i + 1 < _verified.length
            ? _verified[i + 1].start
            : m.start.add(const Duration(days: 30));
        final monthLen = endExclusive.difference(m.start).inDays;
        if (day < 1 || day > monthLen) return null;
        return m.start.add(Duration(days: day - 1));
      }
    }
    // v2.49: API contributes only confirmed dates (user order);
    // predicted API entries are skipped so the Umm al-Qura scan below
    // stays consistent with hijriFor.
    for (final entry in _byGregorian.entries) {
      final h = entry.value;
      if (h.confidence != 'confirmed') continue;
      if (h.year == year && h.month == month && h.day == day) {
        return DateTime.tryParse(entry.key);
      }
    }
    // v2.43: extended range (1900–2100 Gregorian / ~1318–1525 Hijri).
    // Start the scan from an estimated Gregorian year to keep it fast.
    final estYear = (year * 0.970229 + 621.5643).floor() - 2;
    var dt = DateTime(estYear.clamp(1900, 2098), 1, 1);
    final end = DateTime((estYear + 5).clamp(1902, 2100), 12, 31);
    while (!dt.isAfter(end)) {
      // v2.37: match the Pakistan-shifted display.
      // v2.43: same priority as hijriFor (Umm al-Qura → arithmetic).
      final h = _estimatedHijri(dt);
      if (h.year == year && h.month == month && h.day == day) return dt;
      dt = dt.add(const Duration(days: 1));
    }
    return null;
  }

  /// Hijri date for [date]. Priority (v2.49, user order):
  /// 1. triple-verified masthead month starts (confirmed).
  /// 2. hijri-api data — CONFIRMED entries only. The API's predicted /
  ///    unconfirmed entries are skipped; Umm al-Qura covers those dates.
  /// 3-4. (below) everything else — Umm al-Qura table or arithmetic.
  /// Never returns null.
  HijriDate hijriFor(DateTime date) {
    final verified = _verifiedHijri(date);
    if (verified != null) return verified;
    final key = _key(DateTime(date.year, date.month, date.day));
    final known = _byGregorian[key];
    // v2.49: from the API, take only confirmed dates (user order).
    if (known != null && known.confidence == 'confirmed') return known;
    return _estimatedHijri(date);
  }

  /// Out-of-API estimate. Pakistan(G) = UmmAlQura(G - 1 day) (v2.37).
  /// v2.43 priority:
  /// 3. inside 1937–2077 → Umm al-Qura table, marked "~" (predicted);
  /// 4. outside → arithmetical (Kuwaiti) fallback, marked "~" like
  ///    estimated (v2.49: no separate color/legend for calculated).
  HijriDate _estimatedHijri(DateTime date) {
    final shifted = date.subtract(const Duration(days: 1));
    final uq = _ummalquraFor(shifted);
    if (uq != null) return uq;
    return _calculate(shifted);
  }

  /// Umm al-Qura Hijri date for [date] (caller applies the Pakistan
  /// shift). Null when outside the table's 1937–2077 range or when the
  /// asset failed to load (tests).
  HijriDate? _ummalquraFor(DateTime date) {
    if (_uqStarts.length < 2) return null;
    final jdn = _gregorianToJd(date.year, date.month, date.day);
    if (jdn < _uqStarts.first || jdn >= _uqStarts.last) return null;
    // Binary search: largest i with _uqStarts[i] <= jdn.
    var lo = 0, hi = _uqStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_uqStarts[mid] <= jdn) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final absMonth =
        (_uqStartHy - 1) * 12 + (_uqStartHm - 1) + lo;
    final hy = absMonth ~/ 12 + 1;
    final hm = absMonth % 12 + 1;
    final day = jdn - _uqStarts[lo] + 1;
    return HijriDate(
      year: hy,
      month: hm,
      day: day,
      monthNameEn: monthNamesEn[hm - 1],
      monthNameUr: monthNamesUr[hm - 1],
      confidence: 'predicted',
    );
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

/// v2.49: a triple-verified Hijri month start.
class _VerifiedMonth {
  const _VerifiedMonth(this.start, this.hy, this.hm);
  final DateTime start;
  final int hy;
  final int hm;
}
