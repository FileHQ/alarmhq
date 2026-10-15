import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import 'screens/alarm_list_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/alarm_repository.dart';
import 'services/app_settings.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If an alarm fired while the app was in the background and the user
    // returns to it, show the in-app ringing dialog with Dismiss/Snooze.
    if (state == AppLifecycleState.resumed) _checkRinging();
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
                return Scaffold(
                  key: _scaffoldKey,
                  body: _tab == 0
                      ? AlarmListScreen(repo: _repo, settings: _settings)
                      : SettingsScreen(repo: _repo, settings: _settings),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    destinations: [
                      NavigationDestination(
                        icon: const Text('⏰',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.alarms,
                      ),
                      NavigationDestination(
                        icon: const Text('⚙️',
                            style: TextStyle(fontSize: 24)),
                        label: l10n.settings,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
