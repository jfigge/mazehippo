import 'dart:async';

import 'package:flutter/material.dart';

import '../puzzle/puzzle.dart';
import '../render/board_painter.dart';

/// What every screen outside the board shares.

/// The colour a grade is drawn in, wherever a grade has to be shown.
///
/// Warm as it gets harder, which is the one thing the picker has to say at a
/// glance across a hundred tiles. These are not the arrow palette: an arrow's
/// colour deliberately means nothing (see [BoardPainter.colourOf]), and reusing
/// it here would suggest it did.
Color gradeColour(Grade grade) => switch (grade) {
  Grade.easy => const Color(0xFF6FCF7F),
  Grade.moderate => const Color(0xFF4FC3F7),
  Grade.difficult => const Color(0xFFFFB74D),
  Grade.hard => const Color(0xFFFF7B7B),
};

/// A time, as short as it can be said.
///
/// Tenths under a minute because that is the difference between two attempts at
/// the same board, and minutes and seconds above it because at that length
/// tenths are noise. Both have to fit under three hearts in a tile a fifth of a
/// phone wide, which is most of why neither has a unit on it.
String saidQuickly(Duration took) {
  final int tenths = (took.inMilliseconds / 100).round();
  final int seconds = tenths ~/ 10;
  if (seconds < 60) {
    return '$seconds.${tenths % 10}s';
  }
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A running clock, which repaints **itself** and nothing else.
///
/// The obvious way to show a timer is to rebuild the screen ten times a second,
/// and on a thirty-by-thirty board that means repainting nine hundred dots and
/// fifty arrows to move one digit. This holds its own ticker and its own state,
/// so the only thing that rebuilds is the text.
class RunningClock extends StatefulWidget {
  const RunningClock({super.key, required this.since, this.style});

  /// Null until the player has touched an arrow — the clock does not start with
  /// the level, it starts with the first move.
  final Stopwatch? since;

  final TextStyle? style;

  @override
  State<RunningClock> createState() => _RunningClockState();
}

class _RunningClockState extends State<RunningClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(milliseconds: 100),
      (Timer _) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Stopwatch? since = widget.since;
    return Text(
      since == null ? '' : saidQuickly(since.elapsed),
      style:
          widget.style ??
          const TextStyle(
            color: Colors.white38,
            fontSize: 13,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
    );
  }
}

/// A row of hearts: how many lives were left, out of three.
class Hearts extends StatelessWidget {
  const Hearts({super.key, required this.left, this.size = 18, this.of = 3});

  final int left;
  final int of;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < of; i++)
          Icon(
            i < left ? Icons.favorite : Icons.favorite_border,
            size: size,
            color: i < left ? BoardPainter.blockedColour : Colors.white24,
          ),
      ],
    );
  }
}

/// The one button style the menus use.
class MenuButton extends StatelessWidget {
  const MenuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint,
    this.wide = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? tint;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final Color colour = tint ?? Colors.white;
    return SizedBox(
      width: wide ? 240 : null,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon == null ? null : Icon(icon, size: 20),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colour,
          side: BorderSide(color: colour.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// The panel a level ends on, and the one the menus put questions in.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.title,
    this.detail,
    this.tint,
    required this.children,
  });

  final String title;
  final Widget? detail;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1E27),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: (tint ?? Colors.white).withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: tint ?? Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 12),
              detail!,
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}
