import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../puzzle/puzzle.dart';
import 'camera.dart';

/// How an arrow is feeling about the tap it just got.
enum ArrowMood {
  /// Sitting on the board, or on its way off it.
  calm,

  /// Tapped, and stopped. The one the player got wrong.
  blocked,

  /// What stopped it. Lit alongside, because "why not" is the whole question
  /// the player is asking at that moment and pointing at the answer is worth
  /// more than any amount of animation on the arrow that failed.
  culprit,
}

/// One arrow, as it is to be drawn this frame.
///
/// [steps] is how far along its own path it has threaded itself — fractional,
/// because this is the middle of an animation — and [fade] is what is left of it
/// as it goes. The board itself is drawn from a list of these with both at rest,
/// so there is one drawing path rather than a still one and a moving one.
class ArrowFrame {
  const ArrowFrame(
    this.arrow, {
    this.steps = 0,
    this.mood = ArrowMood.calm,
    this.fade = 1,
  });

  final Arrow arrow;
  final double steps;
  final ArrowMood mood;
  final double fade;
}

/// The board: a light grid of dots, and the arrows wound through it.
class BoardPainter extends CustomPainter {
  const BoardPainter({required this.camera, required this.frames});

  final BoardCamera camera;
  final List<ArrowFrame> frames;

  /// The eight arrow colours.
  ///
  /// Which one an arrow gets is a function of where its head is — see
  /// [colourOf], which is load-bearing rather than decorative.
  static const List<Color> palette = <Color>[
    Color(0xFF4FC3F7),
    Color(0xFFFFB74D),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
    Color(0xFF4DD0E1),
    Color(0xFFF06292),
    Color(0xFFAED581),
    Color(0xFF9575CD),
  ];

  static const Color background = Color(0xFF11141A);
  static const Color gridDot = Color(0x33FFFFFF);

  /// The arrow that was tapped and could not go.
  static const Color blockedColour = Color(0xFFFF5252);

  /// And the glow put behind whatever stopped it. A halo rather than a second
  /// coat of red: two red arrows beside each other say only that something went
  /// wrong, where one red arrow and one lit arrow says *this* could not get
  /// past *that*, which is the sentence the player needs.
  static const Color culpritColour = Color(0xFFFF1744);

  /// An arrow's colour, from the position of its head.
  ///
  /// **Not from its index.** The arrows are stored in the order the generator
  /// placed them and the reverse of that order is the solution, so anything the
  /// player can see that is derived from the index — a colour, a draw order —
  /// hands them the answer. Position carries no such information.
  static Color colourOf(Arrow arrow) =>
      palette[(arrow.head.x * 7 + arrow.head.y * 13) % palette.length];

  /// The body, as a fraction of the dot pitch. Thick enough to read as a solid
  /// obstacle — which is what it is — without closing up the gaps between
  /// neighbouring rows.
  static const double _bodyWidth = 0.34;

  /// How far past the head dot the point reaches, and how wide it is there.
  static const double _headLength = 0.62;
  static const double _headWidth = 0.86;

