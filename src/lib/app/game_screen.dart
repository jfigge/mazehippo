import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/ambience.dart';
import '../puzzle/puzzle.dart';
import '../render/board_painter.dart';
import '../render/camera.dart';
import 'chrome.dart';
import 'store.dart';

/// One arrow, mid-move.
///
/// Both kinds are here because they are the same thing seen twice: an arrow
/// told to go, and how far it got. [blocker] is what separates them — null and
/// the arrow is on its way off the board, set and it is the arrow that stopped
/// it, which is what the screen turns red alongside.
class _Motion {
  _Motion.leaving(this.arrow, this.distance, this.since) : blocker = null;
  _Motion.balked(this.arrow, this.distance, this.since, Arrow this.blocker);

  final Arrow arrow;

  /// Dots to travel: the whole way out, or as far as the blocker allows.
  final double distance;

  /// Ticker time when the tap landed.
  final Duration since;

  final Arrow? blocker;

  bool get leaving => blocker == null;

  /// A balked arrow is shot out and pulled back, so it is drawn for as long as
  /// that takes however far it got. A leaving one is timed by its distance,
  /// with a floor so a short exit is not a blink and a ceiling so a run across
  /// a 50-dot board is not a stroll.
  Duration get span => leaving
      ? Duration(milliseconds: (120 + 24 * distance).round().clamp(200, 620))
      : const Duration(milliseconds: 520);

  double progress(Duration now) {
    final int elapsed = (now - since).inMicroseconds;
    final int whole = span.inMicroseconds;
    return whole == 0 ? 1 : (elapsed / whole).clamp(0.0, 1.0);
  }

  bool done(Duration now) => progress(now) >= 1;
}

/// How a level ended, while the screen is still showing it.
enum _Outcome { cleared, spent }

/// Where the board is drawn. See the [CustomPaint] in `build`.
const Key boardKey = ValueKey<String>('board');

