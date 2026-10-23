import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/atomic_time_service.dart';
import '../theme/app_theme.dart';
import 'atomic_panel.dart';
import 'world_clock_screen.dart';
import 'stopwatch_screen.dart';
import 'timer_screen.dart';

/// v2.53: Clock tab — 4 sub-tabs: Atomic | World Clock | Stopwatch | Timer.
/// Atomic time is its own tab (not always on top), so the other tabs
/// get full screen space and buttons never need scrolling.
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

    // 4 tabs: Atomic | World clock | Stopwatch | Timer.
    final tabLabels = [
      l10n.atomicTab,
      l10n.worldClock,
      l10n.stopwatch,
      l10n.timer,
    ];
    final tabIcons = ['⏱️', '🌍', '⏱️', '⏲️'];

    final barBg = isLight ? AppTheme.lightCardBg : const Color(0xFF23272E);
    final activeBg = isLight ? AppTheme.lightCardBorder : const Color(0xFF3A4048);
    final activeColor = AppTheme.emerald;
    final inactiveColor = isLight ? Colors.black54 : Colors.white60;

    return Scaffold(
      backgroundColor: isLight ? Colors.white : AppTheme.charcoal,
      body: SafeArea(
        child: Column(
          children: [
            // Section selector — 4 tabs, icon above label, FittedBox
            // shrinks text so labels never cut off.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: barBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (var i = 0; i < tabLabels.length; i++)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _section = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 2),
                            decoration: BoxDecoration(
                              color: _section == i
                                  ? activeBg
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tabIcons[i],
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tabLabels[i],
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: _section == i
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: _section == i
                                          ? activeColor
                                          : inactiveColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _section,
                children: [
                  // Atomic time — its own tab (scrollable).
                  const SingleChildScrollView(
                    child: AtomicPanel(),
                  ),
                  WorldClockScreen(
                    nowProvider: _useAtomic
                        ? () => AtomicTimeService.instance
                            .now()
                            .toUtc()
                        : null,
                  ),
                  const StopwatchScreen(embedded: true),
                  const TimerScreen(embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
