import 'arrow.dart';
import 'board.dart';
import 'level.dart';

/// xorshift32, written out rather than taken from `dart:math`.
///
/// `Random(seed)` is deterministic for a given seed but its algorithm is not
/// part of Dart's contract, so a level generated on one SDK is not promised to
/// be the level generated on the next. These twelve lines are that promise:
/// level 63 is the same tangle on every machine, on every Dart, forever, which
/// is what lets the levels be *computed* on the way into the screen rather than
/// generated once and checked into the repository as data.
class Rng {
  Rng(int seed) : _state = (seed == 0 ? 0x9e3779b9 : seed) & 0xffffffff;

  int _state;

  int _next() {
    int x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x;
    return x;
  }

  /// A number in 0..bound-1.
  int nextInt(int bound) => _next() % bound;

  /// One of [items], uniformly.
  T pick<T>(List<T> items) => items[nextInt(items.length)];
}

/// How the generator is allowed to draw an arrow.
class _Shape {
  const _Shape(this.maxLegs, this.maxRun, this.minLane);

  /// Legs before the arrow has to stop bending.
  final int maxLegs;

  /// The longest single straight run, in dots.
  final int maxRun;

  /// Dots of lane an arrow must leave in front of its point.
  ///
  /// This is the condition the whole generator turned out to hinge on, and it
  /// is not the one you would guess.
  ///
  /// An arrow whose head is *on* the edge has no lane at all — nothing in front
  /// of it, out to a boundary it is already standing on. It can always leave,
  /// which sounds harmless and is fatal: the next arrow has to be placed on
  /// that lane in order to block it, and there is nowhere to put it. Every
  /// stall the generator hit was this, and it hit it early.
  ///
  /// So an arrow must leave a lane worth having, because that lane is not just
  /// its own way out — it is the entire search space for the arrow that comes
  /// after it.
  final int minLane;
}

/// Build level [number]. Deterministic: same number, same level, always.
Level generateLevel(int number) {
  final LevelPlan plan = LevelPlan.forLevel(number);
  final _Shape shape = _Shape(4, 4, 3);

  // Several goes at it, each with its own stream, and the fullest board wins.
  // A run can paint itself into a corner — every arrow it places is one more
  // wall the next one has to find a way past — and a fresh stream is the
  // cheapest way out of one that a few undos could not fix.
  List<Arrow>? best;
  for (int attempt = 0; attempt < _attempts; attempt++) {
    final List<Arrow> placed = _weave(
      plan,
      shape,
      Rng(number * 0x9e3779b1 + attempt * 0x85ebca77),
    );
    if (placed.length > (best?.length ?? 0)) {
      best = placed;
    }
    if (best!.length >= plan.arrows) {
      break;
    }
  }
  return Level(plan: plan, arrows: best!);
}

/// Tries at a whole board, and candidate arrows tried per placement. Both are
/// generous: generating a level is a few milliseconds of integer work that
/// happens once per level, against a player who is about to spend minutes on
/// the result.
const int _attempts = 120;
const int _candidates = 80;

/// Placements a single run may take back before giving up and letting the next
/// attempt start over. Undoing is worth having because the arrows that are hard
/// to place are the *last* ones, so a restart pays again for the whole easy
/// prefix to reach the same wall; taking back the arrow that built the wall
/// costs one placement.
const int _undos = 30;

/// Workable candidates to look at before taking the best of them. See
/// [_hugging] for what "best" means and why it matters so much more than it
/// sounds like it should.
const int _shortlist = 80;

