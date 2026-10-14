import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../services/alarm_repository.dart';
import '../services/app_settings.dart';
import '../services/native_bridge.dart';

/// Settings: language, theme, default snooze, permission helpers, about.
class SettingsScreen extends StatefulWidget {
  final AlarmRepository repo;
  final AppSettings settings;

  const SettingsScreen({super.key, required this.repo, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _exactAlarm;
  bool? _battery;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final exact = await NativeBridge.hasExactAlarmPermission();
    final battery = await NativeBridge.isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _exactAlarm = exact;
      _battery = battery;
    });
    if (exact) {
      // Permission may have been granted in system settings; make sure
      // native schedules exist for all enabled alarms.
      await widget.repo.rescheduleAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = widget.settings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(l10n.language),
          RadioGroup<String>(
            groupValue: s.language,
            onChanged: (v) => s.setLanguage(v!),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: Text(l10n.languageSystem),
                  value: 'system',
                ),
                RadioListTile<String>(
                  title: Text(l10n.languageEnglish),
                  value: 'en',
                ),
                RadioListTile<String>(
                  title: Text(l10n.languageUrdu),
                  value: 'ur',
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          _section(l10n.theme),
          RadioGroup<String>(
            groupValue: s.themeMode,
            onChanged: (v) => s.setThemeMode(v!),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: Text(l10n.themeSystem),
                  value: 'system',
                ),
                RadioListTile<String>(
                  title: Text(l10n.themeDark),
                  value: 'dark',
                ),
                RadioListTile<String>(
                  title: Text(l10n.themeLight),
                  value: 'light',
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          _section(l10n.snooze),
          ListTile(
            title: Text(l10n.defaultSnooze),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: s.defaultSnoozeMinutes > 1
                      ? () => s.setDefaultSnooze(s.defaultSnoozeMinutes - 1)
                      : null,
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    l10n.minutesUnit(s.defaultSnoozeMinutes),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: s.defaultSnoozeMinutes < 60
                      ? () => s.setDefaultSnooze(s.defaultSnoozeMinutes + 1)
                      : null,
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          _section(l10n.permissions),
          _permissionTile(
            title: l10n.exactAlarmTitle,
            subtitle: l10n.exactAlarmDesc,
            granted: _exactAlarm,
            onTap: () async {
              await NativeBridge.openExactAlarmSettings();
            },
          ),
          _permissionTile(
            title: l10n.batteryTitle,
            subtitle: l10n.batteryDesc,
            granted: _battery,
            onTap: () async {
              await NativeBridge.openBatteryOptimizationSettings();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton(
              onPressed: _refreshPermissions,
              child: Text(l10n.openSettings),
            ),
          ),
          const Divider(height: 32),
          _section(l10n.about),
          ListTile(
            title: Text(l10n.aboutText),
            subtitle: const Text('v1.0.0'),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _permissionTile({
    required String title,
    required String subtitle,
    required bool? granted,
    required VoidCallback onTap,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: granted == null
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator())
          : Chip(
              label: Text(
                  granted ? l10n.granted : l10n.notGranted,
                  style: const TextStyle(fontSize: 12)),
              backgroundColor: granted
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.orange.withValues(alpha: 0.2),
            ),
      onTap: onTap,
    );
  }
}
