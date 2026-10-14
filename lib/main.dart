import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import 'screens/alarm_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/alarm_repository.dart';
import 'services/app_settings.dart';
import 'services/native_bridge.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlarmHQApp());
}

class AlarmHQApp extends StatefulWidget {
  const AlarmHQApp({super.key});

  @override
  State<AlarmHQApp> createState() => _AlarmHQAppState();
}

class _AlarmHQAppState extends State<AlarmHQApp> {
  final AppSettings _settings = AppSettings();
  final AlarmRepository _repo = AlarmRepository();
  bool _ready = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _settings.load();
    await _repo.load();
    _settings.addListener(_onSettingsChanged);
    // If exact-alarm permission was granted while we were away, make sure
    // every enabled alarm is actually scheduled natively.
    if (await NativeBridge.hasExactAlarmPermission()) {
      await _repo.rescheduleAll();
    }
    if (mounted) setState(() => _ready = true);
  }

  void _onSettingsChanged() => setState(() {});

  @override
  void dispose() {
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
          : Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                return Scaffold(
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
