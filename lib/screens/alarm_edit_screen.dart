import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../models/alarm.dart';
import '../services/alarm_repository.dart';
import '../services/app_settings.dart';
import '../services/native_bridge.dart';
import '../services/next_occurrence.dart';

/// Create / edit one alarm, including the signature "every N days" mode.
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
  late DateTime _onceDate;
  late int _intervalDays;
  late DateTime _intervalStart;
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
    _onceDate = e?.onceDate ?? now.add(const Duration(days: 1));
    _intervalDays = e?.intervalDays ?? 5;
    _intervalStart =
        e?.intervalStart ?? DateTime(now.year, now.month, now.day);
    _snoozeMinutes = e?.snoozeMinutes ?? widget.settings.defaultSnoozeMinutes;
    _maxSnoozes = e?.maxSnoozes ?? 3;
    _toneUri = e?.toneUri ?? 'asset://tones/alarmhq-classic.wav';
    _toneName = e?.toneName ?? 'Classic';
    _vibration = e?.vibration ?? true;
    _fadeInSeconds = e?.fadeInSeconds ?? 30;
    _labelCtrl.addListener(() => _dirty = true);
  }

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
        onceDate: DateTime(_onceDate.year, _onceDate.month, _onceDate.day),
        intervalDays: _intervalDays,
        intervalStart: DateTime(
            _intervalStart.year, _intervalStart.month, _intervalStart.day),
        snoozeMinutes: _snoozeMinutes,
        maxSnoozes: _maxSnoozes,
        toneUri: _toneUri,
        toneName: _toneName,
        vibration: _vibration,
        fadeInSeconds: _fadeInSeconds,
        enabled: widget.existing?.enabled ?? true,
      );

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_mode == AlarmRepeatMode.interval && _intervalDays < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.intervalTooSmall)),
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
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) _markDirty(() => _time = t);
  }

  Future<void> _pickDate({required bool forIntervalStart}) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: forIntervalStart ? _intervalStart : _onceDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (d != null) {
      _markDirty(() {
        if (forIntervalStart) {
          _intervalStart = d;
        } else {
          _onceDate = d;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final timeText =
        '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
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
          title: Text(
              widget.existing == null ? l10n.newAlarm : l10n.editAlarm),
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(l10n.save,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---- time ----
            Center(
              child: InkWell(
                onTap: _pickTime,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12),
                  child: Text(
                    timeText,
                    style:
                        Theme.of(context).textTheme.displayLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
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
            // ---- repeat mode ----
            Text(l10n.repeat,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<AlarmRepeatMode>(
              segments: [
                ButtonSegment(
                    value: AlarmRepeatMode.weekly, label: Text(l10n.repeatWeekly)),
                ButtonSegment(
                    value: AlarmRepeatMode.once, label: Text(l10n.repeatOnce)),
                ButtonSegment(
                    value: AlarmRepeatMode.interval,
                    label: Text(l10n.repeatInterval)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _markDirty(() => _mode = s.first),
            ),
            const SizedBox(height: 12),
            if (_mode == AlarmRepeatMode.weekly) _weeklyPicker(l10n),
            if (_mode == AlarmRepeatMode.once) _oncePicker(l10n),
            if (_mode == AlarmRepeatMode.interval) _intervalPicker(l10n),
            const Divider(height: 32),
            // ---- snooze ----
            _sectionTitle(l10n.snooze),
            _stepperRow(
              label: l10n.snoozeLength,
              valueText: l10n.minutesUnit(_snoozeMinutes),
              onMinus: _snoozeMinutes > 1
                  ? () => _markDirty(() => _snoozeMinutes--)
                  : null,
              onPlus: _snoozeMinutes < 60
                  ? () => _markDirty(() => _snoozeMinutes++)
                  : null,
            ),
            _stepperRow(
              label: l10n.maxSnoozes,
              valueText:
                  _maxSnoozes == 0 ? l10n.noSnooze : l10n.timesUnit(_maxSnoozes),
              onMinus: _maxSnoozes > 0
                  ? () => _markDirty(() => _maxSnoozes--)
                  : null,
              onPlus: _maxSnoozes < 10
                  ? () => _markDirty(() => _maxSnoozes++)
                  : null,
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
                  _toneRow('asset://tones/alarmhq-classic.wav',
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
              title: Text(
                  _previewing ? l10n.toneStop : l10n.tonePreview),
              leading: Icon(
                  _previewing ? Icons.stop : Icons.play_arrow),
              onTap: _togglePreview,
            ),
            SwitchListTile(
              title: Text(l10n.vibration),
              value: _vibration,
              onChanged: (v) => _markDirty(() => _vibration = v),
            ),
            ListTile(
              title: Text(l10n.fadeIn),
              subtitle: Slider(
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

  bool get _isBuiltInTone =>
      _toneUri == 'asset://tones/alarmhq-classic.wav' ||
      _toneUri == 'system://default';

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

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
    return Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final wd = i + 1;
        final selected = _weekDays.contains(wd);
        return FilterChip(
          label: Text(names[i]),
          selected: selected,
          onSelected: (v) => _markDirty(() {
            if (v) {
              _weekDays.add(wd);
            } else {
              _weekDays.remove(wd);
            }
          }),
        );
      }),
    );
  }

  Widget _oncePicker(AppLocalizations l10n) => ListTile(
        title: Text(l10n.date),
        subtitle: Text(_dateText(_onceDate)),
        leading: const Icon(Icons.calendar_today),
        onTap: () => _pickDate(forIntervalStart: false),
      );

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
          leading: const Icon(Icons.event_repeat),
          onTap: () => _pickDate(forIntervalStart: true),
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
                  Icon(Icons.alarm,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '${_dateText(t)}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

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
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onMinus,
          ),
          SizedBox(
            width: 72,
            child: Text(valueText, textAlign: TextAlign.center),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onPlus,
          ),
        ],
      );

  String _toneDisplayName(AppLocalizations l10n, String uri) {
    if (uri == 'asset://tones/alarmhq-classic.wav') return l10n.toneClassic;
    if (uri == 'system://default') return l10n.toneSystemDefault;
    return uri.split('/').last;
  }

  Widget _toneRow(String uri, String name) => RadioListTile<String>(
        title: Text(name),
        value: uri,
      );
}
