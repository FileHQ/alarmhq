import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../models/alarm.dart';
import '../services/alarm_repository.dart';
import '../services/app_settings.dart';
import '../services/hijri_service.dart';
import '../services/native_bridge.dart';
import '../services/next_occurrence.dart';
import '../theme/app_theme.dart';
import '../widgets/time_picker_scroll.dart';

/// Create / edit one alarm: 12-hour scroll time picker, 4 repeat modes
/// (weekly / once / N days / specific dates), snooze, sound.
class AlarmEditScreen extends StatefulWidget {
  final AlarmRepository repo;
  final AppSettings settings;
  final AlarmModel? existing;

  const AlarmEditScreen({
    super.key,
    required this.repo,
    required this.settings,
    this.existing,
  });

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late TimeOfDay _time;
  final _labelCtrl = TextEditingController();
  late AlarmRepeatMode _mode;
  late List<int> _weekDays;
  late int _intervalDays;
  late DateTime _intervalStart;
  late int _ringDays;
  late int _skipDays;
  late DateTime _cycleStart;
  late List<DateTime> _specificDates;
  late DateTime _calMonth; // calendar page being viewed
  late int _snoozeMinutes;
  late int _maxSnoozes;
  late String _toneUri;
  late String _toneName;
  late bool _vibration;
  late int _fadeInSeconds;
  bool _previewing = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _time = e == null
        ? TimeOfDay(hour: now.hour, minute: (now.minute + 1) % 60)
        : TimeOfDay(hour: e.hour, minute: e.minute);
    _labelCtrl.text = e?.label ?? '';
    _mode = e?.mode ?? AlarmRepeatMode.weekly;
    _weekDays = List<int>.from(e?.weekDays ?? [1, 2, 3, 4, 5, 6, 7]);
    _intervalDays = e?.intervalDays ?? 5;
    _intervalStart =
        e?.intervalStart ?? DateTime(now.year, now.month, now.day);
    _ringDays = e?.ringDays ?? 5;
    _skipDays = e?.skipDays ?? 1;
    _cycleStart =
        e?.cycleStart ?? DateTime(now.year, now.month, now.day);
    _specificDates = List<DateTime>.from(e?.specificDates ?? []);
    _specificDates.sort(_dateCmp);
    _calMonth = DateTime(now.year, now.month, 1);
    _snoozeMinutes = e?.snoozeMinutes ?? widget.settings.defaultSnoozeMinutes;
    _maxSnoozes = e?.maxSnoozes ?? 3;
    _toneUri = e?.toneUri ?? 'asset://assets/tones/alarmhq-classic.wav';
    _toneName = e?.toneName ?? 'Classic';
    _vibration = e?.vibration ?? true;
    _fadeInSeconds = e?.fadeInSeconds ?? 30;
    _labelCtrl.addListener(() => _dirty = true);
  }

  static int _dateCmp(DateTime a, DateTime b) =>
      DateTime(a.year, a.month, a.day)
          .compareTo(DateTime(b.year, b.month, b.day));

  @override
  void dispose() {
    _labelCtrl.dispose();
    NativeBridge.stopTonePreview();
    super.dispose();
  }

  void _markDirty([void Function()? fn]) => setState(() {
        _dirty = true;
        fn?.call();
      });

  AlarmModel _buildDraft() => AlarmModel(
        id: widget.existing?.id ?? 0,
        label: _labelCtrl.text.trim(),
        hour: _time.hour,
        minute: _time.minute,
        mode: _mode,
        weekDays: List<int>.from(_weekDays)..sort(),
        // v2.47: one-time alarms have no user-visible date — the date is
        // derived from the time: today if the time is still ahead, else
        // tomorrow. Always within the next 24 hours.
        onceDate: _computeOnceDate(),
        intervalDays: _intervalDays,
        intervalStart: DateTime(
            _intervalStart.year, _intervalStart.month, _intervalStart.day),
        ringDays: _ringDays,
        skipDays: _skipDays,
        cycleStart:
            DateTime(_cycleStart.year, _cycleStart.month, _cycleStart.day),
        specificDates: _specificDates
            .map((d) => DateTime(d.year, d.month, d.day))
            .toList(),
        snoozeMinutes: _snoozeMinutes,
        maxSnoozes: _maxSnoozes,
        toneUri: _toneUri,
        toneName: _toneName,
        vibration: _vibration,
        fadeInSeconds: _fadeInSeconds,
        // v2.14: always enable on save — the user explicitly set this alarm.
        enabled: true,
      );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_mode == AlarmRepeatMode.interval && _intervalDays < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.intervalTooSmall)),
      );
      return;
    }
    if (_mode == AlarmRepeatMode.weekly && _weekDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pickAtLeastOneDay)),
      );
      return;
    }
    if (_mode == AlarmRepeatMode.specificDates && _specificDates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pickAtLeastOneDate)),
      );
      return;
    }
    await NativeBridge.stopTonePreview();
    final draft = _buildDraft();
    if (widget.existing == null) {
      await widget.repo.add(draft);
    } else {
      await widget.repo.update(draft);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.discardTitle),
        content: Text(l10n.discardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.keepEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _pickTime() async {
    final t = await ScrollTimePicker.show(context, _time);
    if (t != null) _markDirty(() => _time = t);
  }

  /// which: 1 = interval start, 2 = cycle start.
  /// (v2.47: one-time no longer has a date picker.)
  Future<void> _pickDate({required int which}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: which == 1 ? _intervalStart : _cycleStart,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) {
      _markDirty(() {
        if (which == 1) {
          _intervalStart = d;
        } else {
          _cycleStart = d;
        }
      });
    }
  }

  Future<void> _pickTone() async {
    final uri = await NativeBridge.pickAudioFile();
    if (uri != null && uri.isNotEmpty) {
      _markDirty(() {
        _toneUri = uri;
        _toneName = uri.split('/').last;
      });
    }
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await NativeBridge.stopTonePreview();
      setState(() => _previewing = false);
    } else {
      await NativeBridge.playTonePreview(_toneUri, 0.8);
      setState(() => _previewing = true);
    }
  }

  String _dateText(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// v2.47: one-time alarm date derived from the picked time — today when
  /// the time is still ahead, otherwise tomorrow. Never a past time.
  DateTime _computeOnceDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final t = DateTime(today.year, today.month, today.day, _time.hour, _time.minute);
    return t.isBefore(now) ? today.add(const Duration(days: 1)) : today;
  }

  /// "6:32 PM"
  String _timeText12() {
    final ampm = _time.hour < 12 ? 'AM' : 'PM';
    var h = _time.hour % 12;
    if (h == 0) h = 12;
    return '$h:${_time.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.pop(context, false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title:
              Text(widget.existing == null ? l10n.newAlarm : l10n.editAlarm),
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(l10n.save,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.emerald)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- time (12-hour, tap opens scroll picker) ----
            Center(
              child: InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  child: Text(
                    _timeText12(),
                    style:
                        Theme.of(context).textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.emerald,
                              letterSpacing: -1,
                            ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // ---- label ----
            TextField(
              controller: _labelCtrl,
              decoration: InputDecoration(
                labelText: l10n.label,
                hintText: l10n.labelHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // ---- repeat mode (4 options, one line each) ----
            Text(l10n.repeat,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _modeSegment(l10n),
            const SizedBox(height: 12),
            if (_mode == AlarmRepeatMode.weekly) _weeklyPicker(l10n),
            // v2.47: one-time has no date — just the time, rings within 24h.
            if (_mode == AlarmRepeatMode.once)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.onceInfo24h,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppTheme.emerald),
                ),
              ),
            if (_mode == AlarmRepeatMode.interval) _intervalPicker(l10n),
            if (_mode == AlarmRepeatMode.specificDates)
              _specificDatesPicker(l10n),
            if (_mode == AlarmRepeatMode.cycle) _cyclePicker(l10n),
            const Divider(height: 32),
            // ---- snooze ----
            _sectionTitle(l10n.snooze),
            Text(l10n.snoozeLength,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            _presetChips<int>(
              options: _withCurrent([5, 10, 15, 20, 30], _snoozeMinutes),
              selected: _snoozeMinutes,
              label: (v) => l10n.minutesUnit(v),
              onSelect: (v) => _markDirty(() => _snoozeMinutes = v),
            ),
            const SizedBox(height: 12),
            Text(l10n.maxSnoozes,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            _presetChips<int>(
              // -1 = unlimited.
              options: _withCurrent([0, 1, 2, 3, 5, -1], _maxSnoozes),
              selected: _maxSnoozes,
              label: (v) => v == 0
                  ? l10n.noSnooze
                  : v < 0
                      ? l10n.unlimited
                      : l10n.timesUnit(v),
              onSelect: (v) => _markDirty(() => _maxSnoozes = v),
            ),
            const Divider(height: 32),
            // ---- sound ----
            _sectionTitle(l10n.sound),
            RadioGroup<String>(
              groupValue: _toneUri,
              onChanged: (v) => _markDirty(() {
                _toneUri = v!;
                _toneName = _toneDisplayName(l10n, v);
              }),
              child: Column(
                children: [
                  _toneRow('asset://assets/tones/alarmhq-classic.wav',
                      l10n.toneClassic),
                  _toneRow('system://default', l10n.toneSystemDefault),
                  if (!_isBuiltInTone)
                    _toneRow(_toneUri, '${l10n.toneCustom}: $_toneName'),
                ],
              ),
            ),
            ListTile(
              title: Text(l10n.tonePickFile),
              leading: const Icon(Icons.audio_file),
              onTap: _pickTone,
            ),
            ListTile(
              title:
                  Text(_previewing ? l10n.toneStop : l10n.tonePreview),
              leading:
                  Icon(_previewing ? Icons.stop : Icons.play_arrow),
              onTap: _togglePreview,
            ),
            SwitchListTile(
              title: Text(l10n.vibration),
              value: _vibration,
              onChanged: (v) => _markDirty(() => _vibration = v),
            ),
            ListTile(
              title: Text(l10n.fadeIn),
              // v2.27: explain what gradual volume does — the user asked.
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.fadeInDesc,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54),
                  ),
                  Slider(
                    value: _fadeInSeconds.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 12,
                    label: _fadeInSeconds == 0
                        ? l10n.noFadeIn
                        : l10n.secondsUnit(_fadeInSeconds),
                    onChanged: (v) =>
                        setState(() => _fadeInSeconds = v.round()),
                    onChangeEnd: (_) => _dirty = true,
                  ),
                ],
              ),
              trailing: Text(
                _fadeInSeconds == 0
                    ? l10n.noFadeIn
                    : l10n.secondsUnit(_fadeInSeconds),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 5-option segment with compact labels that fit on one line.
  Widget _modeSegment(AppLocalizations l10n) {
    final options = [
      (AlarmRepeatMode.weekly, l10n.repeatWeeklyShort),
      (AlarmRepeatMode.once, l10n.repeatOnce),
      (AlarmRepeatMode.interval, l10n.repeatNDays),
      (AlarmRepeatMode.specificDates, l10n.repeatDates),
      (AlarmRepeatMode.cycle, l10n.repeatCycle),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.charcoalCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final (mode, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => _markDirty(() => _mode = mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _mode == mode
                        ? AppTheme.emerald
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_mode == mode ? '✓ ' : ''}$label',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _mode == mode
                          ? Colors.black
                          : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _isBuiltInTone =>
      _toneUri == 'asset://assets/tones/alarmhq-classic.wav' ||
      _toneUri == 'system://default';

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  /// Day pills with full localized names (v2.39: user wants full Urdu names).
  /// Uses FittedBox scaleDown so text always fits inside the pill.
  Widget _weeklyPicker(AppLocalizations l10n) {
    final names = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ];
    return Row(
      children: List.generate(7, (i) {
        final wd = i + 1;
        final selected = _weekDays.contains(wd);
        final name = names[i].isNotEmpty ? names[i] : '?';
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: GestureDetector(
              onTap: () => _markDirty(() {
                if (selected) {
                  _weekDays.remove(wd);
                } else {
                  _weekDays.add(wd);
                }
              }),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21),
                  color: selected ? AppTheme.emerald : AppTheme.charcoalCard,
                  border: selected
                      ? null
                      : Border.all(color: Colors.white24, width: 1.5),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    maxLines: 1,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: selected ? Colors.black : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _intervalPicker(AppLocalizations l10n) {
    final preview =
        NextOccurrence.nextTriggers(_buildDraft(), DateTime.now(), 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepperRow(
          label: l10n.intervalDays,
          valueText: '$_intervalDays',
          onMinus: _intervalDays > 1
              ? () => _markDirty(() => _intervalDays--)
              : null,
          onPlus: _intervalDays < 365
              ? () => _markDirty(() => _intervalDays++)
              : null,
        ),
        ListTile(
          title: Text(l10n.startDate),
          subtitle: Text(_dateText(_intervalStart)),
          leading:
              const Icon(Icons.event_repeat, color: AppTheme.emerald),
          onTap: () => _pickDate(which: 1),
          contentPadding: EdgeInsets.zero,
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(l10n.intervalPreview,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          for (final t in preview)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.alarm,
                      size: 16, color: AppTheme.emerald),
                  const SizedBox(width: 8),
                  Text(
                    '${_dateText(t)}  ${_time12(t.hour, t.minute)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _time12(int h24, int m) {
    final ampm = h24 < 12 ? 'AM' : 'PM';
    var h = h24 % 12;
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $ampm';
  }

  /// Ring/skip cycle picker: "ring X days, skip Y days", start date,
  /// plus a preview of the next rings.
  Widget _cyclePicker(AppLocalizations l10n) {
    final preview =
        NextOccurrence.nextTriggers(_buildDraft(), DateTime.now(), 5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stepperRow(
          label: l10n.cycleRingDays,
          valueText: '$_ringDays',
          onMinus: _ringDays > 1
              ? () => _markDirty(() => _ringDays--)
              : null,
          onPlus: _ringDays < 30
              ? () => _markDirty(() => _ringDays++)
              : null,
        ),
        _stepperRow(
          label: l10n.cycleSkipDays,
          valueText: '$_skipDays',
          onMinus: _skipDays > 0
              ? () => _markDirty(() => _skipDays--)
              : null,
          onPlus: _skipDays < 30
              ? () => _markDirty(() => _skipDays++)
              : null,
        ),
        ListTile(
          title: Text(l10n.startDate),
          subtitle: Text(_dateText(_cycleStart)),
          leading:
              const Icon(Icons.event_repeat, color: AppTheme.emerald),
          onTap: () => _pickDate(which: 2),
          contentPadding: EdgeInsets.zero,
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(l10n.intervalPreview,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          for (final t in preview)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.alarm,
                      size: 16, color: AppTheme.emerald),
                  const SizedBox(width: 8),
                  Text(
                    '${_dateText(t)}  ${_time12(t.hour, t.minute)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// Calendar multi-select for specific dates.
  Widget _specificDatesPicker(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.selectDates,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
        ),
        const SizedBox(height: 8),
        _calendarGrid(l10n),
        if (_specificDates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l10n.selectedDates,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final d in _specificDates)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.alarm,
                      size: 16, color: AppTheme.emerald),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_dateText(d)}  ${_timeText12()}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        // v2.33: Hijri date under each selected date.
                        // v2.34: Urdu month name in Urdu locale (digits stay English).
                        Text(
                          l10n.localeName == 'ur'
                              ? HijriService.instance.hijriFor(d).displayUr
                              : HijriService.instance.hijriFor(d).display,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _markDirty(() {
                      _specificDates.removeWhere(
                          (x) => _dateCmp(x, d) == 0);
                    }),
                    child: const Icon(Icons.close,
                        size: 20, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  bool _isSelected(DateTime d) =>
      _specificDates.any((x) => _dateCmp(x, d) == 0);

  Widget _calendarGrid(AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(_calMonth.year, _calMonth.month, 1);
    final monthName = _monthName(l10n, _calMonth.month);
    // Monday-first offset.
    final leading = (monthStart.weekday - 1) % 7;
    final daysInMonth =
        DateTime(_calMonth.year, _calMonth.month + 1, 0).day;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(leading, null),
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_calMonth.year, _calMonth.month, d),
    ];
    final dow = [
      l10n.weekdayMon,
      l10n.weekdayTue,
      l10n.weekdayWed,
      l10n.weekdayThu,
      l10n.weekdayFri,
      l10n.weekdaySat,
      l10n.weekdaySun,
    ].map((s) => s.isNotEmpty ? s.characters.first : '?').toList();

    return GestureDetector(
      // v2.39: swipe left/right to change month (same as main Calendar tab).
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          setState(() {
            _calMonth = DateTime(_calMonth.year, _calMonth.month + 1, 1);
          });
        } else if (v > 200) {
          setState(() {
            _calMonth = DateTime(_calMonth.year, _calMonth.month - 1, 1);
          });
        }
      },
      child: Container(
      decoration: BoxDecoration(
        color: AppTheme.charcoalCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _calMonth =
                      DateTime(_calMonth.year, _calMonth.month - 1, 1);
                }),
              ),
              Text('$monthName ${_calMonth.year}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _calMonth =
                      DateTime(_calMonth.year, _calMonth.month + 1, 1);
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final h in dow)
                Center(
                  child: Text(h,
                      style: const TextStyle(
                          color: Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                ),
              for (final cell in cells)
                if (cell == null)
                  const SizedBox.shrink()
                else
                  _calCell(cell, today),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _calCell(DateTime cell, DateTime today) {
    final selected = _isSelected(cell);
    final isPast = cell.isBefore(today);
    // v2.33: Hijri date under each Gregorian date (English digits only).
    // Amber = arithmetical "calculated" (outside sighted-data coverage).
    final hijri = HijriService.instance.hijriFor(cell);
    final dayColor = selected
        ? Colors.black
        : isPast
            ? Colors.white24
            : Colors.white;
    final hijriColor = selected
        ? Colors.black87
        : isPast
            ? Colors.white12
            : hijri.isCalculated
                ? Colors.amber.shade300
                : Colors.white38;
    return GestureDetector(
      onTap: isPast
          ? null
          : () => _markDirty(() {
                if (selected) {
                  _specificDates
                      .removeWhere((x) => _dateCmp(x, cell) == 0);
                } else {
                  _specificDates.add(cell);
                  _specificDates.sort(_dateCmp);
                }
              }),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? AppTheme.emerald : Colors.transparent,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${cell.day}',
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                fontSize: 14,
                color: dayColor,
              ),
            ),
            Text(
              // "~" marks predicted/estimated (until moon sighting).
              '${hijri.confidenceMarker == '~' ? '~' : ''}${hijri.day}',
              style: TextStyle(
                fontSize: 9,
                color: hijriColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _monthName(AppLocalizations l10n, int m) {
    // v2.33: hardcoded month names so the header ALWAYS shows
    // English digits, even in Urdu locale.
    // v2.34: Urdu names in Urdu locale.
    const namesEn = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const namesUr = [
      'جنوری', 'فروری', 'مارچ', 'اپریل', 'مئی', 'جون',
      'جولائی', 'اگست', 'ستمبر', 'اکتوبر', 'نومبر', 'دسمبر',
    ];
    final names = l10n.localeName == 'ur' ? namesUr : namesEn;
    return '${names[m - 1]} ${_calMonth.year}';
  }

  /// Keeps a stored value selectable even when it isn't a preset.
  List<T> _withCurrent<T>(List<T> presets, T current) =>
      presets.contains(current) ? presets : [...presets, current];

  /// Preset value chips (lime when selected).
  Widget _presetChips<T>({
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelect,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(label(o)),
              selected: o == selected,
              onSelected: (_) => onSelect(o),
              selectedColor: AppTheme.emerald,
              labelStyle: TextStyle(
                color: o == selected ? Colors.black : Colors.white70,
                fontWeight:
                    o == selected ? FontWeight.w700 : FontWeight.w500,
              ),
              backgroundColor: AppTheme.charcoalCard,
              side: BorderSide(
                color: o == selected
                    ? AppTheme.emerald
                    : Colors.white24,
              ),
            ),
        ],
      );

  Widget _stepperRow({
    required String label,
    required String valueText,
    required VoidCallback? onMinus,
    required VoidCallback? onPlus,
  }) =>
      Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: AppTheme.emerald),
            onPressed: onMinus,
          ),
          SizedBox(
            width: 72,
            child: Text(valueText, textAlign: TextAlign.center),
          ),
          IconButton(
            icon:
                const Icon(Icons.add_circle_outline, color: AppTheme.emerald),
            onPressed: onPlus,
          ),
        ],
      );

  String _toneDisplayName(AppLocalizations l10n, String uri) {
    if (uri == 'asset://assets/tones/alarmhq-classic.wav') return l10n.toneClassic;
    if (uri == 'system://default') return l10n.toneSystemDefault;
    return uri.split('/').last;
  }

  Widget _toneRow(String uri, String name) => RadioListTile<String>(
        title: Text(name),
        value: uri,
        activeColor: AppTheme.emerald,
      );
}