/// Weave a board, backwards.
///
/// The whole generator is one idea. **Place arrows that can leave, and the
/// reverse of the placement order is a solve.** When an arrow goes down its run
/// to the edge is clear of everything already placed; in the solve that arrow
/// is lifted while exactly those same arrows are the ones still on the board,
/// so the run is clear then too. No solver is involved, and none is needed —
/// the level is generated along its own solution.
///
/// The difficulty is the second half of the idea. [Grade.branching] is how many
/// arrows may be free at once, and the count is held there by what each
/// placement is *required* to do:
///
/// * Adding an arrow can never free another one — it is one more obstacle, not
///   one fewer — so the free count only moves by the arrow being added and by
///   whichever free arrows that arrow blocks.
/// * So a placement that blocks nothing raises the count by one, and a
///   placement that blocks exactly one free arrow leaves it alone.
///
/// The first K placements block nothing and take the count from 0 to K. Every
/// placement after that blocks exactly one free arrow and holds it at K. That
/// is the invariant, it is maintained by construction rather than searched for,
/// and `test/level_test.dart` replays every level to check it held.
List<Arrow> _weave(LevelPlan plan, _Shape shape, Rng rng) {
  final Board board = Board(plan.size);
  final int k = plan.branching;

  // The free arrows, kept alongside the board rather than recomputed. The
  // invariant is what makes that safe: this list is exactly `board.freeArrows`
  // after every placement, which is asserted below and re-derived from scratch
  // by the test suite.
  final List<Arrow> free = <Arrow>[];

  // What each placement blocked, in placement order, so that taking one back is
  // exact rather than a guess. A null entry is one of the first K arrows, which
  // blocked nothing.
  final List<Arrow?> blocked = <Arrow?>[];
  int undos = _undos;

  while (board.length < plan.arrows) {
    // Which free arrow this placement has to block. Null while the board is
    // still filling up to K, when a placement must block nothing at all.
    final Arrow? target = free.length < k ? null : rng.pick(free);
    final Arrow? placed = _placeOne(board, shape, rng, free, target);

    if (placed == null) {
      if (undos == 0 || board.isEmpty) {
        break;
      }
      undos--;
      final Arrow last = board[board.length - 1];
      final Arrow? freed = blocked.removeLast();
      board.remove(last);
      free.remove(last);
      if (freed != null) {
        free.add(freed);
      }
      continue;
    }

    board.add(placed);
    // The claim `_drawBackwards` makes, checked. Nothing else asks whether a
    // placed arrow can actually get out any more.
    assert(board.isFree(placed), 'a placed arrow must be able to leave');
    if (target != null) {
      free.remove(target);
    }
    free.add(placed);
    blocked.add(target);
    assert(
      free.length == (board.length < k ? board.length : k),
      'the free count drifted from the level grade',
    );
  }

  return board.arrows.toList();
}

/// Find one arrow that may be placed on [board] now.
///
/// It has to satisfy four things at once, and they pull against each other,
/// which is why this is a search and not a construction:
///
/// * it fits — on the board, overlapping nothing;
/// * it is free — the lane in front of its point runs clear to the edge;
/// * it blocks [target] and *only* [target] out of the arrows in [free];
/// * and it leaves a lane of its own worth having. See [_Shape.minLane]; this
///   is the one that is not obvious and the one that mattered most.
///
/// The trick that makes the hit rate liveable is that the third condition is
/// aimed at rather than tested for. [Board.lane] gives the target's lane as a
/// list of dots, so the candidate is built to pass through one picked out of it
/// — after which it blocks the target by construction, and the search is only
/// really looking for the other three.
Arrow? _placeOne(
  Board board,
  _Shape shape,
  Rng rng,
  List<Arrow> free,
  Arrow? target,
) {
  final List<Dot> corridor = target == null
      ? const <Dot>[]
      : board.lane(target).where(board.isVacant).toList();
  if (target != null && corridor.isEmpty) {
    return null;
  }

  // The lanes of every free arrow this candidate must stay out of. Built once
  // per placement rather than per candidate: they do not depend on the
  // candidate, and this is the innermost loop of the whole generator.
  final List<Set<Dot>> keepClear = <Set<Dot>>[
    for (final Arrow arrow in free)
      if (!identical(arrow, target)) board.lane(arrow).toSet(),
  ];

  Arrow? best;
  int bestScore = -1;
  int shortlisted = 0;

  for (int attempt = 0; attempt < _candidates; attempt++) {
    final Dot anchor = target == null
        ? Dot(rng.nextInt(board.size), rng.nextInt(board.size))
        : _nearestOfThree(rng, corridor, target.head);
    // The heading is left exactly as [_randomPath] drew it, and that is a
    // finding rather than an omission. Aiming each candidate at whichever edge
    // it was nearest — the obvious way to give it a short, and so probably
    // clear, lane — was tried under both movement rules and lost both times.
    // The reason is the chain: the arrow being placed is the arrow the *next*
    // placement has to block, and the only place a blocker may be anchored is
    // its lane. An arrow that was easy to place leaves almost nowhere to place
    // the next one.
    final List<Dot> path = _randomPath(rng, shape);
    final Arrow candidate = Arrow.traced(
      path,
    ).shifted(anchor - path[rng.nextInt(path.length)]);

    if (!board.fits(candidate) || _touchesAny(candidate, keepClear)) {
      continue;
    }
    // Asked of a candidate that is *not* on the board, on purpose. The answer
    // is the same either way — an arrow threading along its own path can never
    // run into itself — and putting it down to ask would drop the occupancy
    // index and rebuild it, twice, on every candidate.
    if (!board.slide(candidate).escapes) {
      continue;
    }
    if (board.lane(candidate).length < shape.minLane) {
      continue;
    }

    // Not the first one that works — the tidiest of the next few.
    //
    // What runs a board out of room is not how much of it is covered, it is how
    // the *empty* part is shaped. An arrow needs a straight empty line from its
    // point to the edge, so a board whose gaps are one big open region has
    // plenty and a board whose gaps are scattered crumbs has almost none, at
    // exactly the same coverage. Every arrow dropped in open space cuts the
    // rows and columns it lies across in half; one laid against an arrow
    // already there costs almost nothing, because those lines were spent
    // already.
    //
    // So candidates are scored by how much of them is touching something, and
    // the board packs rather than scatters.
    final int score = _hugging(board, candidate);
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
    if (++shortlisted >= _shortlist) {
      break;
    }
  }
  return best;
}

