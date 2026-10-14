import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ur.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ur'),
  ];

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutText.
  ///
  /// In en, this message translates to:
  /// **'AlarmHQ v1 — a personal alarm app. No ads, no accounts, no tracking.'**
  String get aboutText;

  /// No description provided for @addAlarm.
  ///
  /// In en, this message translates to:
  /// **'Add alarm'**
  String get addAlarm;

  /// No description provided for @alarmOff.
  ///
  /// In en, this message translates to:
  /// **'Alarm is off'**
  String get alarmOff;

  /// No description provided for @alarms.
  ///
  /// In en, this message translates to:
  /// **'Alarms'**
  String get alarms;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'AlarmHQ'**
  String get appTitle;

  /// No description provided for @batteryDesc.
  ///
  /// In en, this message translates to:
  /// **'Prevents the phone from delaying or killing alarms to save battery.'**
  String get batteryDesc;

  /// No description provided for @batteryTitle.
  ///
  /// In en, this message translates to:
  /// **'Ignore battery optimizations'**
  String get batteryTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get confirmDelete;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @dateAt.
  ///
  /// In en, this message translates to:
  /// **'{date} {time}'**
  String dateAt(Object date, Object time);

  /// No description provided for @defaultSnooze.
  ///
  /// In en, this message translates to:
  /// **'Default snooze length'**
  String get defaultSnooze;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteAlarmBody.
  ///
  /// In en, this message translates to:
  /// **'“{label}” will be removed permanently.'**
  String deleteAlarmBody(Object label);

  /// No description provided for @deleteAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete alarm?'**
  String get deleteAlarmTitle;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get disabled;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @discardBody.
  ///
  /// In en, this message translates to:
  /// **'Your edits will be lost.'**
  String get discardBody;

  /// No description provided for @discardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardTitle;

  /// No description provided for @editAlarm.
  ///
  /// In en, this message translates to:
  /// **'Edit alarm'**
  String get editAlarm;

  /// No description provided for @everyNDaysSummary.
  ///
  /// In en, this message translates to:
  /// **'Every {n} days'**
  String everyNDaysSummary(Object n);

  /// No description provided for @exactAlarmDesc.
  ///
  /// In en, this message translates to:
  /// **'Needed so alarms ring at the exact minute, even in Doze mode.'**
  String get exactAlarmDesc;

  /// No description provided for @exactAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Exact alarms'**
  String get exactAlarmTitle;

  /// No description provided for @fadeIn.
  ///
  /// In en, this message translates to:
  /// **'Gradual volume'**
  String get fadeIn;

  /// No description provided for @granted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get granted;

  /// No description provided for @intervalDays.
  ///
  /// In en, this message translates to:
  /// **'Repeat every (days)'**
  String get intervalDays;

  /// No description provided for @intervalPreview.
  ///
  /// In en, this message translates to:
  /// **'Next rings'**
  String get intervalPreview;

  /// No description provided for @intervalTooSmall.
  ///
  /// In en, this message translates to:
  /// **'Enter at least 1 day.'**
  String get intervalTooSmall;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get justNow;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @label.
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// No description provided for @labelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fajr, Work, Medicine'**
  String get labelHint;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// No description provided for @languageUrdu.
  ///
  /// In en, this message translates to:
  /// **'اردو'**
  String get languageUrdu;

  /// No description provided for @maxSnoozes.
  ///
  /// In en, this message translates to:
  /// **'Max snoozes'**
  String get maxSnoozes;

  /// No description provided for @minutesUnit.
  ///
  /// In en, this message translates to:
  /// **'{n} min'**
  String minutesUnit(Object n);

  /// No description provided for @newAlarm.
  ///
  /// In en, this message translates to:
  /// **'New alarm'**
  String get newAlarm;

  /// No description provided for @nextRing.
  ///
  /// In en, this message translates to:
  /// **'Next: {when}'**
  String nextRing(Object when);

  /// No description provided for @noAlarms.
  ///
  /// In en, this message translates to:
  /// **'No alarms yet'**
  String get noAlarms;

  /// No description provided for @noAlarmsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create your first alarm.'**
  String get noAlarmsHint;

  /// No description provided for @noFadeIn.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get noFadeIn;

  /// No description provided for @noSnooze.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get noSnooze;

  /// No description provided for @notGranted.
  ///
  /// In en, this message translates to:
  /// **'Not granted'**
  String get notGranted;

  /// No description provided for @onceSummary.
  ///
  /// In en, this message translates to:
  /// **'Once'**
  String get onceSummary;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @pickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick date'**
  String get pickDate;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatInterval.
  ///
  /// In en, this message translates to:
  /// **'Every N days'**
  String get repeatInterval;

  /// No description provided for @repeatOnce.
  ///
  /// In en, this message translates to:
  /// **'One time'**
  String get repeatOnce;

  /// No description provided for @repeatWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly days'**
  String get repeatWeekly;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @secondsUnit.
  ///
  /// In en, this message translates to:
  /// **'{n} sec'**
  String secondsUnit(Object n);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @snooze.
  ///
  /// In en, this message translates to:
  /// **'Snooze'**
  String get snooze;

  /// No description provided for @snoozeLength.
  ///
  /// In en, this message translates to:
  /// **'Snooze length'**
  String get snoozeLength;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @startDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @timesUnit.
  ///
  /// In en, this message translates to:
  /// **'{n}x'**
  String timesUnit(Object n);

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today {time}'**
  String todayAt(Object time);

  /// No description provided for @tomorrowAt.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow {time}'**
  String tomorrowAt(Object time);

  /// No description provided for @toneClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic (built-in)'**
  String get toneClassic;

  /// No description provided for @toneCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom file'**
  String get toneCustom;

  /// No description provided for @tonePickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick audio file…'**
  String get tonePickFile;

  /// No description provided for @tonePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get tonePreview;

  /// No description provided for @toneStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get toneStop;

  /// No description provided for @toneSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get toneSystemDefault;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @weekdayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// No description provided for @weekdayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// No description provided for @weekdaySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// No description provided for @weekdaySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// No description provided for @weekdayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// No description provided for @weekdayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// No description provided for @weekdayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// No description provided for @weeklySummary.
  ///
  /// In en, this message translates to:
  /// **'{days}'**
  String weeklySummary(Object days);

  /// No description provided for @repeatSpecificDates.
  ///
  /// In en, this message translates to:
  /// **'Specific dates'**
  String get repeatSpecificDates;

  /// No description provided for @repeatDates.
  ///
  /// In en, this message translates to:
  /// **'Dates'**
  String get repeatDates;

  /// No description provided for @repeatNDays.
  ///
  /// In en, this message translates to:
  /// **'N days'**
  String get repeatNDays;

  /// No description provided for @skipNextOnly.
  ///
  /// In en, this message translates to:
  /// **'Skip next only'**
  String get skipNextOnly;

  /// No description provided for @turnOffCompletely.
  ///
  /// In en, this message translates to:
  /// **'Turn off completely'**
  String get turnOffCompletely;

  /// No description provided for @turnOffAlarmTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off alarm?'**
  String get turnOffAlarmTitle;

  /// No description provided for @turnOffAlarmBody.
  ///
  /// In en, this message translates to:
  /// **'{label} — next ring {when}'**
  String turnOffAlarmBody(Object label, Object when);

  /// No description provided for @ringsIn.
  ///
  /// In en, this message translates to:
  /// **'Rings in {duration}'**
  String ringsIn(Object duration);

  /// No description provided for @alarmIn.
  ///
  /// In en, this message translates to:
  /// **'Alarm in {duration}'**
  String alarmIn(Object duration);

  /// No description provided for @selectDates.
  ///
  /// In en, this message translates to:
  /// **'Tap dates to select (each rings once)'**
  String get selectDates;

  /// No description provided for @selectedDates.
  ///
  /// In en, this message translates to:
  /// **'Selected dates'**
  String get selectedDates;

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'H'**
  String get hoursShort;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'M'**
  String get minutesShort;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @repeatWeeklyShort.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get repeatWeeklyShort;

  /// No description provided for @pickAtLeastOneDay.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one day'**
  String get pickAtLeastOneDay;

  /// No description provided for @pickAtLeastOneDate.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one date'**
  String get pickAtLeastOneDate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ur'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ur':
      return AppLocalizationsUr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
