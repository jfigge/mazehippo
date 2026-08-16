import 'dart:async';

import 'package:flutter/material.dart';

import '../puzzle/puzzle.dart';
import '../render/board_painter.dart';
import 'chrome.dart';
import 'game_screen.dart';
import 'store.dart';

/// All hundred levels, in four bands.
///
/// A grid rather than a list because the shape of the campaign is part of what
/// it says: ten easy, fifteen moderate, twenty difficult and then fifty-five
/// hard ones is a fact the player can see here and nowhere else.
class LevelPicker extends StatefulWidget {
  const LevelPicker({super.key});

  @override
  State<LevelPicker> createState() => _LevelPickerState();
}

class _LevelPickerState extends State<LevelPicker> {
  Future<void> _play(int number) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => GameScreen(startAt: number),
      ),
    );
    // The player may have cleared several levels before coming back.
    if (mounted) {
      setState(() {});
    }
  }

  /// The level numbers, split where the grade changes.
  static List<List<int>> get _bands {
    final List<List<int>> bands = <List<int>>[];
    for (int n = 1; n <= LevelPlan.levelCount; n++) {
      if (bands.isEmpty || LevelPlan.gradeOf(n) != LevelPlan.gradeOf(n - 1)) {
        bands.add(<int>[]);
      }
      bands.last.add(n);
    }
    return bands;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BoardPainter.background,
      appBar: AppBar(
        backgroundColor: BoardPainter.background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Levels', style: TextStyle(fontSize: 18)),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${progress.clearedCount} / ${LevelPlan.levelCount}',
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: <Widget>[
          for (final List<int> band in _bands) ...<Widget>[
            _BandHeading(grade: LevelPlan.gradeOf(band.first), levels: band),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: <Widget>[
                for (final int n in band)
                  _LevelTile(
                    number: n,
                    onPlay: progress.isUnlocked(n)
                        ? () => unawaited(_play(n))
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class _BandHeading extends StatelessWidget {
  const _BandHeading({required this.grade, required this.levels});

  final Grade grade;
  final List<int> levels;

  @override
  Widget build(BuildContext context) {
    final int done = levels.where(progress.isCleared).length;
    final Color colour = gradeColour(grade);
    return Row(
      children: <Widget>[
        Container(width: 3, height: 16, color: colour),
        const SizedBox(width: 8),
        Text(
          grade.name,
          style: TextStyle(
            color: colour,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        // Flexible, and not for tidiness. On a phone this row is a grade, an
        // explanation and a count across 358 pixels, and laid out at its
        // natural size it runs 77 pixels off the right — which the 800-wide
        // default test surface is too generous to show. It gives way here
        // because it is the only part of the row that can be shortened and
        // still leave the line making sense.
        Flexible(
          child: Text(
            // The whole of what the grade means, said once per band rather than
            // left for the player to infer from fifty-five hard levels.
            grade.branching == 1
                ? 'one arrow can go at a time'
                : '${grade.branching} arrows can go at a time',
            style: const TextStyle(color: Colors.white30, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$done/${levels.length}',
          style: const TextStyle(color: Colors.white24, fontSize: 12),
        ),
      ],
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({required this.number, required this.onPlay});

  final int number;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final bool locked = onPlay == null;
    final bool cleared = progress.isCleared(number);
    final Duration? best = progress.bestTime(number);
    final Color colour = gradeColour(LevelPlan.gradeOf(number));

    return Material(
      color: cleared ? colour.withValues(alpha: 0.16) : const Color(0xFF171B23),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: locked
                  ? Colors.white10
                  : colour.withValues(alpha: cleared ? 0.7 : 0.35),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (locked)
                const Icon(Icons.lock_outline, size: 18, color: Colors.white24)
              else
                Text(
                  '$number',
                  style: TextStyle(
                    color: cleared ? colour : Colors.white70,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (cleared) ...<Widget>[
                const SizedBox(height: 3),
                Hearts(left: progress.bestLives(number), size: 9),
                if (best != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    saidQuickly(best),
                    style: TextStyle(
                      color: colour.withValues(alpha: 0.75),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