/// The game.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.startAt = 1});

  final int startAt;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Wrong taps a level allows.
  static const int lives = 3;

  /// Null while a level is being generated. The board that was on screen stays
  /// up in the meantime — see [_present].
  Level? _level;
  Board? _board;

  /// The level being shown or waited for, so the heading can say which one it
  /// is before there is a [Level] to ask.
  late int _number = widget.startAt;

  /// Bumped on every [_present]. A generation that finishes after a newer one
  /// has started belongs to a board nobody is looking at.
  int _token = 0;

  late int _left = lives;

  /// Started by the first arrow the player touches, not by the level arriving.
  ///
  /// A board is read before it is played — on the hard levels for a good while
  /// — and a clock that started with the level would be timing that reading.
  /// Null until the first touch, which is also what tells [RunningClock] there
  /// is nothing to show yet.
  Stopwatch? _clock;

  /// Set when the finished level beat a time it already had. Only then: the
  /// first finish is not a record, because there was nothing to break.
  bool _record = false;
  final List<_Motion> _motions = <_Motion>[];
  BoardCamera? _camera;

  Ticker? _ticker;
  Duration _now = Duration.zero;
  _Outcome? _outcome;

  /// The pinch in progress: what the zoom was when the fingers went down, and
  /// the board point that was under them. Held rather than derived because a
  /// pinch is relative to where it started, not to the last frame.
  double _zoomAtStart = 1;
  Offset _anchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_pump);
    // **This is where the audio engine starts, and the first place it does.**
    // Not at launch: initialising the engine and decoding a hundred and seventy
    // seconds of loop is work, and doing it before the title screen has drawn
    // would put it in front of every launch to serve a screen with no sound on
    // it. A puzzle is the first thing that needs a noise, so a puzzle is what
    // pays for it — behind the level being woven, which is already happening.
    unawaited(ambience.startBed());
    unawaited(_present(widget.startAt));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Generate a level on another isolate.
  ///
  /// **Static, and that is the whole reason it exists.** `Isolate.run` sends
  /// its closure to the other isolate, and a closure written inside an instance
  /// method captures `this` — which here is the [State], which holds its
  /// [Element], which holds the entire widget tree, which contains a `Completer`
  /// and is therefore unsendable. The message fails at run time with a
  /// forty-line chain of `<- _parent in Instance of …` and no mention of the
  /// line that caused it. Declared static there is no `this` to capture, and
  /// the closure carries one `int`.
  static Future<Level> _weave(int number) =>
      Isolate.run(() => generateLevel(number));

  /// Put level [number] on the screen, [after] a pause.
  ///
  /// The generating happens on another isolate. Level 100 is about a tenth of a
  /// second of integer work on a desktop and several times that on a phone,
  /// which is a stutter the player would see on every level, and `lib/puzzle/`
  /// imports no Flutter — so it moves off the main thread for the price of one
  /// `Isolate.run`, with nothing to marshal and no plugin to be absent.
  ///
  /// [after] is what makes the pause free. When a level ends the next one
  /// starts generating immediately and the banner covers it, so the wait the
  /// player sees is the banner they were going to see anyway.
  Future<void> _present(int number, {Duration after = Duration.zero}) async {
    final int wanted = number.clamp(1, LevelPlan.levelCount);
    final int token = ++_token;
    setState(() => _number = wanted);
    final Future<Level> coming = _weave(wanted);
    if (after > Duration.zero) {
      await Future<void>.delayed(after);
    }
    final Level level = await coming;
    if (!mounted || token != _token) {
      return;
    }
    setState(() {
      _level = level;
      _board = level.board();
      _left = lives;
      _clock = null;
      _record = false;
      _motions.clear();
      _outcome = null;
      _camera = null;
    });
  }

  /// One frame of whatever is moving.
  ///
  /// The ticker only runs while something is, which matters more than it looks
  /// like it should: a level sits untouched for as long as the player is
  /// reading it, and a ticker left running would repaint a 2,500-dot board sixty
  /// times a second throughout.
  void _pump(Duration elapsed) {
    setState(() {
      _now = elapsed;
      _motions.removeWhere((_Motion motion) => motion.done(_now));
      if (_motions.isEmpty) {
        _ticker?.stop();
      }
    });
  }

  /// Start the clock, if it is not already running.
  ///
  /// **The reset is load-bearing.** [Ticker.start] measures elapsed time from
  /// zero every time it is called, so [_now] after a restart is smaller than
  /// the [_now] the last batch of motions was stamped against. A motion stamped
  /// with the old clock and read against the new one has negative progress,
  /// which clamps to zero — so the arrow sits perfectly still for as long as
  /// the *previous* animation happened to run, and the delay grows with every
  /// tap. Nothing is ever in flight while the ticker is stopped, so there is
  /// nothing to rebase: zeroing [_now] is the whole fix.
  ///
  /// Callers must wake the clock *before* stamping a motion with [_now].
  void _wake() {
    final Ticker? ticker = _ticker;
    if (ticker == null || ticker.isActive) {
      return;
    }
    _now = Duration.zero;
    ticker.start();
  }

  void _tap(Offset position) {
    final BoardCamera? camera = _camera;
    final Board? board = _board;
    if (camera == null || board == null || _outcome != null) {
      return;
    }
    final Arrow? arrow = camera.arrowUnder(position, board.arrows);
    if (arrow == null) {
      return;
    }
    setState(() {
      // First, so that the motions below are stamped against the clock they
      // will be read against. See [_wake].
      _wake();
      // And the other clock. It starts on the first arrow *touched* rather than
      // on the first one that goes: a wrong tap is a move, and a run that opens
      // with one should be timed from it.
      _clock ??= Stopwatch()..start();
      final Slide slide = board.slide(arrow);
      if (slide.escapes) {
        // Off the board at once, drawn leaving afterwards. The removal is what
        // frees whatever it was blocking, and making the player wait out the
        // animation for that would put a fifth of a second between every tap
        // and the next one being possible.
        board.remove(arrow);
        ambience.arrowAway();
        _motions.add(_Motion.leaving(arrow, slide.steps.toDouble(), _now));
        if (board.isEmpty) {
          _end(_Outcome.cleared);
        }
      } else {
        _left--;
        ambience.arrowBlocked();
        _motions.add(
          _Motion.balked(arrow, slide.steps.toDouble(), _now, slide.blocker!),
        );
        if (_left == 0) {
          _end(_Outcome.spent);
        }
      }
    });
  }

  void _end(_Outcome outcome) {
    _outcome = outcome;
    _clock?.stop();
    if (outcome == _Outcome.cleared) {
      // Recorded the moment it happens rather than when the panel is dismissed,
      // so a player who closes the app on the winning tap still keeps it.
      unawaited(_record_(_number, _left, _clock?.elapsed ?? Duration.zero));
      // And the same moment gets the flourish. This is the only place the game
      // decides a board is solved — there is no second one to keep in step.
      unawaited(ambience.playSolved());
    }
  }

  /// Store the result, and light the panel up if the time was a record.
  ///
  /// Separate from [_end] only because the answer arrives a frame later than
  /// the panel does — writing a preference is asynchronous, and the panel is
  /// not going to wait for a disk to say the level was cleared.
  Future<void> _record_(int number, int livesLeft, Duration took) async {
    final bool beaten = await progress.cleared(number, livesLeft, took);
    if (mounted && beaten) {
      setState(() => _record = true);
    }
  }

  /// Where the panel's buttons go.
  ///
  /// The level no longer advances on a timer. That was right when this screen
  /// was the whole game and there was nowhere else to be; with menus behind it
  /// the player wants to decide, and a screen that moves on by itself while
  /// they are reading what they just did is a screen that took the decision
  /// away.
  void _again() => unawaited(_present(_number));

  void _onward() =>
      unawaited(_present(math.min(_number + 1, LevelPlan.levelCount)));

  /// Everything to draw this frame, still arrows and moving ones together.
  ///
  /// A map keyed by arrow identity, so a balked arrow replaces its own resting
  /// frame rather than being drawn twice — once where it is and once where the
  /// shove has taken it.
  List<ArrowFrame> _frames() {
    final Map<Arrow, ArrowFrame> resting = <Arrow, ArrowFrame>{
      for (final Arrow arrow in _board?.arrows ?? const <Arrow>[])
        arrow: ArrowFrame(arrow),
    };
    final List<ArrowFrame> going = <ArrowFrame>[];

    for (final _Motion motion in _motions) {
      final double t = motion.progress(_now);
      if (motion.leaving) {
        going.add(
          ArrowFrame(
            motion.arrow,
            // Linear, and that is the point. An ease-*in* starts at zero
            // velocity, so the arrow spends the first third of its animation
            // visibly not leaving — which reads as the tap having missed. It
            // is shot out, so it goes at once and at speed.
            steps: t * motion.distance,
            fade: t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4,
          ),
        );
      } else {
        resting[motion.arrow] = ArrowFrame(
          motion.arrow,
          steps: _shove(t) * motion.distance,
          mood: ArrowMood.blocked,
        );
        final Arrow blocker = motion.blocker!;
        if (resting.containsKey(blocker)) {
          resting[blocker] = ArrowFrame(blocker, mood: ArrowMood.culprit);
        }
      }
    }
    return <ArrowFrame>[...resting.values, ...going];
  }

  /// Out to where it was stopped, and back. The arrow travels the distance it
  /// actually had — showing the player *where* it ran out of room, which is the
  /// whole of what they got wrong — and then returns to its place.
  static double _shove(double t) {
    const double out = 0.3;
    return t < out
        ? Curves.easeOutCubic.transform(t / out)
        : 1 - Curves.easeInOutCubic.transform((t - out) / (1 - out));
  }

  @override
  Widget build(BuildContext context) {
    final _Outcome? outcome = _outcome;
    return Scaffold(
      backgroundColor: BoardPainter.background,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                _hud(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      // Set together by [_present] and cleared together, but the
                      // analyser has no way to know that, and saying so here is
                      // cheaper than a null check at each of the three uses.
                      final Level? level = _level;
                      final Board? board = _board;
                      if (level == null || board == null) {
                        return const SizedBox.expand();
                      }
                      final Size window = constraints.biggest;
                      final BoardCamera camera = _cameraFor(level, window);
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (TapUpDetails details) =>
                            _tap(details.localPosition),
                        onScaleStart: (ScaleStartDetails details) {
                          _zoomAtStart = camera.zoom;
                          _anchor = camera.boardOf(details.localFocalPoint);
                        },
                        onScaleUpdate: (ScaleUpdateDetails details) {
                          setState(() {
                            camera.zoomAbout(
                              details.localFocalPoint,
                              _anchor.dx,
                              _anchor.dy,
                              _zoomAtStart * details.scale,
                            );
                            camera.clampToContent(
                              camera.contentOf(board.arrows),
                            );
                          });
                        },
                        child: CustomPaint(
                          // Named so the widget test can ask where the board
                          // ended up and work out what tapping a given arrow
                          // means in screen coordinates, exactly as the camera
                          // does here.
                          key: boardKey,
                          size: window,
                          painter: BoardPainter(
                            camera: camera,
                            frames: _frames(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            // Over the board rather than instead of it: the position the player
            // just finished — or just ran out of lives on — is what they want
            // to be looking at while they decide what to do next.
            if (outcome != null) _panel(outcome),
          ],
        ),
      ),
    );
  }

  /// The camera, kept across rebuilds so a repaint does not undo a pinch, and
  /// rebuilt when the level changes because a new board is a new fit.
  BoardCamera _cameraFor(Level level, Size window) {
    BoardCamera? camera = _camera;
    if (camera == null || camera.size != level.size) {
      camera = BoardCamera(size: level.size, viewport: window)..fit();
      _camera = camera;
    } else {
      camera.viewport = window;
    }
    return camera;
  }

  Widget _hud() {
    final Level? level = _level;
    final String banner = switch (_outcome) {
      _Outcome.cleared => 'Clear',
      _Outcome.spent => 'Out of lives',
      null =>
        level == null
            ? 'weaving…'
            : '${level.grade.name} · ${_board?.length ?? 0} left',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.chevron_left_rounded),
            color: Colors.white38,
            tooltip: 'Levels',
          ),
          Text(
            'Level $_number',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              banner,
              style: TextStyle(
                color: _outcome == null ? Colors.white54 : Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          // Running, and repainting only itself — see [RunningClock]. A clock
          // that rebuilt this screen ten times a second would repaint nine
          // hundred dots to move one digit.
          RunningClock(since: _clock),
          const SizedBox(width: 10),
          Hearts(left: _left, of: lives),
        ],
      ),
    );
  }

  /// What a finished level offers.
  Widget _panel(_Outcome outcome) {
    final bool won = outcome == _Outcome.cleared;
    final Color tint = won
        ? gradeColour(_level?.grade ?? Grade.easy)
        : BoardPainter.blockedColour;
    return Positioned.fill(
      child: ColoredBox(
        color: BoardPainter.background.withValues(alpha: 0.82),
        child: Panel(
          title: won ? 'Level $_number clear' : 'Out of lives',
          tint: tint,
          detail: won
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Hearts(left: _left),
                    const SizedBox(height: 8),
                    Text(
                      saidQuickly(_clock?.elapsed ?? Duration.zero),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                    if (_record) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'new fastest time',
                        style: TextStyle(
                          color: tint,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ],
                )
              : const Text(
                  'the board is still there — try it again',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
          children: <Widget>[
            if (won && _number < LevelPlan.levelCount) ...<Widget>[
              MenuButton(
                label: 'Next level',
                icon: Icons.arrow_forward_rounded,
                tint: tint,
                onPressed: _onward,
              ),
              const SizedBox(height: 10),
            ],
            MenuButton(
              label: won ? 'Play it again' : 'Try again',
              icon: Icons.refresh_rounded,
              tint: won ? Colors.white54 : tint,
              onPressed: _again,
            ),
            const SizedBox(height: 10),
            MenuButton(
              label: 'Levels',
              icon: Icons.grid_view_rounded,
              tint: Colors.white38,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}
