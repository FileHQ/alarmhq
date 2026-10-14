import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Infinite-wheel helpers (pure functions — unit tested).
// The wheels use large virtual item counts with modulo indexing so the user
// can scroll forever in either direction, like the Realme/Samsung pickers.
// ---------------------------------------------------------------------------

/// Number of virtual rows per wheel. Large enough that a user can never
/// reach an end in practice.
const int kHourWheelCount = 12000; // 1000 x 12
const int kMinuteWheelCount = 120000; // 2000 x 60
const int kAmPmWheelCount = 4000; // 2000 x 2

/// Hour value (1-12) shown at virtual [index] ([index] >= 0).
int hourValueAt(int index) => (index % 12) + 1;

/// Minute value (0-59) shown at virtual [index] ([index] >= 0).
int minuteValueAt(int index) => index % 60;

/// True when virtual [index] of the AM/PM wheel shows AM ([index] >= 0).
bool isAmAt(int index) => index % 2 == 0;

/// True when moving the hour wheel from [prevHour] to [newHour] crossed the
/// 12 boundary (12 -> 1 or 1 -> 12). The caller must toggle AM/PM.
bool hourWrapTogglesAmPm(int prevHour, int newHour) =>
    (prevHour == 12 && newHour == 1) || (prevHour == 1 && newHour == 12);

/// Virtual index nearest to (at or after) [currentIndex] that shows [hour12].
int nearestHourIndex(int currentIndex, int hour12) {
  final cur = currentIndex % 12;
  final want = hour12 - 1;
  return currentIndex + ((want - cur + 12) % 12);
}

/// Virtual index nearest to (at or after) [currentIndex] that shows [minute].
int nearestMinuteIndex(int currentIndex, int minute) {
  final cur = currentIndex % 60;
  return currentIndex + ((minute - cur + 60) % 60);
}

/// Scroll-based time picker: AM/PM | Hours (H) | Minutes (M).
/// All three columns loop infinitely in both directions (hours 12<->1,
/// minutes 59<->0); AM/PM flips automatically when the hours cross 12.
/// Audible tick + haptic on every scroll step. Tap a number to type it.
/// 12-hour format only.
class ScrollTimePicker extends StatefulWidget {
  final TimeOfDay initial;

  const ScrollTimePicker({super.key, required this.initial});

  /// Shows the picker as a bottom sheet. Returns the picked time or null.
  static Future<TimeOfDay?> show(BuildContext context, TimeOfDay initial) {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        // Keeps the sheet (esp. the Done button) above the system
        // navigation bar on edge-to-edge devices.
        top: false,
        child: SingleChildScrollView(
          // Safety net for very small screens: the sheet scrolls instead
          // of cutting content off.
          child: ScrollTimePicker(initial: initial),
        ),
      ),
    );
  }

  @override
  State<ScrollTimePicker> createState() => _ScrollTimePickerState();
}

class _ScrollTimePickerState extends State<ScrollTimePicker> {
  late int _hour12; // 1-12
  late int _minute; // 0-59
  late bool _isAm;
  late int _hourIndex;
  late int _minIndex;
  late int _ampmIndex;
  late FixedExtentScrollController _ampmCtrl;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;

  /// While true, AM/PM wheel callbacks come from our own programmatic jump
  /// (hour wrap) and must not play an extra tick.
  bool _ampmJumping = false;

  @override
  void initState() {
    super.initState();
    final h24 = widget.initial.hour;
    _isAm = h24 < 12;
    _hour12 = h24 % 12 == 0 ? 12 : h24 % 12;
    _minute = widget.initial.minute;
    // Center the wheels on a multiple of the cycle so modulo math is exact.
    _hourIndex = (kHourWheelCount ~/ 2) + (_hour12 - 1);
    _minIndex = (kMinuteWheelCount ~/ 2) + _minute;
    _ampmIndex = (kAmPmWheelCount ~/ 2) + (_isAm ? 0 : 1);
    _ampmCtrl = FixedExtentScrollController(initialItem: _ampmIndex);
    _hourCtrl = FixedExtentScrollController(initialItem: _hourIndex);
    _minCtrl = FixedExtentScrollController(initialItem: _minIndex);
  }

