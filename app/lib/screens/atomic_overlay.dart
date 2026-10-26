import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ntp_dart/ntp_dart.dart';
import 'package:system_alert_window/system_alert_window.dart';

import '../theme/app_theme.dart';

/// v2.51: floating atomic-clock overlay.
///
/// Shown on top of the system Date & Time settings so the user can match
/// the phone's clock to atomic (NTP) time by hand.
///
/// IMPORTANT: this runs in a SEPARATE FlutterEngine/isolate — it cannot
/// access [AtomicTimeService.instance] or any other main-isolate state.
/// It performs its own one-shot NTP sync at startup and then ticks locally
/// from `DateTime.now() + offset`. Falls back to device time offline.
///
/// NOTE: the system_alert_window native plugin hardcodes the Dart entry
/// point name "overlayMain" (SystemAlertWindowPlugin.java), so [overlayMain]
/// must exist with exactly that name — it delegates to [atomicOverlayMain].
@pragma('vm:entry-point')
void overlayMain() => atomicOverlayMain();

@pragma('vm:entry-point')
void atomicOverlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AtomicOverlayApp());
}

class _AtomicOverlayApp extends StatelessWidget {
  const _AtomicOverlayApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _AtomicOverlayCard(),
    );
  }
}

class _AtomicOverlayCard extends StatefulWidget {
  const _AtomicOverlayCard();

  @override
  State<_AtomicOverlayCard> createState() => _AtomicOverlayCardState();
}

class _AtomicOverlayCardState extends State<_AtomicOverlayCard> {
  // v2.86: monotonic anchor (same fix as AtomicTimeService) — the
  // old DateTime.now() + offset followed phone-time changes.
  DateTime? _anchorAtomic;
  final Stopwatch _watch = Stopwatch();
  Timer? _timer;
  DateTime _now = DateTime.now();

  static const List<String> _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _monthsUr = [
    'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
    'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _syncClock();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = _anchorAtomic == null
            ? DateTime.now()
            : _anchorAtomic!.add(_watch.elapsed));
      }
    });
  }

  /// One-shot NTP sync in this isolate. Falls back to device time offline.
  Future<void> _syncClock() async {
    try {
      final resp = await NtpClient()
          .query(samples: 1)
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _anchorAtomic = DateTime.now().add(resp.offset);
        _watch
          ..reset()
          ..start();
        _now = _anchorAtomic!;
      });
    } catch (_) {
      // Offline: anchor stays null -> device time.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final t = _now;
    final isUrdu =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
            'ur';
    final months = isUrdu ? _monthsUr : _monthsEn;
    final timeText =
        '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
    final dateText = '${t.day} ${months[t.month - 1]} ${t.year}';

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.charcoal,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.emerald, width: 1.5),
        ),
        child: Row(
          children: [
            const Text('⏱️', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeText,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.emerald,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    dateText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => SystemAlertWindow.closeSystemWindow(
                prefMode: SystemWindowPrefMode.OVERLAY,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
