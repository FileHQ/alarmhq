import 'package:flutter/material.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../models/alarm.dart';
import '../services/alarm_repository.dart';
import '../services/app_settings.dart';
import '../services/next_occurrence.dart';
import 'alarm_edit_screen.dart';

/// Main screen: the list of alarms with on/off toggles and next-ring preview.
class AlarmListScreen extends StatefulWidget {
  final AlarmRepository repo;
  final AppSettings settings;

  const AlarmListScreen({super.key, required this.repo, required this.settings});

  @override
  State<AlarmListScreen> createState() => _AlarmListScreenState();
}

class _AlarmListScreenState extends State<AlarmListScreen> {
  Future<void> _openEditor({AlarmModel? existing}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AlarmEditScreen(
          repo: widget.repo,
          settings: widget.settings,
          existing: existing,
        ),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _confirmDelete(AlarmModel alarm) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.deleteAlarmTitle),
        content: Text(l10n.deleteAlarmBody(alarm.label.isEmpty
            ? _timeText(alarm)
            : alarm.label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.confirmDelete),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.repo.remove(alarm.id);
      if (mounted) setState(() {});
    }
  }

  String _timeText(AlarmModel a) {
    final hh = a.hour.toString().padLeft(2, '0');
    final mm = a.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _repeatSummary(AppLocalizations l10n, AlarmModel a) {
    switch (a.mode) {
      case AlarmRepeatMode.once:
        return l10n.onceSummary;
      case AlarmRepeatMode.interval:
        return l10n.everyNDaysSummary(a.intervalDays);
      case AlarmRepeatMode.weekly:
        final names = [
          l10n.weekdayMon,
          l10n.weekdayTue,
          l10n.weekdayWed,
          l10n.weekdayThu,
          l10n.weekdayFri,
          l10n.weekdaySat,
          l10n.weekdaySun,
        ];
        final days = a.weekDays.map((w) => names[w - 1]).join(' · ');
        return l10n.weeklySummary(days);
    }
  }

  String _nextText(AppLocalizations l10n, AlarmModel a) {
    if (!a.enabled) return l10n.alarmOff;
    final next = NextOccurrence.nextTrigger(a, DateTime.now());
    if (next == null) return l10n.disabled;
    final time =
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(next.year, next.month, next.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return l10n.nextRing(l10n.todayAt(time));
    if (diff == 1) return l10n.nextRing(l10n.tomorrowAt(time));
    final date = '${next.day}/${next.month}';
    return l10n.nextRing(l10n.dateAt(date, time));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final alarms = widget.repo.alarms;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alarms)),
      body: alarms.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alarm_off,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(l10n.noAlarms,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(l10n.noAlarmsHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: alarms.length,
              itemBuilder: (c, i) {
                final a = alarms[i];
                return Dismissible(
                  key: ValueKey(a.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    await _confirmDelete(a);
                    return false; // we handle removal ourselves
                  },
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      title: Text(
                        _timeText(a),
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (a.label.isNotEmpty) Text(a.label),
                          Text(_repeatSummary(l10n, a)),
                          Text(
                            _nextText(l10n, a),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      trailing: Switch(
                        value: a.enabled,
                        onChanged: (v) async {
                          await widget.repo.setEnabled(a, v);
                          if (mounted) setState(() {});
                        },
                      ),
                      onTap: () => _openEditor(existing: a),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: l10n.addAlarm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
