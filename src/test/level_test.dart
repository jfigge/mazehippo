// All hundred levels, generated and solved.
//
// This is the whole safety net under `generate.dart`. The generator is the only
// thing that decides what a level is — there is no level data to inspect and no
// designer to notice — so a level it gets wrong is a level nobody can finish,
// and there is nowhere else for that to be caught.

import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/puzzle/puzzle.dart';

/// Level numbers, once, so each test reads as a claim about the campaign rather
/// than a loop with an assertion in it.
final List<int> everyLevel = <int>[
  for (int n = 1; n <= LevelPlan.levelCount; n++) n,
];

void main() {
  group('the campaign', () {
    test(
      'is ten easy, fifteen moderate, twenty difficult, fifty-five hard',
      () {
        final Map<Grade, int> counted = <Grade, int>{};
        for (final int n in everyLevel) {
          final Grade grade = LevelPlan.gradeOf(n);
          counted[grade] = (counted[grade] ?? 0) + 1;
        }
        expect(counted, <Grade, int>{
          Grade.easy: 10,
          Grade.moderate: 15,
          Grade.difficult: 20,
          Grade.hard: 55,
        });
      },
    );

    test('starts at 14 dots, grows by four a block, and stops at 30', () {
      expect(LevelPlan.forLevel(1).size, 14);
      expect(LevelPlan.forLevel(10).size, 14);
      expect(LevelPlan.forLevel(11).size, 18);
      expect(LevelPlan.forLevel(41).size, LevelPlan.lastSize);
      // And held from there: past 30 dots a phone cannot show a board at a size
      // a finger can aim at. See [LevelPlan.lastSize].
      expect(LevelPlan.forLevel(50).size, LevelPlan.lastSize);
      expect(LevelPlan.forLevel(100).size, LevelPlan.lastSize);
      for (final int n in everyLevel.skip(1)) {
        expect(
          LevelPlan.forLevel(n).size,
          greaterThanOrEqualTo(LevelPlan.forLevel(n - 1).size),
        );
      }
    });

    test('never has fewer arrows than the level before it', () {
      // The count comes from [LevelPlan.arrowsPerBlock], one entry per board
      // size, and each entry is at least two above the last — which is what
      // stops the small climb inside a block from outrunning the step between
      // two of them and reading as the game emptying out.
      for (final int n in everyLevel.skip(1)) {
        expect(
          LevelPlan.forLevel(n).arrows,
          greaterThanOrEqualTo(LevelPlan.forLevel(n - 1).arrows),
          reason: 'level $n is a step backwards',
        );
      }
    });

    test('has a mark at the start of every block, and one at the end', () {
      expect(
        LevelPlan.arrowsAtBlock,
        hasLength(LevelPlan.levelCount ~/ 10 + 1),
      );
      // Non-decreasing, which is what makes the interpolation between them
      // non-decreasing and so the campaign never step backwards.
      for (int i = 1; i < LevelPlan.arrowsAtBlock.length; i++) {
        expect(
          LevelPlan.arrowsAtBlock[i],
          greaterThanOrEqualTo(LevelPlan.arrowsAtBlock[i - 1]),
        );
      }
    });

    test('refuses a level number outside it', () {
      expect(() => LevelPlan.forLevel(0), throwsRangeError);
      expect(() => LevelPlan.forLevel(101), throwsRangeError);
    });
  });

  group('every level', () {
    late final List<Level> levels = <Level>[
      for (final int n in everyLevel) generateLevel(n),
    ];

    test('fills the board as full as its grade allows', () {
      // Not an absolute figure — what a board can hold depends on its grade —
      // but a floor under every level, because the campaign looking full is
      // most of what makes it look like a game rather than a diagram.
      for (final Level level in levels) {
        int covered = 0;
        for (final Arrow arrow in level.arrows) {
          covered += arrow.dots.length;
        }
        // The floor falls with the board, because the ceiling does — an arrow
        // needs a clear straight line to the edge, and that line is as long as
        // the board is wide. See [LevelPlan.arrowsAtBlock].
        expect(
          100 * covered / (level.size * level.size),
          greaterThan(level.size <= 22 ? 35 : 28),
          reason: 'level ${level.number} is threadbare',
        );
      }
    });

    test('is generated to the size and arrow count its plan asked for', () {
      for (final Level level in levels) {
        expect(level.size, level.plan.size, reason: 'level ${level.number}');
        expect(
          level.arrows.length,
          level.plan.arrows,
          reason: 'level ${level.number} came up short',
        );
      }
    });

    test('sits on the board without overlapping itself', () {
      for (final Level level in levels) {
        final Set<Dot> seen = <Dot>{};
        for (final Arrow arrow in level.arrows) {
          for (final Dot dot in arrow.dots) {
            expect(
              dot.x >= 0 &&
                  dot.y >= 0 &&
                  dot.x < level.size &&
                  dot.y < level.size,
              isTrue,
              reason: 'level ${level.number}: $dot is off the board',
            );
            expect(
              seen.add(dot),
              isTrue,
              reason: 'level ${level.number}: two arrows both cover $dot',
            );
          }
        }
      }
    });

    test('solves in the order the generator promises', () {
      for (final Level level in levels) {
        final Board board = level.board();
        for (final Arrow arrow in level.solution) {
          expect(
            board.isFree(arrow),
            isTrue,
            reason:
                'level ${level.number}: $arrow was not free when its turn '
                'came, so the reverse of the placement order is not a solve',
          );
          board.remove(arrow);
        }
        expect(board.isEmpty, isTrue);
      }
    });

    test('offers exactly its grade many moves, the whole way down', () {
      // The difficulty, as a number, checked at every position on the intended
      // line: four arrows free on an easy level and one on a hard one, until
      // there are fewer arrows left than that.
      for (final Level level in levels) {
        final Board board = level.board();
        for (int left = level.arrows.length; left > 0; left--) {
          final int wanted = left < level.branching ? left : level.branching;
          expect(
            board.freeArrows.length,
            wanted,
            reason: 'level ${level.number} with $left arrows left',
          );
          board.remove(level.solution[level.arrows.length - left]);
        }
      }
    });

    test('cannot be dead-ended, however the player plays it', () {
      // `Level`'s comment argues this from the construction: removing an arrow
      // can only free others, so an arrow that is free stays free, so the
      // latest-placed arrow still on any reachable position is free on it.
      // Here it is played rather than argued — a hundred boards cleared by
      // picking at random from whatever is free, which is the one thing a
      // player can do that the intended order does not cover.
      final Rng rng = Rng(20260814);
      for (final Level level in levels) {
        final Board board = level.board();
        int peak = 0;
        while (!board.isEmpty) {
          final List<Arrow> free = board.freeArrows;
          expect(
            free,
            isNotEmpty,
            reason: 'level ${level.number} stalled with ${board.length} left',
          );
          if (free.length > peak) {
            peak = free.length;
          }
          board.remove(rng.pick(free));
        }
        // And the grade holds off the intended line too. Playing out of order
        // can only ever free arrows early, so this is the claim worth pinning:
        // it does not open the level up.
        expect(
          peak,
          lessThanOrEqualTo(level.branching),
          reason: 'level ${level.number} offered $peak moves at once',
        );
      }
    });

    test('is the same level every time it is generated', () {
      // The levels are computed on the way into the screen rather than stored,
      // so "level 63" has to mean one tangle. `Rng` is written out in the
      // repository for this reason — `dart:math` does not promise its sequence
      // across SDKs.
      for (final int n in <int>[1, 7, 26, 63, 99, 100]) {
        final Level once = generateLevel(n);
        final Level twice = generateLevel(n);
        expect(once.arrows.length, twice.arrows.length);
        for (int i = 0; i < once.arrows.length; i++) {
          expect(once.arrows[i].dots, twice.arrows[i].dots, reason: 'level $n');
        }
      }
    });
  });
}
