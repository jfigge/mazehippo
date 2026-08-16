// The camera: what fits, what a pinch does, and what a tap lands on.
//
// None of this needs a widget. The camera is arithmetic between two coordinate
// systems, and the gestures on `game_screen.dart` are four lines that hand it
// numbers — so the sums are what is worth pinning, and they pin headlessly.

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/puzzle/puzzle.dart';
import 'package:mazehippo/render/camera.dart';

/// A phone, less the chrome above and below the board.
const Size phone = Size(390, 700);

BoardCamera fitted(int size) => BoardCamera(size: size, viewport: phone)..fit();

void main() {
  group('fitting', () {
    test('puts the whole board on the screen, centred', () {
      final BoardCamera camera = fitted(14);
      final Offset topLeft = camera.dotAt(const Dot(0, 0));
      final Offset bottomRight = camera.dotAt(const Dot(13, 13));
      expect(topLeft.dx, greaterThan(0));
      expect(topLeft.dy, greaterThan(0));
      expect(bottomRight.dx, lessThan(phone.width));
      expect(bottomRight.dy, lessThan(phone.height));
      // Centred: the margins match on both axes.
      expect(topLeft.dx, closeTo(phone.width - bottomRight.dx, 0.001));
      expect(topLeft.dy, closeTo(phone.height - bottomRight.dy, 0.001));
    });

    test('fits the big boards to the same window as the small ones', () {
      // The reason zoom is a fraction of a fit rather than a pixel count: the
      // campaign runs from 14 dots to 50, and both ends open showing all of it.
      for (final int size in <int>[14, 26, 38, 50]) {
        final BoardCamera camera = fitted(size);
        expect(camera.dotAt(Dot(0, 0)).dx, greaterThan(0));
        expect(camera.dotAt(Dot(size - 1, size - 1)).dx, lessThan(phone.width));
      }
    });

    test('screen and board are inverses of each other', () {
      final BoardCamera camera = fitted(22)..zoom = 2.3;
      const Offset probe = Offset(137, 402);
      final Offset there = camera.boardOf(probe);
      expect(camera.screenOf(there).dx, closeTo(probe.dx, 0.001));
      expect(camera.screenOf(there).dy, closeTo(probe.dy, 0.001));
    });
  });

  group('pinching', () {
    test('holds the point between the fingers still', () {
      // What makes a pinch feel like moving the paper rather than the camera:
      // whatever was under the fingers is still under them afterwards.
      final BoardCamera camera = fitted(18);
      const Offset fingers = Offset(120, 260);
      final Offset held = camera.boardOf(fingers);
      camera.zoomAbout(fingers, held.dx, held.dy, 3.1);
      expect(camera.screenOf(held).dx, closeTo(fingers.dx, 0.001));
      expect(camera.screenOf(held).dy, closeTo(fingers.dy, 0.001));
      expect(camera.zoom, closeTo(3.1, 0.001));
    });

    test('stops at half and at four times', () {
      final BoardCamera camera = fitted(18);
      camera.zoomAbout(const Offset(10, 10), 1, 1, 0.05);
      expect(camera.zoom, BoardCamera.minZoom);
      camera.zoomAbout(const Offset(10, 10), 1, 1, 40);
      expect(camera.zoom, BoardCamera.maxZoom);
    });
  });

  group('panning', () {
    test('cannot push the arrows off the screen', () {
      final BoardCamera camera = fitted(50)..zoom = 3.5;
      final Rect content = camera.contentOf(<Arrow>[
        Arrow.fromCorners(<Dot>[const Dot(20, 20), const Dot(26, 20)]),
      ]);
      // Dragged hard into a far corner of a 50-dot board, then clamped.
      camera.centre = const Offset(200, -180);
      camera.clampToContent(content);
      expect(camera.window.overlaps(content.inflate(0.01)), isTrue);
    });

    test('leaves the required sliver of it in the window and no less', () {
      // Zoomed out, one short arrow, dragged as far as the clamp allows: the
      // rule is a margin's worth still inside, not the whole thing.
      final BoardCamera camera = fitted(14)..zoom = BoardCamera.minZoom;
      final Rect content = camera.contentOf(<Arrow>[
        Arrow.fromCorners(<Dot>[const Dot(6, 6), const Dot(7, 6)]),
      ]);
      camera.centre = const Offset(90, 90);
      camera.clampToContent(content);
      expect(camera.window.overlaps(content.inflate(0.01)), isTrue);
      expect(camera.centre.dx, lessThan(90));
    });

    test('centres rather than making a NaN when the window is degenerate', () {
      // A zero-sized viewport for one frame is a real thing during layout. It
      // leaves no interval to clamp into, and — before `fittedPitch` was
      // floored — no finite number anywhere either.
      final BoardCamera camera = BoardCamera(size: 14, viewport: Size.zero)
        ..fit()
        ..centre = const Offset(90, 90);
      const Rect content = Rect.fromLTRB(6, 6, 7, 6);
      camera.clampToContent(content);
      expect(camera.centre.dx.isFinite, isTrue);
      expect(camera.centre.dx, closeTo(content.center.dx, 0.001));
      expect(camera.centre.dy, closeTo(content.center.dy, 0.001));
    });
  });

  group('tapping', () {
    final Arrow across = Arrow.fromCorners(<Dot>[
      const Dot(2, 5),
      const Dot(8, 5),
    ]);
    final Arrow below = Arrow.fromCorners(<Dot>[
      const Dot(2, 6),
      const Dot(8, 6),
    ]);

    test(
      'finds the arrow under the finger, mid-segment as well as on a dot',
      () {
        final BoardCamera camera = fitted(14);
        // Half a dot along a straight run is the case that measuring to the dots
        // alone gets wrong.
        expect(
          camera.arrowUnder(camera.screenOf(const Offset(4.5, 5)), <Arrow>[
            across,
          ]),
          same(across),
        );
      },
    );

    test('misses when the finger is nowhere near', () {
      final BoardCamera camera = fitted(14);
      expect(
        camera.arrowUnder(camera.screenOf(const Offset(4, 11)), <Arrow>[
          across,
        ]),
        isNull,
      );
    });

    test('takes the nearer of two arrows a row apart', () {
      final BoardCamera camera = fitted(14);
      expect(
        camera.arrowUnder(camera.screenOf(const Offset(5, 5.4)), <Arrow>[
          across,
          below,
        ]),
        same(across),
      );
      expect(
        camera.arrowUnder(camera.screenOf(const Offset(5, 5.6)), <Arrow>[
          across,
          below,
        ]),
        same(below),
      );
    });

    test('reaches further when the dots are small', () {
      // Level 100 fitted to a phone puts the dots about eight pixels apart, and
      // a body a third of that is not a target. The reach grows to a fixed
      // number of pixels instead, or the big boards would be untappable.
      final BoardCamera far = fitted(50);
      final Arrow arrow = Arrow.fromCorners(<Dot>[
        const Dot(20, 20),
        const Dot(24, 20),
      ]);
      final Offset justOff =
          far.screenOf(const Offset(22, 20)) + const Offset(0, 14);
      expect(far.arrowUnder(justOff, <Arrow>[arrow]), same(arrow));
    });
  });
}
