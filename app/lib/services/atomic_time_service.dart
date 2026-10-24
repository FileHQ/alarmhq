import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:ntp_dart/ntp_dart.dart';

/// v2.51: Atomic (NTP) time service.
/// NTP servers (time.google.com etc.) are synced to atomic clocks, so the
/// NTP time IS atomic time for our purposes.
///
/// Usage:
///   await AtomicTimeService.instance.sync();   // one NTP query
///   AtomicTimeService.instance.offset;         // device-vs-atomic Duration
///   AtomicTimeService.instance.now();          // atomic-corrected DateTime
class AtomicTimeService extends ChangeNotifier {
  AtomicTimeService._();
  static final AtomicTimeService instance = AtomicTimeService._();

  Duration _offset = Duration.zero;
  DateTime? _lastSync;
  bool _syncing = false;
  String? _error;

  /// Difference: atomicTime - deviceTime. Positive = device is behind.
  Duration get offset => _offset;
  DateTime? get lastSync => _lastSync;
  bool get syncing => _syncing;
  String? get error => _error;
  bool get hasSync => _lastSync != null;

  /// Query NTP servers and compute the offset. Cached for [maxAge].
  /// v2.53: NTP (UDP) first; falls back to HTTPS time API when UDP is
  /// blocked (common on mobile networks).
  Future<bool> sync({Duration maxAge = const Duration(minutes: 5)}) async {
    if (_syncing) return hasSync;
    if (_lastSync != null &&
        DateTime.now().difference(_lastSync!) < maxAge) {
      return true;
    }
    _syncing = true;
    _error = null;
    notifyListeners();
    try {
      // 1. Try NTP (UDP) — 3 samples for accuracy.
      try {
        final resp = await NtpClient().query(samples: 3).timeout(
          const Duration(seconds: 8),
        );
        _offset = resp.offset;
        _lastSync = DateTime.now();
        _error = null;
        return true;
      } catch (_) {
        // NTP failed (UDP blocked?) — try HTTPS fallback below.
      }
      // 2. HTTPS fallbacks (work through firewalls).
      // Try multiple endpoints — some may be blocked.
      final endpoints = [
        'https://timeapi.io/api/time/current/zone?timeZone=UTC',
        'https://worldclockapi.com/api/json/utc/now',
        'http://worldtimeapi.org/api/timezone/Etc/UTC',
      ];
      for (final url in endpoints) {
        if (await _syncViaHttps(url)) return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// HTTPS time sync. Tries the given URL, parses the time.
  /// Supports timeapi.io (dateTime), worldclockapi (currentDateTime),
  /// worldtimeapi (datetime). Returns true on success.
  Future<bool> _syncViaHttps(String url) async {
    try {
      final before = DateTime.now();
      final resp = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final after = DateTime.now();
      if (resp.statusCode != 200) {
        _error = 'Server error: ${resp.statusCode}';
        return false;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // Try each known field.
      String? dtStr = data['dateTime'] as String? ??
          data['currentDateTime'] as String? ??
          data['datetime'] as String?;
      if (dtStr == null) {
        _error = 'Invalid server response';
        return false;
      }
      final serverTime = DateTime.parse(dtStr);
      // RTT/2 correction: assume symmetric latency.
      final rtt = after.difference(before);
      final corrected = serverTime.add(rtt ~/ 2);
      // offset = serverTime - deviceTime.
      _offset = corrected.difference(after);
      _lastSync = DateTime.now();
      _error = null;
      return true;
    } catch (e) {
      // v2.58: user-friendly error in Urdu/English.
      final msg = e.toString();
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup')) {
        _error = 'انٹرنیٹ نہیں مل رہا — کنکشن چیک کریں';
      } else if (msg.contains('TimeoutException')) {
        _error = 'سرور جواب نہیں دے رہا — دوبارہ کوشش کریں';
      } else {
        _error = msg;
      }
      return false;
    }
  }

  /// Current atomic-corrected time (device time + offset).
  /// Falls back to device time if never synced.
  DateTime now() => DateTime.now().add(_offset);

  /// Human-readable offset, e.g. "+2d 3h 15m 30s" / "-5m 20s" / "±0s".
  /// v2.64: includes days (date difference), hours, minutes — not just seconds.
  /// Always LTR-formatted so Urdu RTL doesn't reverse the order.
  String offsetText() {
    final ms = _offset.inMilliseconds;
    // v2.66: LTR isolate on ALL cases (zero case was missing it — showed as "0±s").
    if (ms.abs() < 500) return '\u2066±0s\u2069';
    final sign = ms > 0 ? '+' : '-';
    final absMs = ms.abs();
    final days = absMs ~/ (24 * 3600 * 1000);
    final hours = (absMs % (24 * 3600 * 1000)) ~/ (3600 * 1000);
    final mins = (absMs % (3600 * 1000)) ~/ (60 * 1000);
    final secs = ((absMs % (60 * 1000)) / 1000).toStringAsFixed(0);
    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (mins > 0) parts.add('${mins}m');
    // Always show seconds if nothing else, or if there are leftover seconds.
    if (parts.isEmpty || int.parse(secs) > 0) parts.add('${secs}s');
    // LTR isolate so RTL locales don't reverse the order.
    return '\u2066$sign${parts.join(' ')}\u2069';
  }

  /// Stream ticking every second with the atomic-corrected time.
  Stream<DateTime> tick() async* {
    while (true) {
      yield now();
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
