// Every level, written out to be read rather than asserted.
//
// `test/level_test.dart` checks the same properties and fails on them; this
// prints them, which is what you want when the question is "are these levels
// any good" rather than "are these levels correct". Run it with `make levels`.

// Printing is the whole point of this file, so the lint against it is answered
// here rather than argued with. Nothing under lib/ prints.
// ignore_for_file: avoid_print

import 'package:mazehippo/puzzle/puzzle.dart';

void main() {
  final Stopwatch clock = Stopwatch()..start();
  int worst = 0;
  int shortfall = 0;

  // Coverage is the one number that says whether a board *looks* full: the
  // fraction of its dots that have an arrow standing on them. Arrow count alone
  // does not, because a level 100 arrow is twice the length of a level 1 one.
  print('  #  grade      size  arrows  dots  cover  free  taps  ms');
  for (int number = 1; number <= LevelPlan.levelCount; number++) {
    final Stopwatch one = Stopwatch()..start();
    final Level level = generateLevel(number);
    one.stop();

    final Board board = level.board();
    int covered = 0;
    for (final Arrow arrow in level.arrows) {
      covered += arrow.dots.length;
    }
    final int atStart = board.freeArrows.length;
    int peak = atStart;
    for (final Arrow arrow in level.solution) {
      board.remove(arrow);
      final int now = board.freeArrows.length;
      if (now > peak) {
        peak = now;
      }
    }
    if (one.elapsedMilliseconds > worst) {
      worst = one.elapsedMilliseconds;
    }
    if (level.arrows.length < level.plan.arrows) {
      shortfall++;
    }

    print(
      '${number.toString().padLeft(3)}  '
      '${level.grade.name.padRight(10)} '
      '${level.size.toString().padLeft(3)}  '
      '${level.arrows.length.toString().padLeft(6)}  '
      '${covered.toString().padLeft(4)}  '
      '${(100 * covered / (level.size * level.size)).round().toString().padLeft(4)}%  '
      '${atStart.toString().padLeft(4)}  '
      '${peak.toString().padLeft(4)}  '
      '${one.elapsedMilliseconds.toString().padLeft(4)}',
    );
  }
  clock.stop();
  print('');
  print('all 100 in ${clock.elapsedMilliseconds} ms, worst single $worst ms');
  print('levels short of their planned arrow count: $shortfall');
}
