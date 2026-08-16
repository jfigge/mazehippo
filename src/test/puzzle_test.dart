// The lattice, and what it promises.
//
// These are the small cases: an arrow that gets out, an arrow that does not,
// and the crossing that `Dot`'s comment claims cannot be missed. The hundred
// levels are in level_test.dart, which stands on all of this.

import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/puzzle/puzzle.dart';

void main() {
  group('Arrow', () {
    test('traces every dot between its corners', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(2, 2),
        const Dot(5, 2),
        const Dot(5, 4),
      ]);
      expect(arrow.dots, <Dot>[
        const Dot(2, 2),
        const Dot(3, 2),
        const Dot(4, 2),
        const Dot(5, 2),
        const Dot(5, 3),
        const Dot(5, 4),
      ]);
      expect(arrow.head, const Dot(5, 4));
      expect(arrow.tail, const Dot(2, 2));
      expect(arrow.heading, Heading.down);
    });

    test('gives its corners back', () {
      final List<Dot> corners = <Dot>[
        const Dot(0, 0),
        const Dot(3, 0),
        const Dot(3, 3),
        const Dot(1, 3),
      ];
      expect(Arrow.fromCorners(corners).corners, corners);
    });

    test('refuses a diagonal leg', () {
      expect(
        () => Arrow.fromCorners(<Dot>[const Dot(0, 0), const Dot(2, 2)]),
        throwsArgumentError,
      );
    });

    test('threads along its own path, tail following head', () {
      // The bend is the case worth stating: after two moves the tail is
      // standing where the body's third dot was, not two dots to the right of
      // where it started.
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(1, 1),
        const Dot(1, 3),
        const Dot(4, 3),
      ]);
      expect(arrow.heading, Heading.right);
      expect(arrow.after(2).dots, <Dot>[
        const Dot(1, 3),
        const Dot(2, 3),
        const Dot(3, 3),
        const Dot(4, 3),
        const Dot(5, 3),
        const Dot(6, 3),
      ]);
      // And the path itself: body first, then straight on from the head.
      expect(arrow.pathDot(0), const Dot(1, 1));
      expect(arrow.pathDot(5), const Dot(4, 3));
      expect(arrow.pathDot(6), const Dot(5, 3));
    });

    test('shifts bodily, for the generator to place it', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(1, 1),
        const Dot(1, 4),
      ]);
      expect(arrow.shifted(const Dot(5, 0)).head, const Dot(6, 4));
    });
  });

  group('Board', () {
    test('an arrow with nothing in its way leaves', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(3, 5),
        const Dot(6, 5),
      ]);
      final Board board = Board(10, <Arrow>[arrow]);
      expect(board.slide(arrow).escapes, isTrue);
      // Four dots of body plus three of lane — x = 7, 8, 9 — is seven moves
      // before the tail is off a board ten wide.
      expect(board.slide(arrow).steps, 7);
      expect(board.lane(arrow), <Dot>[
        const Dot(7, 5),
        const Dot(8, 5),
        const Dot(9, 5),
      ]);
    });

    test('an arrow with a body in its way does not, and names it', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(1, 5),
        const Dot(3, 5),
      ]);
      final Arrow wall = Arrow.fromCorners(<Dot>[
        const Dot(6, 3),
        const Dot(6, 7),
      ]);
      final Board board = Board(10, <Arrow>[arrow, wall]);
      final Slide slide = board.slide(arrow);
      expect(slide.escapes, isFalse);
      expect(slide.blocker, same(wall));
      // Head at x = 3, wall at x = 6: the lane is 4, 5, 6, so the head gets two
      // dots along it before the third is somebody else's.
      expect(slide.steps, 2);
    });

    test(
      'a perpendicular crossing is caught between dots as well as on them',
      () {
        // The claim in `Dot`'s comment, as a case: a horizontal arrow sweeping
        // right through a vertical arrow that spans its row. There is no gap to
        // slip through, because the vertical arrow covers (6, 5) and that is
        // exactly where the horizontal one arrives.
        final Arrow mover = Arrow.fromCorners(<Dot>[
          const Dot(0, 5),
          const Dot(2, 5),
        ]);
        final Arrow crossing = Arrow.fromCorners(<Dot>[
          const Dot(6, 4),
          const Dot(6, 6),
        ]);
        expect(Board(12, <Arrow>[mover, crossing]).isFree(mover), isFalse);
        // One row over and it sails past.
        final Arrow missing = crossing.shifted(const Dot(0, 2));
        expect(Board(12, <Arrow>[mover, missing]).isFree(mover), isTrue);
      },
    );

    test('a bend costs an arrow nothing', () {
      // The point of the snake. This arrow is four dots tall and four wide, and
      // none of that is in its way: only the three dots to the right of its
      // point matter, and a rigidly-sliding version of it would have to drag
      // the whole bend through them.
      final Arrow bent = Arrow.fromCorners(<Dot>[
        const Dot(2, 2),
        const Dot(2, 6),
        const Dot(5, 6),
      ]);
      final Arrow beside = Arrow.fromCorners(<Dot>[
        const Dot(7, 2),
        const Dot(7, 4),
      ]);
      // `beside` sits square in the path the bend would sweep if it moved
      // rigidly, and clear of the lane in front of the point.
      final Board board = Board(10, <Arrow>[bent, beside]);
      expect(board.isFree(bent), isTrue);
    });

    test('an arrow may not point along its own body', () {
      // It could not move: the head would land on a dot the tail had not
      // vacated. No shape the generator draws can do it — see `Arrow`.
      expect(
        () => Arrow.fromCorners(<Dot>[
          const Dot(0, 0),
          const Dot(2, 0),
          const Dot(2, 1),
          const Dot(0, 1),
          const Dot(0, 0),
        ]),
        throwsA(anything),
      );
    });

    test('the lane is the dots in front of the point, and only those', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(4, 1),
        const Dot(4, 2),
      ]);
      // Straight down column 4 from below the head, not from the tail.
      expect(Board(6, <Arrow>[arrow]).lane(arrow), <Dot>[
        const Dot(4, 3),
        const Dot(4, 4),
        const Dot(4, 5),
      ]);
    });

    test('anything on the lane blocks, and nothing beside it does', () {
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(4, 1),
        const Dot(4, 2),
      ]);
      final Board board = Board(8, <Arrow>[arrow]);
      for (final Dot dot in board.lane(arrow)) {
        final Arrow wall = Arrow.fromCorners(<Dot>[
          dot,
          dot.step(Heading.left),
        ]);
        expect(
          Board(8, <Arrow>[arrow, wall]).isFree(arrow),
          isFalse,
          reason: 'a body on $dot should stop it',
        );
        // The same body two columns across, off the lane, does not.
        final Arrow aside = wall.shifted(const Dot(-2, 0));
        expect(
          Board(8, <Arrow>[arrow, aside]).isFree(arrow),
          isTrue,
          reason: 'a body beside $dot should not',
        );
      }
    });
  });
}
