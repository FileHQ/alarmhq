import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:alarmhq/l10n/app_localizations.dart';

import '../theme/app_theme.dart';

/// Scroll-based time picker: AM/PM | Hours (H) | Minutes (M).
/// Up/down scroll columns like the reference design. Tick haptic on scroll.
/// Tap a number to type it directly. 12-hour format only.
class ScrollTimePicker extends StatefulWidget {
  final TimeOfDay initial;

  const ScrollTimePicker({super.key, required this.initial});

  /// Shows the picker as a bottom sheet. Returns the picked time or null.
  static Future<TimeOfDay?> show(BuildContext context, TimeOfDay initial) {
    return showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScrollTimePicker(initial: initial),
    );
  }

  @override
  State<ScrollTimePicker> createState() => _ScrollTimePickerState();
}

class _ScrollTimePickerState extends State<ScrollTimePicker> {
  late int _hour12; // 1-12
  late int _minute; // 0-59
  late bool _isAm;
  late FixedExtentScrollController _ampmCtrl;
  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;

  @override
  void initState() {
    super.initState();
    final h24 = widget.initial.hour;
    _isAm = h24 < 12;
    _hour12 = h24 % 12 == 0 ? 12 : h24 % 12;
    _minute = widget.initial.minute;
    _ampmCtrl = FixedExtentScrollController(initialItem: _isAm ? 0 : 1);
    _hourCtrl = FixedExtentScrollController(initialItem: _hour12 - 1);
    _minCtrl = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _ampmCtrl.dispose();
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  void _tick() => HapticFeedback.lightImpact();

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
          onSubmitted: (_) =>
              Navigator.pop(c, int.tryParse(ctrl.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(MaterialLocalizations.of(c).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(c, int.tryParse(ctrl.text.trim())),
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

  Widget _wheel<T>({
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
            onSelectedItemChanged: (i) {
              onChanged(i);
              _tick();
            },
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
                // AM/PM
                _wheel(
                  controller: _ampmCtrl,
                  itemCount: 2,
                  label: (i) => i == 0 ? 'AM' : 'PM',
                  onChanged: (i) => setState(() => _isAm = i == 0),
                  onTap: () {},
                ),
                // Hours 1-12
                _wheel(
                  controller: _hourCtrl,
                  itemCount: 12,
                  label: (i) =>
                      (i + 1).toString().padLeft(2, '0'),
                  onChanged: (i) => setState(() => _hour12 = i + 1),
                  onTap: () => _typeValue(
                    title: l10n.hoursShort,
                    current: _hour12,
                    min: 1,
                    max: 12,
                    onDone: (v) {
                      _hour12 = v;
                      _hourCtrl.jumpToItem(v - 1);
                    },
                  ),
                ),
                // Minutes 00-59
                _wheel(
                  controller: _minCtrl,
                  itemCount: 60,
                  label: (i) => i.toString().padLeft(2, '0'),
                  onChanged: (i) => setState(() => _minute = i),
                  onTap: () => _typeValue(
                    title: l10n.minutesShort,
                    current: _minute,
                    min: 0,
                    max: 59,
                    onDone: (v) {
                      _minute = v;
                      _minCtrl.jumpToItem(v);
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

/// One row inside a wheel. Selected styling is handled by the wheel's
/// magnification; tap opens the type-in dialog.
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