/// How many of [arrow]'s dots have something already standing beside them.
int _hugging(Board board, Arrow arrow) {
  int touching = 0;
  for (final Dot dot in arrow.dots) {
    for (final Heading heading in Heading.values) {
      final Dot beside = dot.step(heading);
      if (board.contains(beside) && !board.isVacant(beside)) {
        touching++;
      }
    }
  }
  return touching;
}

/// An arrow shape, drawn from nothing: one to [_Shape.maxLegs] straight runs,
/// each a quarter turn from the last, head at the end.
///
/// Returned traced and relative to its own tail. A path that crosses itself, or
/// that ends up pointing back along its own body, is thrown away rather than
/// repaired: repairing one would bias which shapes come out, and both faults
/// are cheap to redraw. With four legs available a spiral can manage the
/// second, which is why the check is here and not only in [Arrow]'s assert.
List<Dot> _randomPath(Rng rng, _Shape shape) {
  while (true) {
    final int legs = 1 + rng.nextInt(shape.maxLegs);
    final List<Dot> path = <Dot>[const Dot(0, 0)];
    Heading heading = Heading.values[rng.nextInt(4)];
    for (int leg = 0; leg < legs; leg++) {
      if (leg > 0) {
        heading = rng.nextInt(2) == 0
            ? heading.clockwise
            : heading.anticlockwise;
      }
      final int run = 1 + rng.nextInt(shape.maxRun);
      for (int s = 0; s < run; s++) {
        path.add(path.last.step(heading));
      }
    }
    if (path.toSet().length == path.length && !Arrow.pointsAtItself(path)) {
      return path;
    }
  }
}

bool _touchesAny(Arrow arrow, List<Set<Dot>> corridors) {
  for (final Set<Dot> corridor in corridors) {
    for (final Dot dot in arrow.dots) {
      if (corridor.contains(dot)) {
        return true;
      }
    }
  }
  return false;
}

/// A dot from [corridor], biased towards the near end of it.
///
/// The lane runs from the target's point to the edge of the board, so a dot
/// picked uniformly out of it sits on average halfway to that edge — and since
/// the blocker placed there becomes the next target, the tangle marches
/// outwards and ends up a ring around an empty middle. Best of three by
/// distance pulls it back in without pinning every blocker directly in front of
/// what it blocks, which would be its own kind of pattern.
Dot _nearestOfThree(Rng rng, List<Dot> corridor, Dot from) {
  Dot best = rng.pick(corridor);
  int bestReach = _reach(best, from);
  for (int i = 0; i < 2; i++) {
    final Dot other = rng.pick(corridor);
    final int reach = _reach(other, from);
    if (reach < bestReach) {
      best = other;
      bestReach = reach;
    }
  }
  return best;
}

int _reach(Dot a, Dot b) => (a.x - b.x).abs() + (a.y - b.y).abs();
