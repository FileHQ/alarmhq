import 'package:flutter/material.dart';

import 'prefs_service.dart';

/// Persisted app settings: language, theme mode, default snooze.
class AppSettings extends ChangeNotifier {
  static const _langKey = 'alarmhq_lang'; // system | en | ur
  static const _themeKey = 'alarmhq_theme'; // system | dark | light
  static const _snoozeKey = 'alarmhq_default_snooze';

  String language = 'system';
  String themeMode = 'system';
  int defaultSnoozeMinutes = 10;

  Future<void> load() async {
    language = await PrefsService.getString(_langKey) ?? 'system';
    themeMode = await PrefsService.getString(_themeKey) ?? 'system';
    defaultSnoozeMinutes =
        int.tryParse(await PrefsService.getString(_snoozeKey) ?? '') ?? 10;
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    language = v;
    await PrefsService.putString(_langKey, v);
    notifyListeners();
  }

  Future<void> setThemeMode(String v) async {
    themeMode = v;
    await PrefsService.putString(_themeKey, v);
    notifyListeners();
  }

  Future<void> setDefaultSnooze(int v) async {
    defaultSnoozeMinutes = v;
    await PrefsService.putString(_snoozeKey, '$v');
    notifyListeners();
  }

  Locale? get locale {
    switch (language) {
      case 'en':
        return const Locale('en');
      case 'ur':
        return const Locale('ur');
      default:
        return null; // system
    }
  }

  ThemeMode get theme {
    switch (themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}
