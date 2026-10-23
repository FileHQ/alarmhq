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

  const _CityEntry({
    required this.city,
    required this.country,
    required this.zone,
  });

  factory _CityEntry.fromJson(Map<String, dynamic> j) => _CityEntry(
        city: (j['city'] as String?) ?? '',
        country: (j['country'] as String?) ?? '',
        zone: (j['zone'] as String?) ?? '',
      );
}

class _WorldClockScreenState extends State<WorldClockScreen> {
  static bool _tzInit = false;
  static const String _prefsKey = 'worldclock_cities';
  static const List<String> _defaultZones = [
    'Asia/Karachi',
    'Asia/Dubai',
    'Asia/Riyadh',
    'Europe/London',
    'America/New_York',
  ];
  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  List<String> _zones = [];
  Map<String, _CityEntry> _meta = {};
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
    final meta = <String, _CityEntry>{};
    for (final e in all) {
      meta.putIfAbsent(e.zone, () => e);
    }

    List<String> zones;
    try {
      final saved = await PrefsService.getString(_prefsKey);
      if (saved == null) {
        zones = List<String>.from(_defaultZones);
      } else {
        final decoded = jsonDecode(saved) as List;
        zones = decoded.whereType<String>().toList();
        if (zones.isEmpty) zones = List<String>.from(_defaultZones);
      }
    } catch (_) {
      zones = List<String>.from(_defaultZones);
    }
    // Drop zones the timezone DB doesn't know (defensive).
    zones = zones.where((z) {
      try {
        tz.getLocation(z);
        return true;
      } catch (_) {
        return false;
      }
    }).toList();

    if (!mounted) return;
    setState(() {
      _allCities = all;
      _meta = meta;
      _zones = zones;
      _loaded = true;
    });
    _save();
  }

  Future<void> _save() async {
    try {
      await PrefsService.putString(_prefsKey, jsonEncode(_zones));
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
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}';
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

  String _cityName(String zone) => _meta[zone]?.city ?? zone.split('/').last.replaceAll('_', ' ');
  String _countryName(String zone) => _meta[zone]?.country ?? '';

  Future<void> _openPicker() async {
    final zone = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _CityPickerScreen(
          allCities: _allCities,
          existing: _zones.toSet(),
          fmtOffset: _fmtOffset,
          cityTime: _cityTime,
        ),
      ),
    );
    if (zone != null && !_zones.contains(zone)) {
      setState(() => _zones.add(zone));
      _save();
    }
  }

  void _removeAt(int index) {
    final removed = _zones[index];
    setState(() => _zones.removeAt(index));
    _save();
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _cityName(removed),
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        action: SnackBarAction(
          label: l10n.addCity,
          onPressed: () {
            setState(() => _zones.insert(index, removed));
            _save();
          },
        ),
      ),
    );
  }

  void _confirmRemove(int index) {
    final zone = _zones[index];
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _cityName(zone),
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
          : _zones.isEmpty
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
                  itemCount: _zones.length,
                  itemBuilder: (ctx, i) {
                    final zone = _zones[i];
                    return Dismissible(
                      key: ValueKey(zone),
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
                        child: _cityCard(zone, isLight),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _cityCard(String zone, bool isLight) {
    final t = _cityTime(zone);
    final timeColor = isLight ? AppTheme.lightRingsText : AppTheme.emerald;
    final subColor = isLight ? Colors.black54 : Colors.white70;
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
                  _cityName(zone),
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _countryName(zone),
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

/// Full-screen searchable city picker. Returns the selected zone ID
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
          e.country.toLowerCase().contains(q);
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
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontWeight: FontWeight.w400),
          decoration: InputDecoration(
            hintText: l10n.searchCityHint,
            hintStyle: const TextStyle(fontWeight: FontWeight.w400),
            border: InputBorder.none,
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
      body: ListView.builder(
        itemCount: results.length,
        itemBuilder: (ctx, i) {
          final e = results[i];
          final added = widget.existing.contains(e.zone);
          String offset;
          try {
            offset = widget.fmtOffset(widget.cityTime(e.zone).timeZoneOffset);
          } catch (_) {
            offset = '';
          }
          final subColor = isLight ? Colors.black54 : Colors.white70;
          return ListTile(
            title: Text(
              e.city,
              style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
            ),
            subtitle: Text(
              e.country,
              style: TextStyle(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: subColor,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
            onTap: added ? null : () => Navigator.of(context).pop(e.zone),
          );
        },
      ),
    );
  }
}
