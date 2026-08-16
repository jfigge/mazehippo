import 'arrow.dart';

/// What happened when an arrow was told to go.
class Slide {
  const Slide.escapes(this.steps) : blocker = null;
  const Slide.blocked(this.steps, Arrow this.blocker);

  /// Moves made. For an escape it is the whole path — the body's own length
  /// plus the lane it threads out along — so that the tail clears the board and
  /// not just the head. For a block it is how far the head gets before the dot
  /// in front of it is [blocker]'s, which is zero when the two are already
  /// touching.
  final int steps;

  /// What stopped it, or null if nothing did. The screen turns this one red
  /// alongside the arrow that failed, because "why not" is the whole question
  /// the player is asking at that moment.
  final Arrow? blocker;

  bool get escapes => blocker == null;
}

/// A square lattice of `size × size` dots, numbered 0..size-1 on both axes, and
/// the arrows currently on it.
///
/// The board is mutable, because a level is a board arrows leave. Both [add]
/// and [remove] drop the occupancy index, which is the only cached thing here.
class Board {
  Board(this.size, [Iterable<Arrow>? arrows]) : _arrows = <Arrow>[...?arrows];

  /// Dots across, and dots down. A dot is on the board when both its
  /// coordinates are in 0..size-1.
  final int size;

  final List<Arrow> _arrows;

  /// Dot to whichever arrow covers it. Arrows never overlap, so this is a
  /// function rather than a relation — see [add], which is where that is
  /// enforced.
  Map<Dot, Arrow>? _occupancy;

  Iterable<Arrow> get arrows => _arrows;
  int get length => _arrows.length;
  bool get isEmpty => _arrows.isEmpty;
  Arrow operator [](int index) => _arrows[index];

  Map<Dot, Arrow> get _occupied {
    final Map<Dot, Arrow> built = _occupancy ??= <Dot, Arrow>{
      for (final Arrow arrow in _arrows)
        for (final Dot dot in arrow.dots) dot: arrow,
    };
    return built;
  }

  bool contains(Dot dot) =>
      dot.x >= 0 && dot.y >= 0 && dot.x < size && dot.y < size;

  /// Whether [arrow] would sit legally on the board as it stands: every dot on
  /// the board, and no dot already taken.
  bool fits(Arrow arrow) {
    final Map<Dot, Arrow> occupied = _occupied;
    for (final Dot dot in arrow.dots) {
      if (!contains(dot) || occupied.containsKey(dot)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [dot] is on the board and nothing is standing on it.
  bool isVacant(Dot dot) => contains(dot) && !_occupied.containsKey(dot);

  void add(Arrow arrow) {
    assert(fits(arrow), 'arrows may not overlap or hang off the board');
    _arrows.add(arrow);
    _occupancy = null;
  }

  void remove(Arrow arrow) {
    _arrows.remove(arrow);
    _occupancy = null;
  }

  /// The dots [arrow] needs empty: straight ahead of its point, out to the edge
  /// of the board.
  ///
  /// This is the whole of what stands between an arrow and the exit, and it is
  /// worth being clear about why so little of the arrow matters. The body
  /// follows the head — see [Arrow] — so every dot the body will ever occupy is
  /// a dot the head has already passed through. Checking the head's line checks
  /// the body's too, and a bent arrow is under no more threat than a straight
  /// one of the same reach.
  ///
  /// Geometry, not state: it does not change as the board fills, which is what
  /// makes it something the generator can aim at rather than keep guessing
  /// against.
  List<Dot> lane(Arrow arrow) {
    final List<Dot> ahead = <Dot>[];
    Dot at = arrow.head.step(arrow.heading);
    while (contains(at)) {
      ahead.add(at);
      at = at.step(arrow.heading);
    }
    return ahead;
  }

  /// Moves before no part of [arrow] is on the board, ignoring every other
  /// arrow: its own length, plus the lane it has to thread out along. The
  /// length is there because the *tail* is what leaves last, and it has the
  /// whole body's worth of path to walk before it even reaches the lane.
  int exitSteps(Arrow arrow) => arrow.dots.length + lane(arrow).length;

  /// Where [arrow] gets to.
  ///
  /// One walk down the lane. There is no sweeping and no stepping of the whole
  /// shape, because there is nothing else to test: the arrow occupies the lane
  /// dots one at a time in order, so the first one that belongs to somebody
  /// else is exactly where it stops.
  Slide slide(Arrow arrow) {
    final Map<Dot, Arrow> occupied = _occupied;
    final List<Dot> ahead = lane(arrow);
    for (int i = 0; i < ahead.length; i++) {
      final Arrow? hit = occupied[ahead[i]];
      if (hit != null && !identical(hit, arrow)) {
        return Slide.blocked(i, hit);
      }
    }
    return Slide.escapes(arrow.dots.length + ahead.length);
  }

  bool isFree(Arrow arrow) => slide(arrow).escapes;

  /// Every arrow that could leave right now. The count of these is the whole of
  /// what makes a level easy or hard — see [Grade.branching].
  List<Arrow> get freeArrows => <Arrow>[
    for (final Arrow arrow in _arrows)
      if (isFree(arrow)) arrow,
  ];
}
