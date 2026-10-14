// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Urdu (`ur`).
class AppLocalizationsUr extends AppLocalizations {
  AppLocalizationsUr([String locale = 'ur']) : super(locale);

  @override
  String get about => 'ایپ کے بارے میں';

  @override
  String get aboutText =>
      'AlarmHQ v1 — ذاتی استعمال کی الارم ایپ۔ نہ اشتہارات، نہ اکاؤنٹ، نہ ٹریکنگ۔';

  @override
  String get addAlarm => 'الارم شامل کریں';

  @override
  String alarmIn(Object duration) {
    return '$duration میں الارم';
  }

  @override
  String get alarmOff => 'الارم بند ہے';

  @override
  String get alarmRinging => 'الارم بج رہا ہے';

  @override
  String get alarms => 'الارمز';

  @override
  String get appTitle => 'AlarmHQ';

  @override
  String get batteryDesc =>
      'فون کو بیٹری بچانے کے لیے الارم میں تاخیر یا بند کرنے سے روکتا ہے۔';

  @override
  String get batteryTitle => 'بیٹری آپٹیمائزیشن نظرانداز کریں';

  @override
  String get cancel => 'منسوخ کریں';

  @override
  String get confirmDelete => 'حذف کریں';

  @override
  String get date => 'تاریخ';

  @override
  String dateAt(Object date, Object time) {
    return '$date $time';
  }

  @override
  String get defaultSnooze => 'اسنوز کی پہلے سے طے شدہ مدت';

  @override
  String get delete => 'حذف کریں';

  @override
  String deleteAlarmBody(Object label) {
    return '“$label” مستقل طور پر ہٹا دیا جائے گا۔';
  }

  @override
  String get deleteAlarmTitle => 'الارم حذف کریں؟';

  @override
  String get disabled => 'بند';

  @override
  String get discard => 'چھوڑ دیں';

  @override
  String get discardBody => 'آپ کی ترامیم ضائع ہو جائیں گی۔';

  @override
  String get discardTitle => 'تبدیلیاں چھوڑ دیں؟';

  @override
  String get dismiss => 'بند کریں';

  @override
  String get done => 'ٹھیک ہے';

  @override
  String get editAlarm => 'الارم میں ترمیم';

  @override
  String everyNDaysSummary(Object n) {
    return 'ہر $n دن بعد';
  }

  @override
  String get exactAlarmDesc => 'تاکہ Doze موڈ میں بھی الارم ٹھیک وقت پر بجے۔';

  @override
  String get exactAlarmTitle => 'ٹھیک وقت کے الارم';

  @override
  String get fadeIn => 'آواز آہستہ آہستہ بڑھے';

  @override
  String get granted => 'اجازت ہے';

  @override
  String get hoursShort => 'H';

  @override
  String get intervalDays => 'ہر کتنے دن بعد دہراؤ';

  @override
  String get intervalPreview => 'اگلی بار بجنے کے اوقات';

  @override
  String get intervalTooSmall => 'کم از کم 1 دن لکھیں۔';

  @override
  String get justNow => 'ابھی';

  @override
  String get keepEditing => 'ترمیم جاری رکھیں';

  @override
  String get label => 'نام';

  @override
  String get labelHint => 'مثلاً فجر، دفتر، دوا';

  @override
  String get language => 'زبان';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSystem => 'سسٹم کے مطابق';

  @override
  String get languageUrdu => 'اردو';

  @override
  String get maxSnoozes => 'زیادہ سے زیادہ اسنوز';

  @override
  String get minutesShort => 'M';

  @override
  String minutesUnit(Object n) {
    return '$n منٹ';
  }

  @override
  String get newAlarm => 'نیا الارم';

  @override
  String nextRing(Object when) {
    return 'اگلا: $when';
  }

  @override
  String get noAlarms => 'ابھی کوئی الارم نہیں';

  @override
  String get noAlarmsHint => 'پہلا الارم بنانے کے لیے + دبائیں۔';

  @override
  String get noFadeIn => 'بند';

  @override
  String get noMoreSnoozes => 'مزید اسنوز باقی نہیں';

  @override
  String get noSnooze => 'بند';

  @override
  String get notGranted => 'اجازت نہیں';

  @override
  String get onceSummary => 'ایک بار';

  @override
  String get openPermissionScreen => 'اجازت سکرین کھولیں';

  @override
  String get openSettings => 'سیٹنگز کھولیں';

  @override
  String get permBatteryDesc =>
      'فون کو بیٹری بچانے کے لیے الارم میں تاخیر یا بند کرنے سے روکتا ہے۔';

  @override
  String get permBatteryTitle => 'بیٹری آپٹیمائزیشن نظرانداز کریں';

