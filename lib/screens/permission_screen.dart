import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../services/native_bridge.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';

/// First-launch permission onboarding.
///
/// Shown once (flagged in [PrefsService]) so the user grants the four
/// permissions an alarm app needs to ring reliably:
/// exact alarms, battery-optimization exemption, notifications,
/// and display-over-other-apps (full-screen alarm).
class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  static const String _flagKey = 'permissions_onboarded';

  static Future<bool> isOnboarded() async =>
      await PrefsService.getString(_flagKey) == '1';

  static Future<void> markOnboarded() =>
      PrefsService.putString(_flagKey, '1');

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool? _exact;
  bool? _battery;
  bool? _notif;
  bool? _overlay;

  /// Android 14+: USE_FULL_SCREEN_INTENT must be granted or the alarm
  /// won't pop up on the lock screen (v2.11, critical). Only shown on
  /// API 34+; auto-granted below that.
  bool? _fsIntent;
  bool _showFsCard = false;

  /// Autostart can't be checked via API; marked done once the user opens
  /// the manufacturer's page. Never blocks Continue.
  /// v2.10: initialized to false (was null → infinite spinner bug).
  bool? _autostartDone;

  /// Set when the user taps the autostart card; used to show the
  /// background-activity reminder snackbar when they return.
  bool _autostartOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when the user returns from system settings.
    if (state == AppLifecycleState.resumed) {
      _refresh();
      // v2.10: after the user visits the autostart page on Realme/ColorOS,
      // remind them to also allow background activity.
      if (_autostartOpened) {
        _autostartOpened = false;
        _maybeShowBgActivityReminder();
      }
    }
  }

  /// On Realme/Oppo/OnePlus (ColorOS), autostart alone is not enough —
  /// "Allow background activity" must also be enabled. Remind once.
  Future<void> _maybeShowBgActivityReminder() async {
    try {
      final m = (await NativeBridge.getManufacturer()).toLowerCase();
      final isColorOs =
          m.contains('realme') || m.contains('oppo') || m.contains('oneplus');
      if (isColorOs && mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.permBgActivityReminder),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      // Best effort only.
    }
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      NativeBridge.hasExactAlarmPermission(),
      NativeBridge.isIgnoringBatteryOptimizations(),
      NativeBridge.hasNotificationPermission(),
      NativeBridge.canDrawOverlays(),
      NativeBridge.needsFullScreenIntentCard(),
    ]);
    final showFs = results[4];
    final fsGranted =
        showFs ? await NativeBridge.canUseFullScreenIntent() : true;
    if (!mounted) return;
    setState(() {
      _exact = results[0];
      _battery = results[1];
      _notif = results[2];
      _overlay = results[3];
      _showFsCard = showFs;
      _fsIntent = fsGranted;
      // v2.10: autostart was never set here → infinite spinner.
      // Default to false so the Grant button shows.
      _autostartDone ??= false;
    });
  }

  bool get _allGranted =>
      _exact == true &&
      _battery == true &&
      _notif == true &&
      _overlay == true &&
      (!_showFsCard || _fsIntent == true);

  Future<void> _finish() async {
    await PermissionScreen.markOnboarded();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppTheme.charcoal,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Text('⏰', style: TextStyle(fontSize: 56),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Text(
              l10n.permTitle,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppTheme.emerald,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.permBody,
              style: const TextStyle(fontSize: 15, color: Colors.white70,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            _permCard(
              icon: '⏱️',
              title: l10n.permExactTitle,
              desc: l10n.permExactDesc,
              granted: _exact,
              onGrant: NativeBridge.openExactAlarmSettings,
              l10n: l10n,
            ),
            _permCard(
              icon: '🔋',
              title: l10n.permBatteryTitle,
              desc: l10n.permBatteryDesc,
              granted: _battery,
              onGrant: NativeBridge.openBatteryOptimizationSettings,
              l10n: l10n,
            ),
            _permCard(
              icon: '🔔',
              title: l10n.permNotifTitle,
              desc: l10n.permNotifDesc,
              granted: _notif,
              // One-tap system dialog (no settings page); the result comes
              // back through the MethodChannel, so update state directly.
              onGrant: () async {
                final granted =
                    await NativeBridge.requestNotificationPermission();
                if (mounted) setState(() => _notif = granted);
              },
              l10n: l10n,
            ),
            _permCard(
              icon: '📱',
              title: l10n.permOverlayTitle,
              desc: l10n.permOverlayDesc,
              granted: _overlay,
              onGrant: NativeBridge.openOverlaySettings,
              l10n: l10n,
            ),
            // v2.11 (critical): Android 14+ requires the user to grant
            // USE_FULL_SCREEN_INTENT or the alarm never pops up on the
            // lock screen. Only shown where needed.
            if (_showFsCard)
              _permCard(
                icon: '🔔',
                title: l10n.permFsTitle,
                desc: l10n.permFsDesc,
                granted: _fsIntent,
                onGrant: NativeBridge.openFullScreenIntentSettings,
                l10n: l10n,
              ),
            // v2.4: autostart — Xiaomi/Oppo/Vivo/Huawei kill background
            // alarms without it. Cannot be checked programmatically, so
            // this card never blocks Continue; it just opens the right page.
            _permCard(
              icon: '🚀',
              title: l10n.permAutostartTitle,
              desc: l10n.permAutostartDesc,
              granted: _autostartDone,
              onGrant: () async {
                // v2.10: fire-and-forget with timeout — never hang the UI.
                _autostartOpened = true;
                try {
                  await NativeBridge.openAutostartSettings()
                      .timeout(const Duration(seconds: 2));
                } catch (_) {
                  // Best effort: the settings page was still launched.
                }
                if (mounted) setState(() => _autostartDone = true);
              },
              l10n: l10n,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _allGranted ? _finish : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.emerald,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  l10n.permContinue,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _finish,
                child: Text(l10n.permSkip,
                    style: const TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permCard({
    required String icon,
    required String title,
    required String desc,
    required bool? granted,
    required Future<void> Function() onGrant,
    required AppLocalizations l10n,
  }) {
    final isGranted = granted == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.charcoalCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted
              ? AppTheme.emerald.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(desc,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.white60, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted == null)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (isGranted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.emerald, size: 22),
                const SizedBox(width: 4),
                Text(l10n.permGranted,
                    style: const TextStyle(
                        color: AppTheme.emerald,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ],
            )
          else
            ElevatedButton(
              onPressed: () async {
                await onGrant();
                // Status re-checks on resume via the lifecycle observer.
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(l10n.permGrant,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
