/// A dot on the lattice the whole game is played on.
///
/// The board the player sees is dots rather than cells on purpose. An arrow is
/// a line *through* dots, not a run of filled squares, and every question the
/// game asks — does this arrow touch that one, can it get out — is a question
/// about which dots are covered.
///
/// That is worth one paragraph here because [Board] leans on it completely.
/// Every segment of every arrow is axis-aligned and exactly one unit long, and
/// two axis-aligned unit-lattice polylines cannot cross anywhere *except* at a
/// dot: a horizontal run at row y and a vertical run at column x meet at
/// (x, y), which is a dot both of them cover. So there is no case where two
/// arrows pass through each other between dots, and a set intersection is not
/// an approximation of the overlap test. It is the overlap test.
class Dot {
  const Dot(this.x, this.y);

  final int x;
  final int y;

  Dot step(Heading heading, [int times = 1]) =>
      Dot(x + heading.dx * times, y + heading.dy * times);

  Dot operator +(Dot other) => Dot(x + other.x, y + other.y);
  Dot operator -(Dot other) => Dot(x - other.x, y - other.y);

  @override
  bool operator ==(Object other) =>
      other is Dot && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// The four ways an arrow can point.
///
/// y increases *downwards*, as it does on the screen the board is drawn to.
/// Carrying the screen's sign convention all the way down into the puzzle layer
/// costs nothing — nothing here is doing geometry that cares which way up the
/// world is — and it removes the one flip that would otherwise sit between the
/// model and the painter, waiting to be got wrong once.
enum Heading {
  right(1, 0),
  down(0, 1),
  left(-1, 0),
  up(0, -1);

  const Heading(this.dx, this.dy);

  final int dx;
  final int dy;

  /// The heading a quarter turn clockwise, given y down.
  Heading get clockwise => Heading.values[(index + 1) % 4];

  /// And a quarter turn the other way.
  Heading get anticlockwise => Heading.values[(index + 3) % 4];

  Heading get opposite => Heading.values[(index + 2) % 4];

  /// Which way (x, y) points, or null if it is not one unit along an axis.
  static Heading? of(Dot delta) {
    for (final Heading heading in Heading.values) {
      if (delta.x == heading.dx && delta.y == heading.dy) {
        return heading;
      }
    }
    return null;
  }
}

/// One arrow: a run of dots from its tail to its head, and the direction it
/// leaves in.
///
/// The dots are stored *traced* — every lattice point along the path, not just
/// the corners — and that is the single source of truth for the shape. The
/// corners are derived back out of them for drawing, rather than stored
/// alongside, because two representations of one shape is two chances to
/// disagree and the collision test only ever wants the traced form.
///
/// **An arrow moves like a snake.** The head takes one step along [heading] and
/// every other dot moves up onto the one in front of it, so the body threads
/// itself along the line the head has already travelled. It does not translate
/// rigidly and it does not drag its bends sideways through the board.
///
/// That is the thing to have straight before reading [Board], because it is
/// what makes the game readable. Whether an arrow can leave depends on one
/// straight line of dots — the ones in front of its point, out to the edge —
/// and on nothing else. Its own bends cost it nothing, because every dot the
/// body passes through is a dot the head has already been through and found
/// empty. Sighting down that line is the whole of what the player is doing, and
/// [pathDot] is that line written down.
class Arrow {
  Arrow._(this.dots)
    : assert(dots.length >= 2, 'an arrow needs somewhere to point'),
      assert(
        dots.toSet().length == dots.length,
        'an arrow that crosses itself is not a shape this game can draw',
      ),
      assert(
        !pointsAtItself(dots),
        'an arrow may not point along its own body: the head would arrive '
        'before the tail had left',
      );

  /// Whether any part of [dots] lies straight ahead of the point.
  ///
  /// Such an arrow could not move: the head would step onto a dot its own tail
  /// had not vacated yet, which in a game that moves like a snake is the one
  /// thing a snake must not do. No shape the generator draws can manage it —
  /// it takes at least three bends to wrap a body round in front of its own
  /// head. `generate.dart` draws shapes with enough bends to manage it, so it
  /// checks with this before building an [Arrow] out of one — and the assert in
  /// the constructor is what catches a hand-written arrow that does the same.
  static bool pointsAtItself(List<Dot> dots) {
    final Dot head = dots.last;
    final Heading heading = Heading.of(head - dots[dots.length - 2])!;
    for (final Dot dot in dots) {
      final Dot delta = dot - head;
      final bool ahead = heading.dx != 0
          ? delta.y == 0 && delta.x * heading.dx > 0
          : delta.x == 0 && delta.y * heading.dy > 0;
      if (ahead) {
        return true;
      }
    }
    return false;
  }

