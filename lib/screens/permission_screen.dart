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

  /// v2.17: the full-screen-intent card was added in v2.11. Users who
  /// onboarded before that never saw it, so re-show the permission
  /// screen once for them on Android 14+.
  static const String _fsFlagKey = 'permissions_fs_prompt_shown';

  static Future<bool> isOnboarded() async =>
      await PrefsService.getString(_flagKey) == '1';

  static Future<void> markOnboarded() =>
      PrefsService.putString(_flagKey, '1');

  static Future<bool> isFsPromptShown() async =>
      await PrefsService.getString(_fsFlagKey) == '1';

  static Future<void> markFsPromptShown() =>
      PrefsService.putString(_fsFlagKey, '1');

  /// v2.18: the "Show on Lock screen" card was added for ColorOS
  /// (Realme/Oppo/OnePlus). Users who onboarded before that never saw it,
  /// so re-show the permission screen once for them.
  static const String _lockFlagKey = 'permissions_lockscreen_prompt_shown';

  static Future<bool> isLockScreenPromptShown() async =>
      await PrefsService.getString(_lockFlagKey) == '1';

  static Future<void> markLockScreenPromptShown() =>
      PrefsService.putString(_lockFlagKey, '1');

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

  /// v2.18: Realme/ColorOS hides "Show on Lock screen" (+ "Open new
  /// windows in background") inside the app's system settings page.
  /// Cannot be checked via API — marked done once the user opens it.
  /// Only shown on ColorOS devices; never blocks Continue.
  bool _showLockCard = false;
  bool? _lockDone;
  bool _lockOpened = false;

  /// v2.18: Android 12+ "Manage app if unused" silently revokes
  /// permissions. Shown on API 31+. Marked done once the user opens
  /// the settings page. Never blocks Continue.
  bool _showUnusedCard = false;
  bool? _unusedDone;

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
      // v2.18: after the user visits the app-details page from the
      // "Show on Lock screen" card, remind them which toggles to turn on.
      if (_lockOpened) {
        _lockOpened = false;
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.permLockScreenReminder),
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
      NativeBridge.isColorOsDevice(),
      NativeBridge.getSdkInt(),
    ]);
    final showFs = results[4] as bool;
    final fsGranted =
        showFs ? await NativeBridge.canUseFullScreenIntent() : true;
    final isColorOs = results[5] as bool;
    final sdkInt = results[6] as int;
    if (!mounted) return;
    setState(() {
      _exact = results[0] as bool;
      _battery = results[1] as bool;
      _notif = results[2] as bool;
      _overlay = results[3] as bool;
      _showFsCard = showFs;
      _fsIntent = fsGranted;
      // v2.10: autostart was never set here → infinite spinner.
      // Default to false so the Grant button shows.
      _autostartDone ??= false;
      // v2.18: ColorOS "Show on Lock screen" card + unused-app warning.
      // "Manage app if unused" exists on Android 12+ (API 31+).
      _showLockCard = isColorOs;
      _lockDone ??= false;
      _showUnusedCard = sdkInt >= 31;
      _unusedDone ??= false;
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
    // v2.17: if the full-screen card was part of this onboarding round,
    // don't ask again on later launches.
    if (_showFsCard) await PermissionScreen.markFsPromptShown();
    // v2.18: same for the ColorOS "Show on Lock screen" card.
    if (_showLockCard) await PermissionScreen.markLockScreenPromptShown();
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
            // v2.17: highlighted — impossible to miss.
            if (_showFsCard)
              _permCard(
                icon: '🔔',
                title: l10n.permFsTitle,
                desc: l10n.permFsDesc,
                granted: _fsIntent,
                onGrant: NativeBridge.openFullScreenIntentSettings,
                l10n: l10n,
                highlight: _fsIntent != true,
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
            // v2.18 (critical): on Realme/Oppo/OnePlus (ColorOS) the
            // "Show on Lock screen" toggle lives inside the app's system
            // settings page. Without it, the alarm NEVER appears on the
            // lock screen. Cannot be checked via API — the card just
            // opens the right page. Never blocks Continue.
            if (_showLockCard)
              _permCard(
                icon: '🔒',
                title: l10n.permLockScreenTitle,
                desc: l10n.permLockScreenDesc,
                granted: _lockDone,
                onGrant: () async {
                  // Fire-and-forget with timeout — never hang the UI.
                  _lockOpened = true;
                  try {
                    await NativeBridge.openAppDetailsSettings()
                        .timeout(const Duration(seconds: 2));
                  } catch (_) {
                    // Best effort: the settings page was still launched.
                  }
                  if (mounted) setState(() => _lockDone = true);
                },
                l10n: l10n,
                highlight: _lockDone != true,
              ),
            // v2.18: Android 12+ "Manage app if unused" silently removes
            // AlarmHQ's permissions. Warn + open the settings page.
            // Never blocks Continue.
            if (_showUnusedCard)
              _permCard(
                icon: '🗑️',
                title: l10n.permUnusedTitle,
                desc: l10n.permUnusedDesc,
                granted: _unusedDone,
                onGrant: () async {
                  try {
                    await NativeBridge.openAppDetailsSettings()
                        .timeout(const Duration(seconds: 2));
                  } catch (_) {
                    // Best effort: the settings page was still launched.
                  }
                  if (mounted) setState(() => _unusedDone = true);
                },
                l10n: l10n,
                highlight: _unusedDone != true,
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
    // v2.17: when true and not granted, the card gets a red alert border
    // and a "Required" badge so it can't be missed.
    bool highlight = false,
  }) {
    final isGranted = granted == true;
    final alert = highlight && !isGranted;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: alert
            ? const Color(0xFF3A2222)
            : AppTheme.charcoalCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alert
              ? Colors.redAccent
              : isGranted
                  ? AppTheme.emerald.withValues(alpha: 0.6)
                  : Colors.white12,
          width: alert ? 2 : 1,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    // v2.17: "Required" badge for critical permissions.
                    if (alert) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l10n.permRequired,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
