/// Alarm data model. Serialized to JSON; the same schema is mirrored by
/// the native Android scheduler (AlarmScheduler.kt) so both sides agree.
class AlarmModel {
  final int id;
  final String label;
  final int hour; // 0-23
  final int minute; // 0-59
  final AlarmRepeatMode mode;
  final List<int> weekDays; // 1=Mon .. 7=Sun (DateTime.monday == 1)
  final DateTime? onceDate; // date part only, for AlarmRepeatMode.once
  final int intervalDays; // N for AlarmRepeatMode.interval (>= 1)
  final DateTime? intervalStart; // date part only, counting origin
  final int ringDays; // X for AlarmRepeatMode.cycle: ring every day for X days
  final int skipDays; // Y for AlarmRepeatMode.cycle: then skip Y days
  final DateTime? cycleStart; // date part only, cycle counting origin
  final List<DateTime> specificDates; // date parts only, for specificDates mode
  final DateTime? skipNextDate; // exact trigger to skip ("skip next only")
  final int snoozeMinutes;
  final int maxSnoozes; // 0 = no snooze, -1 = unlimited
  final String toneUri; // asset://..., system://default, content://...
  final String toneName;
  final bool vibration;
  final int fadeInSeconds; // 0 = no fade
  final bool enabled;

  const AlarmModel({
    required this.id,
    this.label = '',
    required this.hour,
    required this.minute,
    this.mode = AlarmRepeatMode.weekly,
    this.weekDays = const [1, 2, 3, 4, 5, 6, 7],
    this.onceDate,
    this.intervalDays = 1,
    this.intervalStart,
    this.ringDays = 5,
    this.skipDays = 1,
    this.cycleStart,
    this.specificDates = const [],
    this.skipNextDate,
    this.snoozeMinutes = 10,
    this.maxSnoozes = 3,
    this.toneUri = 'asset://assets/tones/alarmhq-classic.wav',
    this.toneName = 'Classic',
    this.vibration = true,
    this.fadeInSeconds = 30,
    this.enabled = true,
  });

  AlarmModel copyWith({
    int? id,
    String? label,
    int? hour,
    int? minute,
    AlarmRepeatMode? mode,
    List<int>? weekDays,
    DateTime? Function()? onceDate,
    int? intervalDays,
    DateTime? Function()? intervalStart,
    int? ringDays,
    int? skipDays,
    DateTime? Function()? cycleStart,
    List<DateTime>? specificDates,
    DateTime? Function()? skipNextDate,
    int? snoozeMinutes,
    int? maxSnoozes,
    String? toneUri,
    String? toneName,
    bool? vibration,
    int? fadeInSeconds,
    bool? enabled,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      mode: mode ?? this.mode,
      weekDays: weekDays ?? this.weekDays,
      onceDate: onceDate != null ? onceDate() : this.onceDate,
      intervalDays: intervalDays ?? this.intervalDays,
      intervalStart: intervalStart != null ? intervalStart() : this.intervalStart,
      ringDays: ringDays ?? this.ringDays,
      skipDays: skipDays ?? this.skipDays,
      cycleStart: cycleStart != null ? cycleStart() : this.cycleStart,
      specificDates: specificDates ?? this.specificDates,
      skipNextDate: skipNextDate != null ? skipNextDate() : this.skipNextDate,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      maxSnoozes: maxSnoozes ?? this.maxSnoozes,
      toneUri: toneUri ?? this.toneUri,
      toneName: toneName ?? this.toneName,
      vibration: vibration ?? this.vibration,
      fadeInSeconds: fadeInSeconds ?? this.fadeInSeconds,
      enabled: enabled ?? this.enabled,
    );
  }

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _dateParse(String s) {
    final p = s.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static String _dateTimeStr(DateTime d) =>
      '${_dateStr(d)}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static DateTime _dateTimeParse(String s) {
    final parts = s.split('T');
    final d = _dateParse(parts[0]);
    final t = parts[1].split(':').map(int.parse).toList();
    return DateTime(d.year, d.month, d.day, t[0], t[1]);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hour': hour,
        'minute': minute,
        'mode': mode.name,
        'weekDays': weekDays,
        'onceDate': onceDate == null ? null : _dateStr(onceDate!),
        'intervalDays': intervalDays,
        'intervalStart': intervalStart == null ? null : _dateStr(intervalStart!),
        'ringDays': ringDays,
        'skipDays': skipDays,
        'cycleStart': cycleStart == null ? null : _dateStr(cycleStart!),
        'specificDates':
            specificDates.map(_dateStr).toList(),
        'skipNextDate':
            skipNextDate == null ? null : _dateTimeStr(skipNextDate!),
        'snoozeMinutes': snoozeMinutes,
        'maxSnoozes': maxSnoozes,
        'toneUri': toneUri,
        'toneName': toneName,
        'vibration': vibration,
        'fadeInSeconds': fadeInSeconds,
        'enabled': enabled,
      };

  factory AlarmModel.fromJson(Map<String, dynamic> j) => AlarmModel(
        id: (j['id'] as num).toInt(),
        label: (j['label'] as String?) ?? '',
        hour: (j['hour'] as num).toInt(),
        minute: (j['minute'] as num).toInt(),
        mode: AlarmRepeatMode.values.firstWhere(
          (e) => e.name == j['mode'],
          orElse: () => AlarmRepeatMode.weekly,
        ),
        weekDays: ((j['weekDays'] as List?) ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        onceDate:
            j['onceDate'] == null ? null : _dateParse(j['onceDate'] as String),
        intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 1,
        intervalStart: j['intervalStart'] == null
            ? null
            : _dateParse(j['intervalStart'] as String),
        ringDays: (j['ringDays'] as num?)?.toInt() ?? 5,
        skipDays: (j['skipDays'] as num?)?.toInt() ?? 1,
        cycleStart: j['cycleStart'] == null
            ? null
            : _dateParse(j['cycleStart'] as String),
        specificDates: ((j['specificDates'] as List?) ?? const [])
            .map((e) => _dateParse(e as String))
            .toList(),
        skipNextDate: j['skipNextDate'] == null
            ? null
            : _dateTimeParse(j['skipNextDate'] as String),
        snoozeMinutes: (j['snoozeMinutes'] as num?)?.toInt() ?? 10,
        maxSnoozes: (j['maxSnoozes'] as num?)?.toInt() ?? 3,
        toneUri: (j['toneUri'] as String?) ?? 'asset://assets/tones/alarmhq-classic.wav',
        toneName: (j['toneName'] as String?) ?? 'Classic',
        vibration: (j['vibration'] as bool?) ?? true,
        fadeInSeconds: (j['fadeInSeconds'] as num?)?.toInt() ?? 30,
        enabled: (j['enabled'] as bool?) ?? true,
      );
}

enum AlarmRepeatMode { weekly, once, interval, specificDates, cycle }
