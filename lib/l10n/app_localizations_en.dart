// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get about => 'About';

  @override
  String get aboutText =>
      'AlarmHQ v1 — a personal alarm app. No ads, no accounts, no tracking.';

  @override
  String get addAlarm => 'Add alarm';

  @override
  String get alarmOff => 'Alarm is off';

  @override
  String get alarms => 'Alarms';

  @override
  String get appTitle => 'AlarmHQ';

  @override
  String get batteryDesc =>
      'Prevents the phone from delaying or killing alarms to save battery.';

  @override
  String get batteryTitle => 'Ignore battery optimizations';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirmDelete => 'Delete';

  @override
  String get date => 'Date';

  @override
  String dateAt(Object date, Object time) {
    return '$date $time';
  }

  @override
  String get defaultSnooze => 'Default snooze length';

  @override
  String get delete => 'Delete';

  @override
  String deleteAlarmBody(Object label) {
    return '“$label” will be removed permanently.';
  }

  @override
  String get deleteAlarmTitle => 'Delete alarm?';

  @override
  String get disabled => 'Off';

  @override
  String get discard => 'Discard';

  @override
  String get discardBody => 'Your edits will be lost.';

  @override
  String get discardTitle => 'Discard changes?';

  @override
  String get editAlarm => 'Edit alarm';

  @override
  String everyNDaysSummary(Object n) {
    return 'Every $n days';
  }

  @override
  String get exactAlarmDesc =>
      'Needed so alarms ring at the exact minute, even in Doze mode.';

  @override
  String get exactAlarmTitle => 'Exact alarms';

  @override
  String get fadeIn => 'Gradual volume';

  @override
  String get granted => 'Granted';

  @override
  String get intervalDays => 'Repeat every (days)';

  @override
  String get intervalPreview => 'Next rings';

  @override
  String get intervalTooSmall => 'Enter at least 1 day.';

  @override
  String get justNow => 'now';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get label => 'Label';

  @override
  String get labelHint => 'e.g. Fajr, Work, Medicine';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageUrdu => 'اردو';

  @override
  String get maxSnoozes => 'Max snoozes';

  @override
  String minutesUnit(Object n) {
    return '$n min';
  }

  @override
  String get newAlarm => 'New alarm';

  @override
  String nextRing(Object when) {
    return 'Next: $when';
  }

  @override
  String get noAlarms => 'No alarms yet';

  @override
  String get noAlarmsHint => 'Tap + to create your first alarm.';

  @override
  String get noFadeIn => 'Off';

  @override
  String get noSnooze => 'Off';

  @override
  String get notGranted => 'Not granted';

  @override
  String get onceSummary => 'Once';

  @override
  String get openSettings => 'Open settings';

  @override
  String get permissions => 'Permissions';

  @override
  String get pickDate => 'Pick date';

  @override
  String get repeat => 'Repeat';

  @override
  String get repeatInterval => 'Every N days';

  @override
  String get repeatOnce => 'One time';

  @override
  String get repeatWeekly => 'Weekly days';

  @override
  String get save => 'Save';

  @override
  String secondsUnit(Object n) {
    return '$n sec';
  }

  @override
  String get settings => 'Settings';

  @override
  String get snooze => 'Snooze';

  @override
  String get snoozeLength => 'Snooze length';

  @override
  String get sound => 'Sound';

  @override
  String get startDate => 'Start date';

  @override
  String get theme => 'Theme';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System default';

  @override
  String get time => 'Time';

  @override
  String timesUnit(Object n) {
    return '${n}x';
  }

  @override
  String todayAt(Object time) {
    return 'Today $time';
  }

  @override
  String tomorrowAt(Object time) {
    return 'Tomorrow $time';
  }

  @override
  String get toneClassic => 'Classic (built-in)';

  @override
  String get toneCustom => 'Custom file';

  @override
  String get tonePickFile => 'Pick audio file…';

  @override
  String get tonePreview => 'Preview';

  @override
  String get toneStop => 'Stop';

  @override
  String get toneSystemDefault => 'System default';

  @override
  String get vibration => 'Vibration';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String weeklySummary(Object days) {
    return '$days';
  }

  @override
  String get repeatSpecificDates => 'Specific dates';

  @override
  String get repeatDates => 'Dates';

  @override
  String get repeatNDays => 'N days';

  @override
  String get skipNextOnly => 'Skip next only';

  @override
  String get turnOffCompletely => 'Turn off completely';

  @override
  String get turnOffAlarmTitle => 'Turn off alarm?';

  @override
  String turnOffAlarmBody(Object label, Object when) {
    return '$label — next ring $when';
  }

  @override
  String ringsIn(Object duration) {
    return 'Rings in $duration';
  }

  @override
  String alarmIn(Object duration) {
    return 'Alarm in $duration';
  }

  @override
  String get selectDates => 'Tap dates to select (each rings once)';

  @override
  String get selectedDates => 'Selected dates';

  @override
  String get hoursShort => 'H';

  @override
  String get minutesShort => 'M';

  @override
  String get done => 'Done';

  @override
  String get repeatWeeklyShort => 'Weekly';

  @override
  String get pickAtLeastOneDay => 'Pick at least one day';

  @override
  String get pickAtLeastOneDate => 'Pick at least one date';
}
