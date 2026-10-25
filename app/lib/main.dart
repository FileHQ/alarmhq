import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/services.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import 'screens/alarm_list_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/clock_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/alarm_repository.dart';
import 'services/app_settings.dart';
import 'services/hijri_service.dart';
import 'services/native_bridge.dart';
import 'theme/app_theme.dart';
import 'widgets/ringing_overlay.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlarmHQApp());
}

class AlarmHQApp extends StatefulWidget {
  const AlarmHQApp({super.key});

  @override
  State<AlarmHQApp> createState() => _AlarmHQAppState();
}

class _AlarmHQAppState extends State<AlarmHQApp>
    with WidgetsBindingObserver {
  final AppSettings _settings = AppSettings();
  final AlarmRepository _repo = AlarmRepository();
  bool _ready = false;
  bool _onboarded = false;
  int _tab = 0;
  bool _ringingDialogOpen = false;
  bool _exitDialogOpen = false;

  @override
  static const _alarmChannel =
      MethodChannel('com.technoon.alarmhq/alarm');

  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // v2.70: Native back handling — report tab changes to MainActivity
    // and handle its goToTab0 request.
    _alarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'goToTab0') {
        if (mounted) setState(() => _tab = 0);
      }
    });
    _boot();
  }

  void _reportTab(int tab) {
    _alarmChannel.invokeMethod('setCurrentTab', {'tab': tab});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If an alarm fired while the app was in the background and the user
    // returns to it, show the in-app ringing dialog with Dismiss/Snooze.
    if (state == AppLifecycleState.resumed) _checkRinging();
  }

  // v2.66: Back button — BOTH PopScope (below) AND didPopRoute (fallback).
  // PopScope alone didn't work on her Realme device.
  @override
  Future<bool> didPopRoute() async {
    if (!_onboarded || !_ready) return false;
    if (_tab != 0) {
      setState(() => _tab = 0);
      return true;
    }
    return false; // Let PopScope handle the dialog on main tab.
  }

  Future<void> _checkRinging() async {
    if (!_ready || _ringingDialogOpen) return;
    final ctx = _scaffoldKey.currentContext;
    if (ctx == null) return;
    _ringingDialogOpen = true;
    try {
      await RingingOverlay.showIfRinging(ctx);
    } finally {
      _ringingDialogOpen = false;
    }
  }

  final GlobalKey _scaffoldKey = GlobalKey();

  Future<void> _boot() async {
    await _settings.load();
    await _repo.load();
    // v2.33: offline Hijri calendar data for the Calendar tab and
    // the Dates picker. Sync silently in background (never blocks UI).
    await HijriService.instance.load();
    HijriService.instance.syncFromNetwork();
    _onboarded = await PermissionScreen.isOnboarded();
    // v2.17: users who onboarded before v2.11 never saw the full-screen
    // permission card (Android 14+). Show the permission screen once more
    // so they can't miss it — this is the lock-screen fix.
    if (_onboarded) {
      try {
        final needsFs = await NativeBridge.needsFullScreenIntentCard();
        final fsShown = await PermissionScreen.isFsPromptShown();
        if (needsFs && !fsShown) _onboarded = false;
      } catch (_) {
        // Best effort only.
      }
      // v2.18: ColorOS users who onboarded before the "Show on Lock
      // screen" card existed never saw it — show the permission screen
      // once more so they can't miss it.
      if (_onboarded) {
        try {
          final isColorOs = await NativeBridge.isColorOsDevice();
          final lockShown =
              await PermissionScreen.isLockScreenPromptShown();
          if (isColorOs && !lockShown) _onboarded = false;
        } catch (_) {
          // Best effort only.
        }
      }
    }
    _settings.addListener(_onSettingsChanged);
    // If exact-alarm permission was granted while we were away, make sure
    // every enabled alarm is actually scheduled natively.
    if (await NativeBridge.hasExactAlarmPermission()) {
      await _repo.rescheduleAll();
    }
    if (mounted) setState(() => _ready = true);
    // In case the app was opened while an alarm is ringing (e.g. from the
    // notification), check right after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRinging());
  }

  void _onSettingsChanged() => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AlarmHQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _settings.theme,
      locale: _settings.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !_onboarded
              ? PermissionScreen(
                  onDone: () => setState(() => _onboarded = true))
              : Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                // v2.64: PopScope intercepts back button at Scaffold level.
                // didPopRoute was unreliable — PopScope with canPop:false
                // catches the system back button before Navigator does.
                // v2.68: WillPopScope (deprecated API, but different
                // mechanism than PopScope — trying as last resort).
                return WillPopScope(
                  onWillPop: () async {
                    if (_tab != 0) {
                      setState(() => _tab = 0);
                      return false;
                    }
                    // On main tab: confirm dialog.
                    if (_exitDialogOpen) return false;
                    _exitDialogOpen = true;
                    try {
                      final ctx = _scaffoldKey.currentContext;
                      if (ctx == null) return false;
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: Text(
                            l10n.exitTitle,
                            style: const TextStyle(
                                fontWeight: FontWeight.w400, fontSize: 17),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(false),
                              child: Text(
                                l10n.exitNo,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w400),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(true),
                              child: Text(
                                l10n.exitYes,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w400),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        // v2.73: SystemNavigator.pop() is a no-op in a
                        // plain Activity — finish natively instead.
                        _alarmChannel.invokeMethod('exitApp');
                      }
                    } finally {
                      _exitDialogOpen = false;
                    }
                    return false;
                  },
                  child: Scaffold(
                    key: _scaffoldKey,
                    body: _tab == 0
                        ? AlarmListScreen(repo: _repo, settings: _settings)
                        : _tab == 1
                            ? const ClockScreen()
                            : _tab == 2
                                ? const CalendarScreen()
                                : SettingsScreen(
                                    repo: _repo, settings: _settings),
                    bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) {
                      setState(() => _tab = i);
                      _reportTab(i);
                    },
                    destinations: [
                      NavigationDestination(
                        icon: const Text('⏰',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.alarms,
                      ),
                      NavigationDestination(
                        icon: const Text('🕐',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.clockTab,
                      ),
                      NavigationDestination(
                        icon: const Text('📅',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.calendar,
                      ),
                      NavigationDestination(
                        icon: const Text('⚙️',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.settings,
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