  @override
  String get permBody =>
      'AlarmHQ کو یہ اجازتیں چاہییں تاکہ آپ کے الارم ہمیشہ وقت پر بجیں — چاہے فون لاک ہو یا بیٹری بچا رہا ہو۔';

  @override
  String get permContinue => 'آگے بڑھیں';

  @override
  String get permExactDesc =>
      'الارم ٹھیک اسی منٹ پر بجتا ہے، چاہے فون Doze موڈ میں ہو۔';

  @override
  String get permExactTitle => 'عین وقت پر الارم';

  @override
  String get permGrant => 'اجازت دیں';

  @override
  String get permGranted => 'اجازت مل گئی';

  @override
  String get permNotifDesc => 'الارم اسکرین پر اور نوٹیفکیشن میں دکھاتا ہے۔';

  @override
  String get permNotifTitle => 'نوٹیفکیشنز';

  @override
  String get permOverlayDesc => 'لاک اسکرین پر فل اسکرین الارم دکھاتا ہے۔';

  @override
  String get permOverlayTitle => 'دوسری ایپس پر دکھائیں';

  @override
  String get permAutostartTitle => 'آٹو اسٹارٹ کی اجازت';

  @override
  String get permAutostartDesc =>
      'ایپ بند ہو تو بھی الارم بجے (Xiaomi، Oppo، Vivo، Huawei پر ضروری)۔';

  @override
  String get permSkip => 'ابھی چھوڑیں';

  @override
  String get permTitle => 'اجازتیں درکار ہیں';

  @override
  String get permissions => 'اجازتیں';

  @override
  String get pickAtLeastOneDate => 'کم از کم ایک تاریخ چنیں';

  @override
  String get pickAtLeastOneDay => 'کم از کم ایک دن چنیں';

  @override
  String get pickDate => 'تاریخ چنیں';

  @override
  String get repeat => 'دہراؤ';

  @override
  String get repeatDates => 'تاریخیں';

  @override
  String get repeatInterval => 'ہر N دن بعد';

  @override
  String get repeatNDays => 'N دن';

  @override
  String get repeatOnce => 'ایک بار';

  @override
  String get repeatSpecificDates => 'مخصوص تاریخیں';

  @override
  String get repeatWeekly => 'ہفتہ وار دن';

  @override
  String get repeatWeeklyShort => 'ہفتہ وار';

  @override
  String ringsIn(Object duration) {
    return '$duration میں بجے گا';
  }

  @override
  String get save => 'محفوظ کریں';

  @override
  String secondsUnit(Object n) {
    return '$n سیکنڈ';
  }

  @override
  String get selectDates => 'تاریخوں پر ٹیپ کریں (ہر ایک پر ایک بار بجے گا)';

  @override
  String get selectedDates => 'منتخب تاریخیں';

  @override
  String get settings => 'سیٹنگز';

  @override
  String get skipNextOnly => 'صرف اگلی چھوڑیں';

  @override
  String get snooze => 'اسنوز';

  @override
  String get snoozeLength => 'اسنوز کی مدت';

  @override
  String get sound => 'آواز';

  @override
  String get startDate => 'آغاز کی تاریخ';

  @override
  String get theme => 'تھیم';

  @override
  String get themeDark => 'گہرا';

  @override
  String get themeLight => 'روشن';

  @override
  String get themeSystem => 'سسٹم کے مطابق';

  @override
  String get time => 'وقت';

  @override
  String timesUnit(Object n) {
    return '$n بار';
  }

  @override
  String todayAt(Object time) {
    return 'آج $time';
  }

  @override
  String tomorrowAt(Object time) {
    return 'کل $time';
  }

  @override
  String get toneClassic => 'کلاسک (اندرونی)';

  @override
  String get toneCustom => 'اپنی فائل';

  @override
  String get tonePickFile => 'آڈیو فائل چنیں…';

  @override
  String get tonePreview => 'سن کر دیکھیں';

  @override
  String get toneStop => 'روکیں';

  @override
  String get toneSystemDefault => 'سسٹم کی پہلے سے طے شدہ';

  @override
  String turnOffAlarmBody(Object label, Object when) {
    return '$label — اگلی رنگ $when';
  }

  @override
  String get turnOffAlarmTitle => 'الارم بند کریں؟';

  @override
  String get turnOffCompletely => 'مکمل بند کریں';

  @override
  String get unlimited => 'لامحدود';

  @override
  String get vibration => 'وائبریشن';

  @override
  String get weekdayFri => 'جمعہ';

  @override
  String get weekdayMon => 'پیر';

  @override
  String get weekdaySat => 'ہفتہ';

  @override
  String get weekdaySun => 'اتوار';

  @override
  String get weekdayThu => 'جمعرات';

  @override
  String get weekdayTue => 'منگل';

  @override
  String get weekdayWed => 'بدھ';

  @override
  String weeklySummary(Object days) {
    return '$days';
  }
}
