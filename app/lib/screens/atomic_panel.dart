import 'dart:async';

import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../services/atomic_overlay_service.dart';
import '../services/atomic_time_service.dart';
import '../theme/app_theme.dart';

/// v2.51: Atomic (NTP) time panel.
///
/// Shows the live atomic-corrected time + date, the phone-vs-atomic
/// difference, sync status, and a "Fix phone time" flow that opens the
/// system Date & Time settings with a floating atomic clock on top.
class AtomicPanel extends StatefulWidget {
  const AtomicPanel({super.key});

  @override
  State<AtomicPanel> createState() => _AtomicPanelState();
}

class _AtomicPanelState extends State<AtomicPanel> {
  static const List<String> _monthsEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const List<String> _monthsUr = [
    'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
    'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
  ];

  bool _fixing = false;
  late final Stream<DateTime> _tickStream;

  @override
  void initState() {
    super.initState();
    // One tick stream for the widget's lifetime (tick() is infinite —
    // creating it per-build would leak a loop on every rebuild).
    _tickStream = AtomicTimeService.instance.tick();
    // Auto-sync on first display (cached for 5 min inside the service).
    AtomicTimeService.instance.sync();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  /// v2.55: 12-hour format with AM/PM (her order).
  String _fmt12(DateTime t) {
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h12:${_two(t.minute)}:${_two(t.second)} $ampm';
  }

  /// "Fix phone time": overlay permission -> show floating atomic clock ->
  /// open system Date & Time settings so the user can match it by hand.
  /// v2.56: shows error feedback instead of failing silently.
  Future<void> _onFixPhoneTime() async {
    if (_fixing) return;
    setState(() => _fixing = true);
    try {
      // v2.69: ClockSync-style flow.
      // 1. If rooted: set time directly (su + chmod + setCurrentTimeMillis).
      // 2. Else: show NATIVE overlay (WindowManager via Service — works
      //    on non-rooted devices) + open Date & Time settings.
      final svc = AtomicTimeService.instance;
      final atomicNow = svc.now();
      final rooted = await AtomicOverlayService.isRooted();
      if (rooted) {
        final ok = await AtomicOverlayService.setSystemTimeRoot(
            atomicNow.millisecondsSinceEpoch);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'فون کا ٹائم اٹامک ٹائم سے سیٹ ہو گیا',
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
            ),
          );
          return;
        }
        // Root set failed — fall through to overlay + settings.
      }
      // v2.72: Overlay permission MUST be granted, else the service
      // silently shows nothing (the v2.71 'no time on Settings' cause).
      // If missing, open overlay settings and stop — user grants, then
      // taps the button again.
      final canOverlay = await AtomicOverlayService.canDrawOverlays();
      if (!canOverlay) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'پہلے اوورلے کی اجازت دیں، پھر دوبارہ بٹن دبائیں',
                style: TextStyle(fontWeight: FontWeight.w400),
              ),
            ),
          );
        }
        await AtomicOverlayService.openOverlaySettings();
        return;
      }
      // Native overlay (ClockSync SyncAssistService method).
      await AtomicOverlayService.showNativeOverlay(
          svc.offset.inMilliseconds);
      await AtomicOverlayService.openDateTimeSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fixing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isUrdu = Localizations.localeOf(context).languageCode == 'ur';
    final svc = AtomicTimeService.instance;

    final cardBg = isLight ? AppTheme.lightCardBg : AppTheme.charcoalCard;
    final borderColor =
        isLight ? AppTheme.lightCardBorder : Colors.white10;
    final titleColor = isLight ? AppTheme.lightTimeText : Colors.white;
    final descColor = isLight ? Colors.black54 : Colors.white70;

    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('⏱️', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(
                    l10n.atomicTime,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: titleColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Live atomic time (ticks every second).
              StreamBuilder<DateTime>(
                stream: _tickStream,
                builder: (context, snap) {
                  final t = snap.data ?? svc.now();
                  final months = isUrdu ? _monthsUr : _monthsEn;
                  return Column(
                    children: [
                      Text(
                        _fmt12(t),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w400,
                          color: AppTheme.emerald,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${t.day} ${months[t.month - 1]} ${t.year}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: descColor,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              // Sync status row.
              _buildStatusRow(l10n, svc, descColor),
              // Phone-vs-atomic difference — prominent badge (v2.52).
              if (svc.hasSync && !svc.syncing) ...[
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: (svc.offset.inMilliseconds >= 0
                              ? AppTheme.emerald
                              : const Color(0xFFFFB400))
                          .withValues(alpha: 0.12),
                      border: Border.all(
                        color: svc.offset.inMilliseconds >= 0
                            ? AppTheme.emerald
                            : const Color(0xFFFFB400),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l10n.atomicDiff(svc.offsetText()),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: svc.offset.inMilliseconds >= 0
                            ? AppTheme.emerald
                            : const Color(0xFFFFB400),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              // Fix phone time.
              Text(
                l10n.fixPhoneTimeDesc,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: descColor,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _fixing ? null : _onFixPhoneTime,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.emerald,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _fixing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          l10n.fixPhoneTime,
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(
      AppLocalizations l10n, AtomicTimeService svc, Color descColor) {
    if (svc.syncing) {
      // Sync in progress — spinner only (no extra string needed).
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      );
    }
    if (svc.hasSync) {
      final ls = svc.lastSync!;
      final timeStr =
          '${_two(ls.hour)}:${_two(ls.minute)}:${_two(ls.second)}';
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.atomicLastSync(timeStr),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: descColor,
              ),
            ),
          ),
          TextButton(
            onPressed: () => svc.sync(maxAge: Duration.zero),
            child: Text(
              l10n.atomicSync,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      );
    }
    // Never synced (offline or error): show offline note + sync button.
    // v2.56: show the actual error so we can diagnose.
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                l10n.atomicOffline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: descColor,
                ),
              ),
            ),
            TextButton(
              onPressed: () => svc.sync(maxAge: Duration.zero),
              child: Text(
                l10n.atomicSync,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        if (svc.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              svc.error!,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: Colors.redAccent,
              ),
            ),
          ),
      ],
    );
  }
}
