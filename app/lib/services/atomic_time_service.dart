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
      // 2. HTTPS fallback: worldtimeapi.org (works through firewalls).
      final ok = await _syncViaHttps();
      return ok;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// HTTPS time sync via worldtimeapi.org. Returns true on success.
  Future<bool> _syncViaHttps() async {
    try {
      final before = DateTime.now();
      final resp = await http
          .get(Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'))
          .timeout(const Duration(seconds: 10));
      final after = DateTime.now();
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final utcStr = data['utc_datetime'] as String?;
      if (utcStr == null) return false;
      final serverTime = DateTime.parse(utcStr);
      // RTT/2 correction: assume symmetric latency.
      final rtt = after.difference(before);
      final corrected = serverTime.add(rtt ~/ 2);
      // offset = serverTime - deviceTime.
      _offset = corrected.difference(after);
      _lastSync = DateTime.now();
      _error = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    }
  }

  /// Current atomic-corrected time (device time + offset).
  /// Falls back to device time if never synced.
  DateTime now() => DateTime.now().add(_offset);

  /// Human-readable offset, e.g. "+2.3s" / "-0.8s" / "±0.0s".
  String offsetText() {
    final ms = _offset.inMilliseconds;
    if (ms.abs() < 500) return '±0.0s';
    final s = (ms.abs() / 1000).toStringAsFixed(1);
    return ms > 0 ? '+${s}s' : '-${s}s';
  }

  /// Stream ticking every second with the atomic-corrected time.
  Stream<DateTime> tick() async* {
    while (true) {
      yield now();
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