  /// Trace an arrow through the given corners. The last corner is the head, and
  /// the direction of the final leg is the direction it will try to leave in.
  ///
  /// Consecutive corners must be axis-aligned and distinct; anything else is a
  /// caller bug rather than a runtime condition, hence the throw.
  factory Arrow.fromCorners(List<Dot> corners) {
    if (corners.length < 2) {
      throw ArgumentError.value(corners, 'corners', 'need at least two');
    }
    final List<Dot> traced = <Dot>[corners.first];
    for (int i = 1; i < corners.length; i++) {
      final Dot from = corners[i - 1];
      final Dot to = corners[i];
      final int dx = to.x - from.x;
      final int dy = to.y - from.y;
      if ((dx != 0) == (dy != 0)) {
        throw ArgumentError.value(
          corners,
          'corners',
          'leg $i is diagonal or empty: $from to $to',
        );
      }
      final Heading leg = Heading.of(Dot(dx.sign, dy.sign))!;
      final int run = dx.abs() + dy.abs();
      for (int s = 1; s <= run; s++) {
        traced.add(from.step(leg, s));
      }
    }
    return Arrow._(List<Dot>.unmodifiable(traced));
  }

  /// An arrow from a path that is already traced: consecutive dots exactly one
  /// unit apart, none repeated. `generate.dart` draws its shapes a step at a
  /// time, so this spares it reducing a path to corners for [Arrow.fromCorners]
  /// to expand straight back out again.
  factory Arrow.traced(List<Dot> dots) {
    if (dots.length < 2) {
      throw ArgumentError.value(dots, 'dots', 'need at least two');
    }
    for (int i = 1; i < dots.length; i++) {
      if (Heading.of(dots[i] - dots[i - 1]) == null) {
        throw ArgumentError.value(
          dots,
          'dots',
          'step $i is not one unit along an axis',
        );
      }
    }
    return Arrow._(List<Dot>.unmodifiable(dots));
  }

  /// Every lattice point the arrow covers, tail first, head last.
  final List<Dot> dots;

  Dot get tail => dots.first;
  Dot get head => dots.last;

  /// The way out. The direction of the last leg, which is where the head is
  /// drawn pointing.
  Heading get heading => Heading.of(dots.last - dots[dots.length - 2])!;

  int get minX => dots.fold(dots.first.x, (int a, Dot d) => a < d.x ? a : d.x);
  int get maxX => dots.fold(dots.first.x, (int a, Dot d) => a > d.x ? a : d.x);
  int get minY => dots.fold(dots.first.y, (int a, Dot d) => a < d.y ? a : d.y);
  int get maxY => dots.fold(dots.first.y, (int a, Dot d) => a > d.y ? a : d.y);

  /// The same arrow moved bodily by [by]. The generator's way of placing a
  /// shape it has just invented — not a move any arrow makes in play.
  Arrow shifted(Dot by) =>
      Arrow._(List<Dot>.unmodifiable(<Dot>[for (final Dot d in dots) d + by]));

  /// The whole path the arrow threads itself along, indexed from the tail.
  ///
  /// Up to the head it is the arrow's own body; past the head it is the
  /// straight line out. That single sequence is what makes the movement simple
  /// to state: after [steps] moves the arrow covers `pathDot(steps)` through
  /// `pathDot(steps + dots.length - 1)`, so the tail walks the same dots the
  /// head did, [steps] behind it.
  ///
  /// Defined for any [step] at or above zero, including ones off the board —
  /// leaving is the arrow walking off the end of this path.
  Dot pathDot(int step) => step < dots.length
      ? dots[step]
      : head.step(heading, step - dots.length + 1);

  /// The arrow after [steps] moves.
  Arrow after(int steps) => Arrow._(
    List<Dot>.unmodifiable(<Dot>[
      for (int i = 0; i < dots.length; i++) pathDot(steps + i),
    ]),
  );

  /// The corners, derived: the tail, every dot where the direction changes, and
  /// the head. Only [toString] uses it now that the painter walks the path
  /// dot by dot, but it is the honest description of the shape.
  List<Dot> get corners {
    final List<Dot> found = <Dot>[dots.first];
    for (int i = 1; i < dots.length - 1; i++) {
      final Dot before = dots[i] - dots[i - 1];
      final Dot after = dots[i + 1] - dots[i];
      if (before.x != after.x || before.y != after.y) {
        found.add(dots[i]);
      }
    }
    found.add(dots.last);
    return found;
  }

  @override
  String toString() => 'Arrow(${corners.join(' → ')} ${heading.name})';
}