  @override
  void dispose() {
    _ampmCtrl.dispose();
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  /// Audible tick + haptic on every scroll step.
  void _tick() {
    unawaited(HapticFeedback.lightImpact());
    unawaited(SystemSound.play(SystemSoundType.click));
  }

  TimeOfDay get _picked {
    final h24 = _isAm ? (_hour12 % 12) : (_hour12 % 12 + 12);
    return TimeOfDay(hour: h24, minute: _minute);
  }

  /// "Alarm in X hours Y minutes" preview from now.
  String _alarmInText(AppLocalizations l10n) {
    final now = DateTime.now();
    final p = _picked;
    var target = DateTime(now.year, now.month, now.day, p.hour, p.minute);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    final diff = target.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    String dur;
    if (h > 0 && m > 0) {
      dur = '$h h $m m';
    } else if (h > 0) {
      dur = '$h h';
    } else {
      dur = '$m m';
    }
    return l10n.alarmIn(dur);
  }

  Future<void> _typeValue({
    required String title,
    required int current,
    required int min,
    required int max,
    required ValueChanged<int> onDone,
  }) async {
    final ctrl = TextEditingController(text: current.toString());
    final v = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => Navigator.pop(c, int.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text.trim())),
            child: Text(MaterialLocalizations.of(c).okButtonLabel),
          ),
        ],
      ),
    );
    if (v != null && v >= min && v <= max) {
      setState(() => onDone(v));
      _tick();
    }
  }

  void _onHourChanged(int index) {
    final newHour = hourValueAt(index);
    if (hourWrapTogglesAmPm(_hour12, newHour)) {
      // Crossing 12 <-> 1 flips AM/PM; move the AM/PM wheel along so it
      // always shows the true value.
      _isAm = !_isAm;
      _ampmIndex += 1;
      _ampmJumping = true;
      _ampmCtrl.jumpToItem(_ampmIndex);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _ampmJumping = false);
    }
    _hour12 = newHour;
    _hourIndex = index;
    setState(() {});
    _tick();
  }

  void _onMinuteChanged(int index) {
    _minute = minuteValueAt(index);
    _minIndex = index;
    setState(() {});
    _tick();
  }

  void _onAmPmChanged(int index) {
    _ampmIndex = index;
    _isAm = isAmAt(index);
    setState(() {});
    if (_ampmJumping) {
      _ampmJumping = false;
    } else {
      _tick();
    }
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) label,
    required ValueChanged<int> onChanged,
    required VoidCallback onTap,
    double width = 90,
  }) {
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: 56,
            perspective: 0.003,
            diameterRatio: 1.6,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onChanged,
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (c, i) {
                if (i < 0 || i >= itemCount) return null;
                return _WheelItem(
                  text: label(i),
                  onTap: onTap,
                );
              },
              childCount: itemCount,
            ),
          ),
          // selection highlight lines
          IgnorePointer(
            child: Center(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppTheme.emerald.withAlpha(90), width: 1),
                    bottom: BorderSide(
                        color: AppTheme.emerald.withAlpha(90), width: 1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.charcoalSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 12,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _alarmInText(l10n),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.emerald,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          // column headers
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 90),
              SizedBox(
                width: 90,
                child: Text(l10n.hoursShort,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              SizedBox(
                width: 90,
                child: Text(l10n.minutesShort,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
          SizedBox(
            height: 200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // AM/PM (loops forever too)
                _wheel(
                  controller: _ampmCtrl,
                  itemCount: kAmPmWheelCount,
                  label: (i) => isAmAt(i) ? 'AM' : 'PM',
                  onChanged: _onAmPmChanged,
                  onTap: () {
                    // Tap toggles AM/PM.
                    _ampmCtrl.jumpToItem(_ampmIndex + 1);
                  },
                ),
                // Hours 1-12 (infinite loop)
                _wheel(
                  controller: _hourCtrl,
                  itemCount: kHourWheelCount,
                  label: (i) => hourValueAt(i).toString().padLeft(2, '0'),
                  onChanged: _onHourChanged,
                  onTap: () => _typeValue(
                    title: l10n.hoursShort,
                    current: _hour12,
                    min: 1,
                    max: 12,
                    onDone: (v) {
                      _hour12 = v;
                      _hourIndex = nearestHourIndex(_hourIndex, v);
                      _hourCtrl.jumpToItem(_hourIndex);
                    },
                  ),
                ),
                // Minutes 00-59 (infinite loop)
                _wheel(
                  controller: _minCtrl,
                  itemCount: kMinuteWheelCount,
                  label: (i) => minuteValueAt(i).toString().padLeft(2, '0'),
                  onChanged: _onMinuteChanged,
                  onTap: () => _typeValue(
                    title: l10n.minutesShort,
                    current: _minute,
                    min: 0,
                    max: 59,
                    onDone: (v) {
                      _minute = v;
                      _minIndex = nearestMinuteIndex(_minIndex, v);
                      _minCtrl.jumpToItem(_minIndex);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.emerald,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => Navigator.pop(context, _picked),
              child: Text(l10n.done,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row inside a wheel. Tap opens the type-in dialog.
class _WheelItem extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _WheelItem({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
