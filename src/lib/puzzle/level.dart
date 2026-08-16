import 'arrow.dart';
import 'board.dart';

/// How hard a level is meant to be, which in this game is one number: how many
/// arrows can leave at any moment.
///
/// It is a strikingly direct handle. At four the player nearly always has an
/// obvious move and the level is a sequence of small reliefs; at one there is
/// never a choice at all, so every tap is a claim about the whole tangle and a
/// wrong one costs a life. Nothing else about a level — its size, its arrow
/// count, how bent the arrows are — moves the difficulty anything like as far.
enum Grade {
  easy(4),
  moderate(3),
  difficult(2),
  hard(1);

  const Grade(this.branching);

  /// The most arrows that may be free at once, anywhere in the solve. The
  /// generator holds the board to exactly this many for as long as there are
  /// that many arrows left — see `generate.dart`.
  final int branching;
}

/// The shape of one level, before any arrows exist.
///
/// All three numbers are functions of the level number and nothing else, which
/// is what lets the whole campaign be described in the three expressions below
/// rather than a table of a hundred rows.
class LevelPlan {
  const LevelPlan({
    required this.number,
    required this.size,
    required this.arrows,
    required this.grade,
  });

  /// The campaign. Ten easy, fifteen moderate, twenty difficult, and then
  /// fifty-five hard ones.
  static const int levelCount = 100;

  /// Dots across the first board, and how much wider each block of ten gets:
  /// two more dots in every direction, so four more across.
  static const int firstSize = 14;
  static const int sizeStep = 4;

  /// And where it stops. The board grows for the first fifty levels and then
  /// holds, because past this a phone cannot show one at a size a finger can
  /// aim at: 30 dots across a portrait screen is about eleven pixels a dot,
  /// and the arrows are a third of that.
  ///
  /// The second half of the campaign gets harder the two ways that do not cost
  /// legibility — one free arrow instead of two, and more arrows woven into the
  /// same square — rather than by getting bigger and further away.
  static const int lastSize = 30;

  /// Arrows at the start of each block of ten levels, and once more for the
  /// end — eleven marks, interpolated between, so the count climbs level by
  /// level rather than in steps of ten.
  ///
  /// Measurements, not choices. Each was found by asking the generator for far
  /// more than it could place and taking the *worst* of the ten levels in the
  /// block, then leaving a couple of arrows of margin for the fact that some
  /// tangles are luckier than others. Asking for the margin back does not
  /// produce more arrows — it produces levels that come up short and spend a
  /// second each failing to.
  ///
  /// **The tail is flat, and that is the board rather than the generator.** The
  /// grid stops growing at level 50 (see [lastSize]) and the grade is already
  /// as hard as it goes by level 46, so from there the only thing left to
  /// increase is how many arrows are woven into the same square — and a 30 × 30
  /// board with one free arrow holds about forty before there is nowhere left
  /// to put one that can still get out. The back half of the campaign is
  /// therefore fifty different tangles of much the same difficulty rather than
  /// a climb. Raising it means changing one of the three things that set it:
  /// the board size, the branching, or the three lives.
  static const List<int> arrowsAtBlock = <int>[
    22, // 14 × 14
    24,
    31, // 18 × 18
    40, // 22 × 22
    44, // 26 × 26
    48, // 30 × 30, and 30 × 30 from here on
    49,
    49,
    49,
    49,
    49, // level 100
  ];

  factory LevelPlan.forLevel(int number) {
    if (number < 1 || number > levelCount) {
      throw RangeError.range(number, 1, levelCount, 'number');
    }
    return LevelPlan(
      number: number,
      size: sizeFor(number),
      arrows: arrowsFor(number),
      grade: gradeOf(number),
    );
  }

  /// How many dots across level [number] is.
  static int sizeFor(int number) {
    final int grown = firstSize + sizeStep * ((number - 1) ~/ 10);
    return grown < lastSize ? grown : lastSize;
  }

  /// How many arrows level [number] asks for: along the line between its
  /// block's mark and the next one. Non-decreasing, because [arrowsAtBlock] is.
  static int arrowsFor(int number) {
    final int block = (number - 1) ~/ 10;
    final int into = (number - 1) % 10;
    final int from = arrowsAtBlock[block];
    return from + (arrowsAtBlock[block + 1] - from) * into ~/ 10;
  }

  static Grade gradeOf(int number) {
    if (number <= 10) {
      return Grade.easy;
    }
    if (number <= 25) {
      return Grade.moderate;
    }
    if (number <= 45) {
      return Grade.difficult;
    }
    return Grade.hard;
  }

  final int number;
  final int size;
  final int arrows;
  final Grade grade;

  int get branching => grade.branching;
}

/// A level: the plan, and the arrows that satisfy it.
///
/// **The arrows are in the order they were placed, and clearing them in the
/// reverse of that order always solves the level.** That is not a solver's
/// finding, it is how the generator built them — every arrow was placed with a
/// clear run to the edge past everything already down, so undoing the placement
/// is a legal solve by construction.
///
/// Two consequences worth stating where they cannot be missed:
///
/// * **The order is a spoiler.** Anything the screen derives from an arrow's
///   index — a colour, a draw order, a z-order — hands the player the answer.
///   `render/board_painter.dart` colours arrows by where their head is instead,
///   and that is why.
/// * **The level cannot be dead-ended.** Removing an arrow can only ever free
///   others, never block them, so an arrow that is free stays free. Take any
///   position the player has reached and let A be the placed-latest arrow still
///   on it: everything still on the board was placed no later than A, so the
///   position is a subset of the board A was placed onto, where A was free — so
///   A is free now. There is always a move. A life is only ever lost to a wrong
///   tap, never to a position, and the game needs no undo to be fair.
class Level {
  Level({required this.plan, required List<Arrow> arrows})
    : arrows = List<Arrow>.unmodifiable(arrows);

  final LevelPlan plan;

  /// Placement order. See the class comment before using the index for
  /// anything the player can see.
  final List<Arrow> arrows;

  int get number => plan.number;
  int get size => plan.size;
  Grade get grade => plan.grade;
  int get branching => plan.branching;

  /// A fresh board with every arrow on it.
  Board board() => Board(size, arrows);

  /// The order the generator guarantees: last placed, first out.
  List<Arrow> get solution => arrows.reversed.toList();
}
