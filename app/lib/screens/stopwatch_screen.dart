import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alarmhq/l10n/app_localizations.dart';
import 'package:alarmhq/theme/app_theme.dart';

/// Stopwatch screen: large MM:SS.CS display, start/pause toggle, lap, reset.
///
/// Uses Dart's [Stopwatch] for elapsed tracking and a 30ms periodic timer
/// for UI updates. Disposing the screen stops UI updates but the Stopwatch
/// keeps its elapsed time.
class StopwatchScreen extends StatefulWidget {
  const StopwatchScreen({super.key});

  @override
  State<StopwatchScreen> createState() => _StopwatchScreenState();
}

class _LapEntry {
  final int number;
  final Duration lapTime;
  final Duration totalTime;

  const _LapEntry(this.number, this.lapTime, this.totalTime);
}

class _StopwatchScreenState extends State<StopwatchScreen> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  final List<_LapEntry> _laps = [];
  Duration _lastLapTotal = Duration.zero;

  bool get _running => _stopwatch.isRunning;
  bool get _hasElapsed =>
      _stopwatch.elapsed > Duration.zero || _laps.isNotEmpty;

  @override
  void dispose() {
    // Stop UI updates; the Stopwatch itself keeps its elapsed time.
    _ticker?.cancel();
    super.dispose();
  }

  void _ensureTicker() {
    _ticker ??= Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _toggleStartPause() {
    setState(() {
      if (_running) {
        _stopwatch.stop();
        _ticker?.cancel();
        _ticker = null;
      } else {
        _stopwatch.start();
        _ensureTicker();
      }
    });
  }

  void _lap() {
    if (!_running) return;
    setState(() {
      final total = _stopwatch.elapsed;
      final lapTime = total - _lastLapTotal;
      _lastLapTotal = total;
      // Latest lap on top.
      _laps.insert(0, _LapEntry(_laps.length + 1, lapTime, total));
    });
  }

  void _reset() {
    setState(() {
      _stopwatch.stop();
      _stopwatch.reset();
      _ticker?.cancel();
      _ticker = null;
      _laps.clear();
      _lastLapTotal = Duration.zero;
    });
  }

  /// MM:SS.CS (H:MM:SS.CS past one hour). English digits only.
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final cs = ((d.inMilliseconds % 1000) ~/ 10).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s.$cs';
    return '$m:$s.$cs';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final displayColor = isLight ? AppTheme.lightTimeText : Colors.white;
    final subColor = isLight ? Colors.black54 : Colors.white70;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stopwatch),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            // Large time display — Roboto: JameelNoori has no digit glyphs.
            Text(
              formatDuration(_stopwatch.elapsed),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 56,
                fontWeight: FontWeight.w400,
                color: displayColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 24),
            // Buttons: Lap | Start/Pause | Reset.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundButton(
                    label: l10n.swLap,
                    onPressed: _running ? _lap : null,
                    isLight: isLight,
                  ),
                  _primaryButton(
                    label: _running
                        ? l10n.swPause
                        : (_hasElapsed ? l10n.swResume : l10n.swStart),
                    onPressed: _toggleStartPause,
                  ),
                  _roundButton(
                    label: l10n.swReset,
                    onPressed: _hasElapsed && !_running ? _reset : null,
                    isLight: isLight,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            // Lap list — latest on top.
            Expanded(
              child: _laps.isEmpty
                  ? Center(
                      child: Text(
                        l10n.swLap,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: subColor,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 8),
                      itemCount: _laps.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final lap = _laps[i];
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 64,
                                child: Text(
                                  '${lap.number}',
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  // Lap time.
                                  formatDuration(lap.lapTime),
                                  style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                              Text(
                                // Total time at this lap.
                                formatDuration(lap.totalTime),
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: subColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 96,
      height: 96,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.emerald,
          foregroundColor: Colors.black,
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
