import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/theme/app_theme.dart';

/// Timer screen: HH:MM:SS countdown with a simple beep when done.
///
/// The countdown is anchored to a target [_endTime] so it keeps correct
/// time even if the UI ticker is delayed or the app was backgrounded.
/// On finish: three short system beeps + vibration and a "Time's up" dialog.
class TimerScreen extends StatefulWidget {
  /// When true, renders without its own AppBar (embedded in ClockScreen).
  final bool embedded;

  const TimerScreen({super.key, this.embedded = false});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

enum _TimerPhase { idle, running, paused, done }

class _TimerScreenState extends State<TimerScreen> {
  int _hours = 0;
  int _minutes = 5;
  int _seconds = 0;

  _TimerPhase _phase = _TimerPhase.idle;
  DateTime? _endTime;
  Duration _remaining = Duration.zero;
  Timer? _ticker;
  bool _beeping = false;

  Duration get _setDuration =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  Duration get _displayRemaining {
    if (_phase == _TimerPhase.running && _endTime != null) {
      final r = _endTime!.difference(DateTime.now());
      return r.isNegative ? Duration.zero : r;
    }
    if (_phase == _TimerPhase.idle) return _setDuration;
    return _remaining;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    // 250ms ticks: the displayed value changes each second, but the
    // finish is detected promptly.
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_phase == _TimerPhase.running && _endTime != null) {
        if (!_endTime!.difference(DateTime.now()).isNegative) {
          setState(() {});
          return;
        }
        _finish();
        return;
      }
      setState(() {});
    });
  }

  void _start() {
    if (_setDuration == Duration.zero) return;
    setState(() {
      _endTime = DateTime.now().add(_setDuration);
      _remaining = _setDuration;
      _phase = _TimerPhase.running;
      _startTicker();
    });
  }

  void _pause() {
    setState(() {
      _remaining = _displayRemaining;
      _phase = _TimerPhase.paused;
      _ticker?.cancel();
      _ticker = null;
    });
  }

  void _resume() {
    setState(() {
      _endTime = DateTime.now().add(_remaining);
      _phase = _TimerPhase.running;
      _startTicker();
    });
  }

  void _reset() {
    setState(() {
      _ticker?.cancel();
      _ticker = null;
      _phase = _TimerPhase.idle;
      _endTime = null;
      _remaining = Duration.zero;
      _beeping = false;
    });
  }

  void _finish() {
    _ticker?.cancel();
    _ticker = null;
    if (!mounted) return;
    setState(() {
      _phase = _TimerPhase.done;
      _remaining = Duration.zero;
      _endTime = null;
    });
    _playBeeps();
    _showDoneDialog();
  }

  /// Three loud beeps (bundled WAV) + vibration.
  /// v2.54: audioplayers is reliable across devices; SystemSound.alert
  /// was silent on some phones.
  Future<void> _playBeeps() async {
    if (_beeping) return;
    _beeping = true;
    final player = AudioPlayer();
    try {
      for (var i = 0; i < 3; i++) {
        if (!mounted) break;
        try {
          await player.play(AssetSource('tones/timer_beep.wav'));
        } catch (_) {
          // Fallback to system sound if asset fails.
          SystemSound.play(SystemSoundType.alert);
        }
        HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      await player.dispose();
      if (mounted) setState(() => _beeping = false);
    }
  }

  void _showDoneDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (c) => AlertDialog(
        title: Text(l10n.tmrDone),
        content: const Text(
          // Big 00:00:00 — Roboto: JameelNoori has no digit glyphs.
          '00:00:00',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: 40,
            fontWeight: FontWeight.w400,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(c).pop();
              _reset();
            },
            child: Text(l10n.dismiss),
          ),
        ],
      ),
    );
  }

  /// HH:MM:SS. English digits only.
  static String formatHMS(Duration d) {
    final total = d.isNegative ? Duration.zero : d;
    final h = total.inHours.toString().padLeft(2, '0');
    final m = (total.inMinutes % 60).toString().padLeft(2, '0');
    final s = (total.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<int?> _promptNumber({
    required String title,
    required int current,
    required int min,
    required int max,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: '$current');
    int? parse() {
      final n = int.tryParse(ctrl.text.trim());
      if (n == null) return null;
      return n.clamp(min, max);
    }

    return showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          // English digits only.
          decoration: InputDecoration(
            hintText: '$min – $max',
            helperText: '$min – $max',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(parse()),
            child: Text(l10n.go),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final displayColor = isLight ? AppTheme.lightTimeText : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white70;

    final idle = _phase == _TimerPhase.idle;
    final running = _phase == _TimerPhase.running;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(l10n.timer),
              centerTitle: false,
            ),
      body: SafeArea(
        // v2.53: scrollable when embedded so nothing is cut off
        // on small screens below the atomic panel.
        child: widget.embedded
            ? SingleChildScrollView(
                child: _timerBody(context, l10n, isLight, displayColor,
                    subColor, idle, running),
              )
            : _timerBody(context, l10n, isLight, displayColor, subColor,
                idle, running),
      ),
    );
  }

  Widget _timerBody(
    BuildContext context,
    AppLocalizations l10n,
    bool isLight,
    Color displayColor,
    Color subColor,
    bool idle,
    bool running,
  ) {
    return Column(
          children: [
            const SizedBox(height: 32),
            // Countdown display — Roboto: JameelNoori has no digit glyphs.
            Text(
              formatHMS(_displayRemaining),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 56,
                fontWeight: FontWeight.w400,
                color: displayColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tmrSetTime,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: subColor,
              ),
            ),
            const SizedBox(height: 24),
            // Steppers — only while setting the time.
            if (idle) ...[
              _stepper(
                label: l10n.tmrHours,
                value: _hours,
                min: 0,
                max: 99,
                subColor: subColor,
                onChanged: (v) => setState(() => _hours = v),
              ),
              _stepper(
                label: l10n.tmrMinutes,
                value: _minutes,
                min: 0,
                max: 59,
                subColor: subColor,
                onChanged: (v) => setState(() => _minutes = v),
              ),
              _stepper(
                label: l10n.tmrSeconds,
                value: _seconds,
                min: 0,
                max: 59,
                subColor: subColor,
                onChanged: (v) => setState(() => _seconds = v),
              ),
              const SizedBox(height: 16),
            ] else
              const Spacer(),
            // Buttons.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!idle)
                    _roundButton(
                      label: l10n.tmrReset,
                      onPressed: _reset,
                      isLight: isLight,
                    ),
                  _primaryButton(
                    label: running
                        ? l10n.tmrPause
                        : (_phase == _TimerPhase.paused
                            ? l10n.tmrResume
                            : l10n.tmrStart),
                    onPressed: idle
                        ? (_setDuration == Duration.zero ? null : _start)
                        : (running ? _pause : _resume),
                  ),
                  if (!idle) const SizedBox(width: 76),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        );
  }

  /// [-] value [+] stepper; the value is tappable for direct numeric entry.
  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required Color subColor,
    required ValueChanged<int> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value > min ? () => onChanged(value - 1) : null,
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final v = await _promptNumber(
                  title: label,
                  current: value,
                  min: min,
                  max: max,
                );
                if (v != null) onChanged(v);
              },
              child: Text(
                // English digits only — plain toString().
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value < max ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 96,
      height: 96,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.emerald,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppTheme.emerald.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    required String label,
    required VoidCallback? onPressed,
    required bool isLight,
  }) {
    return SizedBox(
      width: 76,
      height: 76,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: isLight ? Colors.black26 : Colors.white30,
          ),
          foregroundColor: isLight ? Colors.black87 : Colors.white,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