  /// The glow behind a culprit, as a fraction of the dot pitch. Wide enough to
  /// stand clear of the body it is behind at any zoom.
  static const double _haloWidth = 0.95;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    _paintGrid(canvas, size);
    for (final ArrowFrame frame in frames) {
      _paintArrow(canvas, frame);
    }
  }

  /// The dots.
  ///
  /// They are the reason the game can be played at all: an arrow travels along
  /// a row of them, so the player can follow the line it will take and see
  /// whether it clears everything in the way without having to guess at what
  /// counts as lined up. Only the ones inside the window are drawn — a 50 × 50
  /// board zoomed to 400% has most of its 2,500 dots off screen.
  void _paintGrid(Canvas canvas, Size size) {
    final double pitch = camera.pitch;
    final Paint paint = Paint()..color = gridDot;
    final double radius = math.max(1.0, pitch * 0.055);
    final Rect window = camera.window;
    final int fromX = math.max(0, window.left.floor());
    final int toX = math.min(camera.size - 1, window.right.ceil());
    final int fromY = math.max(0, window.top.floor());
    final int toY = math.min(camera.size - 1, window.bottom.ceil());

    // One list of centres and a single call, rather than a few thousand.
    final List<Offset> centres = <Offset>[
      for (int x = fromX; x <= toX; x++)
        for (int y = fromY; y <= toY; y++) camera.dotAt(Dot(x, y)),
    ];
    if (centres.isEmpty) {
      return;
    }
    canvas.drawPoints(
      ui.PointMode.points,
      centres,
      paint
        ..strokeWidth = radius * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  /// The arrow's outline, [steps] of the way along its path, in board space.
  ///
  /// This is the snake, drawn. `Arrow.pathDot` is the whole path from the tail
  /// onwards, and after `steps` moves the arrow covers the window of it from
  /// `steps` to `steps + length - 1` — so the shape at rest and the shape half
  /// way out of the board are the same expression with a different offset, and
  /// the body bends around corners on the way out because the path does.
  ///
  /// [steps] is fractional, so both ends of that window land between dots. The
  /// two ends share the same fraction — the window slides, it does not stretch —
  /// which is why one `f` does for both.
  static List<Offset> _thread(Arrow arrow, double steps) {
    Offset at(int i) =>
        Offset(arrow.pathDot(i).x.toDouble(), arrow.pathDot(i).y.toDouble());

    final int length = arrow.dots.length;
    final int from = steps.floor();
    final double f = steps - from;
    if (f <= 0) {
      return <Offset>[for (int i = from; i < from + length; i++) at(i)];
    }
    return <Offset>[
      Offset.lerp(at(from), at(from + 1), f)!,
      for (int i = from + 1; i < from + length; i++) at(i),
      Offset.lerp(at(from + length - 1), at(from + length), f)!,
    ];
  }

  void _paintArrow(Canvas canvas, ArrowFrame frame) {
    final Arrow arrow = frame.arrow;
    final double pitch = camera.pitch;
    final List<Offset> points = _thread(arrow, frame.steps);

    final Path body = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset at = camera.screenOf(points[i]);
      if (i == 0) {
        body.moveTo(at.dx, at.dy);
      } else {
        body.lineTo(at.dx, at.dy);
      }
    }

    // The point, from the leading end outwards along the last stretch of body.
    // Taken from the drawn shape rather than from `arrow.heading`, because a
    // body part way round a corner is still pointing the way it came until the
    // head has finished turning.
    final Offset lead = points.last;
    final Offset run = lead - points[points.length - 2];
    final Offset along = run.distance < 1e-9
        ? Offset(arrow.heading.dx.toDouble(), arrow.heading.dy.toDouble())
        : run / run.distance;
    final Offset across = Offset(-along.dy, along.dx);
    final Offset tip = camera.screenOf(lead + along * _headLength);
    final Offset left = camera.screenOf(lead + across * (_headWidth / 2));
    final Offset right = camera.screenOf(lead - across * (_headWidth / 2));
    final Path point = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();

    if (frame.mood == ArrowMood.culprit) {
      final Paint halo = Paint()
        ..color = culpritColour.withValues(alpha: 0.5 * frame.fade)
        ..strokeWidth = pitch * _haloWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(body, halo);
      canvas.drawPath(point, halo);
    }

    // A culprit keeps its own colour — the halo is what marks it. Only the
    // arrow that actually failed goes red.
    final Color colour = frame.mood == ArrowMood.blocked
        ? blockedColour
        : colourOf(arrow);
    canvas.drawPath(
      body,
      Paint()
        ..color = colour.withValues(alpha: frame.fade)
        ..strokeWidth = pitch * _bodyWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      point,
      Paint()
        ..color = colour.withValues(alpha: frame.fade)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(BoardPainter old) => true;
}
