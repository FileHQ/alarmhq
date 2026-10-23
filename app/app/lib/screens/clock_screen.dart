import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/atomic_time_service.dart';
import '../theme/app_theme.dart';
import 'atomic_panel.dart';
import 'world_clock_screen.dart';
import 'stopwatch_screen.dart';
import 'timer_screen.dart';

/// v2.51: Clock tab — atomic time panel on top, then World Clock /
/// Stopwatch / Timer sections.
class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  int _section = 0;
  bool _useAtomic = false;

  @override
  void initState() {
    super.initState();
    AtomicTimeService.instance.addListener(_onAtomic);
    // Try a silent sync on open.
    AtomicTimeService.instance.sync();
  }

  @override
  void dispose() {
    AtomicTimeService.instance.removeListener(_onAtomic);
    super.dispose();
  }

  void _onAtomic() {
    if (!mounted) return;
    setState(() {
      _useAtomic = AtomicTimeService.instance.hasSync;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final sections = [l10n.worldClock, l10n.stopwatch, l10n.timer];

    return Scaffold(
      backgroundColor: isLight ? Colors.white : AppTheme.charcoal,
      body: SafeArea(
        child: Column(
          children: [
            const AtomicPanel(),
            // Section selector.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < sections.length; i++)
                    ButtonSegment(value: i, label: Text(sections[i])),
                ],
                selected: {_section},
                onSelectionChanged: (s) =>
                    setState(() => _section = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _section,
                children: [
                  WorldClockScreen(
                    nowProvider: _useAtomic
                        ? () => AtomicTimeService.instance
                            .now()
                            .toUtc()
                        : null,
                  ),
                  const StopwatchScreen(),
                  const TimerScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
