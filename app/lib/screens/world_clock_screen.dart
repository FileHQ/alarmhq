import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../services/prefs_service.dart';
import '../theme/app_theme.dart';

/// World Clock tab: user-selected cities with live local times.
///
/// Times tick every second. An optional [nowProvider] supplies the base
/// time (UTC); when the parent passes atomic-corrected time, all cities
/// show atomic time. Otherwise the device clock is used.
///
/// Design notes:
/// - All text uses FontWeight.w400 — JameelNoori has no bold variant and
///   synthetic bold renders blurry on Nastaleeq ligatures.
/// - All digits are English (plain toString/padLeft, never Urdu digits).
class WorldClockScreen extends StatefulWidget {
  final DateTime Function()? nowProvider;

  const WorldClockScreen({super.key, this.nowProvider});

  @override
  State<WorldClockScreen> createState() => _WorldClockScreenState();
}

class _CityEntry {
  final String city;
  final String country;
  final String zone;
  final String cityUr;
  final String countryUr;

  const _CityEntry({
    required this.city,
    required this.country,
    required this.zone,
    this.cityUr = '',
    this.countryUr = '',
  });

  factory _CityEntry.fromJson(Map<String, dynamic> j) => _CityEntry(
        city: (j['city'] as String?) ?? '',
        country: (j['country'] as String?) ?? '',
        zone: (j['zone'] as String?) ?? '',
        cityUr: (j['city_ur'] as String?) ?? '',
        countryUr: (j['country_ur'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'city': city,
        'country': country,
        'zone': zone,
        if (cityUr.isNotEmpty) 'city_ur': cityUr,
        if (countryUr.isNotEmpty) 'country_ur': countryUr,
      };
}

class _WorldClockScreenState extends State<WorldClockScreen> {
  static bool _tzInit = false;
  static const String _prefsKey = 'worldclock_cities';
  static const List<_CityEntry> _defaultCities = [
    _CityEntry(city: 'Karachi', country: 'Pakistan', zone: 'Asia/Karachi'),
    _CityEntry(city: 'Dubai', country: 'United Arab Emirates', zone: 'Asia/Dubai'),
    _CityEntry(city: 'Riyadh', country: 'Saudi Arabia', zone: 'Asia/Riyadh'),
    _CityEntry(city: 'London', country: 'United Kingdom', zone: 'Europe/London'),
    _CityEntry(city: 'New York', country: 'United States', zone: 'America/New_York'),
  ];
  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<_CityEntry> _cities = [];
  List<_CityEntry> _allCities = [];
  bool _loaded = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (!_tzInit) {
      tzdata.initializeTimeZones();
      _tzInit = true;
    }
    _load();
    // Tick every second so all city times stay live.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    List<_CityEntry> all = [];
    try {
      final raw = await rootBundle.loadString('assets/cities.json');
      final list = jsonDecode(raw) as List;
      all = list
          .whereType<Map<String, dynamic>>()
          .map(_CityEntry.fromJson)
          .where((e) => e.zone.isNotEmpty && e.city.isNotEmpty)
          .toList();
    } catch (_) {
      all = [];
    }
    // Meta: zone -> first city (for backward-compat zone-only entries).
    final meta = <String, _CityEntry>{};
    for (final e in all) {
      meta.putIfAbsent(e.zone, () => e);
    }
    // Fast lookup: "city|zone" -> entry.
    final byKey = <String, _CityEntry>{};
    for (final e in all) {
      byKey['${e.city}|${e.zone}'] = e;
    }

    List<_CityEntry> cities;
    try {
      final saved = await PrefsService.getString(_prefsKey);
      if (saved == null) {
        cities = List<_CityEntry>.from(_defaultCities);
      } else {
        final decoded = jsonDecode(saved) as List;
        cities = [];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            // New format: full city object.
            final e = _CityEntry.fromJson(item);
            if (e.zone.isNotEmpty && e.city.isNotEmpty) cities.add(e);
          } else if (item is String) {
            // Old format: zone ID only — resolve via meta.
            final e = meta[item];
            if (e != null) cities.add(e);
          }
        }
        if (cities.isEmpty) cities = List<_CityEntry>.from(_defaultCities);
      }
    } catch (_) {
      cities = List<_CityEntry>.from(_defaultCities);
    }
    // Drop zones the timezone DB doesn't know (defensive).
    cities = cities.where((c) {
      try {
        tz.getLocation(c.zone);
        return true;
      } catch (_) {
        return false;
      }
    }).toList();

