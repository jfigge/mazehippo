import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import '../puzzle/puzzle.dart';

/// Where the board is being looked at from.
///
/// Two numbers: how far in, and what is in the middle. Everything else — the
/// pitch of the dots, what a tap lands on, how far the player may drag — falls
/// out of those and the size of the window.
class BoardCamera {
  BoardCamera({required this.size, required this.viewport});

  /// Dots across the board.
  final int size;

  /// The window, in logical pixels. Not final: a rotation or a resized desktop
  /// window changes it, and rebuilding the camera around the new one would
  /// throw away the zoom and the pan the player had set.
  Size viewport;

  /// 1.0 is the whole board fitted to the window. The player may pinch between
  /// [minZoom] and [maxZoom] of that.
  ///
  /// Fitted rather than absolute on purpose: level 1 is 14 dots and level 100
  /// is 50, so a fixed pixels-per-dot would either lose the big boards off the
  /// sides or draw the small ones postage-stamp size. Making 100% mean "all of
  /// it" gives the two ends of the campaign the same starting view.
  static const double minZoom = 0.5;
  static const double maxZoom = 4.0;

  /// Dots kept clear around a fitted board, so the arrowheads on the edge rows
  /// are not flush against the glass.
  static const double _margin = 1.0;

  /// How much of the tangle must stay in the window. See [clampToContent].
  static const double _keepVisible = 1.5;

  double zoom = 1.0;

  /// The board-space point under the middle of the window.
  Offset centre = Offset.zero;

  /// Logical pixels per dot at [zoom] 1. The board is square and the window is
  /// not, so it is the shorter side that decides.
  ///
  /// Floored above zero rather than divided by whatever arrives. A window can
  /// be zero-sized for a frame while a layout settles, and a pitch of zero
  /// turns every screen coordinate, the window rectangle and both clamp
  /// intervals into NaN — which does not throw, does not draw, and does not say
  /// where it came from.
  double get fittedPitch {
    final double shorter = math.min(viewport.width, viewport.height);
    return shorter <= 0 ? 1 : shorter / (size - 1 + 2 * _margin);
  }

  double get pitch => fittedPitch * zoom;

  Offset get _windowCentre => Offset(viewport.width / 2, viewport.height / 2);

  Offset screenOf(Offset board) => _windowCentre + (board - centre) * pitch;

  Offset boardOf(Offset screen) => centre + (screen - _windowCentre) / pitch;

  Offset dotAt(Dot dot) => screenOf(Offset(dot.x.toDouble(), dot.y.toDouble()));

  /// The board-space rectangle currently on screen.
  Rect get window => Rect.fromCenter(
    center: centre,
    width: viewport.width / pitch,
    height: viewport.height / pitch,
  );

  /// Look at the whole board, from the middle. What a level opens on.
  void fit() {
    zoom = 1.0;
    centre = Offset((size - 1) / 2, (size - 1) / 2);
  }

  /// Zoom about a fixed point on the screen — the two fingers' midpoint, which
  /// is the only zoom that feels like moving the paper rather than the camera.
  void zoomAbout(Offset screenAnchor, double boardX, double boardY, double to) {
    zoom = to.clamp(minZoom, maxZoom);
    centre = Offset(boardX, boardY) + (_windowCentre - screenAnchor) / pitch;
  }

  /// Keep the tangle where the player can see it.
  ///
  /// The rule is that the bounding box of whatever arrows are left must still
  /// overlap the window by [_keepVisible] dots on both axes. That is a little
  /// stronger than "one arrow is on screen" in the usual case and a little
  /// weaker in the pathological one — a window parked on an empty corner of the
  /// box would satisfy it — but it is the version that can be *clamped* to,
  /// with one interval per axis, rather than searched for. In exchange the
  /// player can never lose the level off the side of the screen, which is the
  /// thing the rule is for.
  ///
  /// When the window is wider than the content — a small board zoomed out — the
  /// interval inverts and there is nothing to choose, so the content is
  /// centred instead.
  void clampToContent(Rect content) {
    final Rect view = window;
    centre = Offset(
      _clampAxis(
        centre.dx,
        content.left + _keepVisible - view.width / 2,
        content.right - _keepVisible + view.width / 2,
        content.center.dx,
      ),
      _clampAxis(
        centre.dy,
        content.top + _keepVisible - view.height / 2,
        content.bottom - _keepVisible + view.height / 2,
        content.center.dy,
      ),
    );
  }

  static double _clampAxis(
    double value,
    double low,
    double high,
    double fallback,
  ) => low > high ? fallback : value.clamp(low, high);

  /// The arrow under [screen], or null if the tap missed everything.
  ///
  /// Nearest wins rather than first-within-range, which is what lets the reach
  /// be generous. It has to be: at level 100 fitted to a phone the dots are
  /// eight pixels apart, and an arrow body a third of that is not something a
  /// finger can be asked to land on. So the reach is the larger of half a dot
  /// and [_touchPixels] worth of them, and picking the closest of whatever is
  /// in range keeps that from grabbing an arrow the player was not aiming at.
  Arrow? arrowUnder(Offset screen, Iterable<Arrow> arrows) {
    final Offset at = boardOf(screen);
    final double reach = math.max(0.55, _touchPixels / pitch);
    Arrow? nearest;
    double best = reach;
    for (final Arrow arrow in arrows) {
      final double distance = _distanceTo(arrow, at);
      if (distance < best) {
        best = distance;
        nearest = arrow;
      }
    }
    return nearest;
  }

  static const double _touchPixels = 20.0;

  /// Board-space distance from [point] to the nearest part of [arrow]'s body.
  ///
  /// Segment by segment rather than dot by dot. Measuring to the dots alone
  /// would report 0.71 for a point half a dot to the side of the middle of a
  /// straight run — further than the reach, on a part of the arrow the player
  /// can plainly see they are touching.
  static double _distanceTo(Arrow arrow, Offset point) {
    double best = double.infinity;
    for (int i = 1; i < arrow.dots.length; i++) {
      final Offset a = Offset(
        arrow.dots[i - 1].x.toDouble(),
        arrow.dots[i - 1].y.toDouble(),
      );
      final Offset b = Offset(
        arrow.dots[i].x.toDouble(),
        arrow.dots[i].y.toDouble(),
      );
      final Offset span = b - a;
      final double lengthSquared = span.distanceSquared;
      final double t = lengthSquared == 0
          ? 0
          : (((point - a).dx * span.dx + (point - a).dy * span.dy) /
                    lengthSquared)
                .clamp(0.0, 1.0);
      best = math.min(best, (point - (a + span * t)).distance);
    }
    return best;
  }

  /// The bounding box of [arrows], in board space, or the whole board if there
  /// are none left to bound.
  Rect contentOf(Iterable<Arrow> arrows) {
    if (arrows.isEmpty) {
      return Rect.fromLTRB(0, 0, (size - 1).toDouble(), (size - 1).toDouble());
    }
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    for (final Arrow arrow in arrows) {
      left = math.min(left, arrow.minX.toDouble());
      top = math.min(top, arrow.minY.toDouble());
      right = math.max(right, arrow.maxX.toDouble());
      bottom = math.max(bottom, arrow.maxY.toDouble());
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