    if (!mounted) return;
    setState(() {
      _allCities = all;
      _cities = cities;
      _loaded = true;
    });
    _save();
  }

  Future<void> _save() async {
    try {
      final list = _cities.map((c) => c.toJson()).toList();
      await PrefsService.putString(_prefsKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Base time in UTC: atomic-corrected when the parent provides it,
  /// otherwise the device clock.
  DateTime _baseUtc() {
    final p = widget.nowProvider;
    if (p != null) {
      final t = p();
      return t.isUtc ? t : t.toUtc();
    }
    return DateTime.now().toUtc();
  }

  tz.TZDateTime _cityTime(String zone) {
    return tz.TZDateTime.from(_baseUtc(), tz.getLocation(zone));
  }

  String _fmtTime(tz.TZDateTime t) {
    // v2.55: 12-hour format with AM/PM (her order).
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    String p2(int n) => n.toString().padLeft(2, '0');
    return '$h12:${p2(t.minute)}:${p2(t.second)} $ampm';
  }

  String _fmtDate(tz.TZDateTime t) {
    return '${t.day} ${_monthAbbr[t.month - 1]} ${t.year}';
  }

  String _fmtOffset(Duration d) {
    final neg = d.isNegative;
    final a = d.abs();
    final h = a.inHours;
    final m = a.inMinutes.remainder(60);
    final sign = neg ? '-' : '+';
    if (m == 0) return 'UTC$sign$h';
    return 'UTC$sign$h:${m.toString().padLeft(2, '0')}';
  }

  String _cityKey(_CityEntry c) => '${c.city}|${c.zone}';

  Future<void> _openPicker() async {
    final picked = await Navigator.of(context).push<_CityEntry>(
      MaterialPageRoute(
        builder: (_) => _CityPickerScreen(
          allCities: _allCities,
          existing: _cities.map(_cityKey).toSet(),
          fmtOffset: _fmtOffset,
          cityTime: _cityTime,
        ),
      ),
    );
    if (picked != null &&
        !_cities.any((c) => _cityKey(c) == _cityKey(picked))) {
      setState(() => _cities.add(picked));
      _save();
    }
  }

  void _removeAt(int index) {
    final removed = _cities[index];
    setState(() => _cities.removeAt(index));
    _save();
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          // v2.53: clear confirmation so the undo bar isn't
          // mistaken for the city coming back.
          '${removed.city} ${l10n.deleted}',
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            setState(() => _cities.insert(index, removed));
            _save();
          },
        ),
      ),
    );
  }

  void _confirmRemove(int index) {
    final city = _cities[index];
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          city.city,
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              MaterialLocalizations.of(ctx).cancelButtonLabel,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _removeAt(index);
            },
            child: Text(
              l10n.delete,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight ? Colors.white : AppTheme.charcoal,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.worldClock,
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.addCity,
            onPressed: _openPicker,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _cities.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.noCities,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        fontSize: 16,
                        color: isLight ? Colors.black54 : Colors.white70,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cities.length,
                  itemBuilder: (ctx, i) {
                    final city = _cities[i];
                    return Dismissible(
                      key: ValueKey(_cityKey(city)),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _removeAt(i),
                      child: GestureDetector(
                        onLongPress: () => _confirmRemove(i),
                        child: _cityCard(city, isLight),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _cityCard(_CityEntry city, bool isLight) {
    final t = _cityTime(city.zone);
    final timeColor = isLight ? AppTheme.lightRingsText : AppTheme.emerald;
    final subColor = isLight ? Colors.black54 : Colors.white70;
    // v2.55: Urdu names when app is in Urdu.
    final isUrdu =
        Localizations.localeOf(context).languageCode == 'ur';
    final cityName =
        isUrdu && city.cityUr.isNotEmpty ? city.cityUr : city.city;
    final countryName =
        isUrdu && city.countryUr.isNotEmpty ? city.countryUr : city.country;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isLight ? AppTheme.lightCardBg : AppTheme.charcoalCard,
        borderRadius: BorderRadius.circular(14),
        border: isLight
            ? Border.all(color: AppTheme.lightCardBorder)
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cityName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  countryName,
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                    color: subColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_fmtDate(t)}  ·  ${_fmtOffset(t.timeZoneOffset)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _fmtTime(t),
            style: TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 30,
              color: timeColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen searchable city picker. Returns the selected city
/// via Navigator.pop, or null when dismissed.
class _CityPickerScreen extends StatefulWidget {
  final List<_CityEntry> allCities;
  final Set<String> existing;
  final String Function(Duration) fmtOffset;
  final tz.TZDateTime Function(String) cityTime;

  const _CityPickerScreen({
    required this.allCities,
    required this.existing,
    required this.fmtOffset,
    required this.cityTime,
  });

  @override
  State<_CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<_CityPickerScreen> {
  String _query = '';
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_CityEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.allCities;
    return widget.allCities.where((e) {
      return e.city.toLowerCase().contains(q) ||
          e.country.toLowerCase().contains(q) ||
          e.cityUr.contains(_query.trim()) ||
          e.countryUr.contains(_query.trim());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final results = _filtered;
    return Scaffold(
      backgroundColor: isLight ? Colors.white : AppTheme.charcoal,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // v2.56: proper padding for the search field (was cramped).
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            height: 56,
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              // v2.58: Urdu font for proper Nastaleeq rendering.
              // v2.63: taller field for Nastaleeq's tall glyphs.
              style: const TextStyle(
                fontWeight: FontWeight.w400,
                fontFamily: 'JameelNoori',
                height: 2.0,
                fontSize: 18,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchCityHint,
                hintStyle: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontFamily: 'JameelNoori',
                  height: 2.0,
                  fontSize: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 16),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        itemCount: results.length,
        itemBuilder: (ctx, i) {
          final e = results[i];
          final added = widget.existing.contains('${e.city}|${e.zone}');
          String offset;
          try {
            offset = widget.fmtOffset(widget.cityTime(e.zone).timeZoneOffset);
          } catch (_) {
            offset = '';
          }
          final subColor = isLight ? Colors.black54 : Colors.white70;
          final isUrdu =
              Localizations.localeOf(context).languageCode == 'ur';
          // v2.55: custom layout with proper spacing (ListTile was cramped),
          // Urdu names when app is in Urdu.
          // v2.63: apply Urdu font to prevent clipping.
          final cityName = isUrdu && e.cityUr.isNotEmpty ? e.cityUr : e.city;
          final countryName =
              isUrdu && e.countryUr.isNotEmpty ? e.countryUr : e.country;
          final urduStyle = isUrdu
              ? const TextStyle(
                  fontFamily: 'JameelNoori',
                  height: 1.6,
                )
              : null;
          return InkWell(
            onTap: added ? null : () => Navigator.of(context).pop(e),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cityName,
                          style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 16,
                              fontFamily: urduStyle?.fontFamily,
                              height: urduStyle?.height),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          countryName,
                          style: TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 13,
                            color: subColor,
                            fontFamily: urduStyle?.fontFamily,
                            height: urduStyle?.height,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (offset.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLight
                            ? AppTheme.lightCardBg
                            : AppTheme.charcoalSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        offset,
                        style: const TextStyle(
                          fontWeight: FontWeight.w400,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    added ? Icons.check_circle : Icons.add_circle_outline,
                    color: added ? AppTheme.emerald : subColor,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
