// The glue: a tap on the screen, through the camera, into the board.
//
// Everything either side of this is tested on its own — the lattice in
// puzzle_test.dart, the coordinates in camera_test.dart — so what is left is
// the wiring, and the wiring is what a widget test is for.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/app/chrome.dart';
import 'package:mazehippo/app/game_screen.dart';
import 'package:mazehippo/app/store.dart';
import 'package:mazehippo/puzzle/puzzle.dart';
import 'package:mazehippo/render/board_painter.dart';
import 'package:mazehippo/render/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wait for the isolate that generates the level, then paint.
///
/// [WidgetTester.pump] cannot be called inside [WidgetTester.runAsync], so the
/// real time and the frames are taken in that order rather than together. Level
/// 1 weaves in single-digit milliseconds; the wait is loose because a test
/// machine under load is the only thing that could make it matter.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pump();
}

/// Where to tap to hit [arrow], in the screen's own coordinates.
///
/// Built from the same [BoardCamera] the screen builds, fitted to the same
/// rectangle, which is what makes this a test of the wiring rather than a
/// second implementation of it.
Offset tapPointFor(WidgetTester tester, int size, Arrow arrow) {
  final Rect board = tester.getRect(find.byKey(boardKey));
  final BoardCamera camera = BoardCamera(size: size, viewport: board.size)
    ..fit();
  final Dot on = arrow.dots[arrow.dots.length ~/ 2];
  return board.topLeft +
      camera.screenOf(Offset(on.x.toDouble(), on.y.toDouble()));
}

/// What the board is being told to draw right now.
///
/// The animation is invisible from the widget tree — an arrow half way out is
/// pixels, not widgets — so the frames the painter was handed are the only
/// place to see whether anything is actually moving.
List<ArrowFrame> framesOn(WidgetTester tester) {
  final CustomPaint paint = tester.widget<CustomPaint>(find.byKey(boardKey));
  return (paint.painter! as BoardPainter).frames;
}

int heartsLeft(WidgetTester tester) => tester
    .widgetList<Icon>(find.byType(Icon))
    .where((Icon icon) => icon.icon == Icons.favorite)
    .length;

void main() {
  testWidgets('opens on level 1 with three lives and every arrow on it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    final Level level = generateLevel(1);
    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('easy · ${level.arrows.length} left'), findsOneWidget);
    expect(heartsLeft(tester), 3);
  });

  testWidgets('a tap on an arrow that can go takes it off the board', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    // The levels are deterministic, so the test can generate the same one the
    // screen did and ask it which arrows are free.
    final Level level = generateLevel(1);
    final Arrow free = level.board().freeArrows.first;

    await tester.tapAt(tapPointFor(tester, level.size, free));
    await tester.pump();

    expect(find.text('easy · ${level.arrows.length - 1} left'), findsOneWidget);
    expect(heartsLeft(tester), 3, reason: 'a good tap costs nothing');
  });

  testWidgets(
    'a tap on an arrow that cannot costs a life and changes nothing else',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: GameScreen()));
      await settle(tester);

      final Level level = generateLevel(1);
      final Board board = level.board();
      final Arrow stuck = level.arrows.firstWhere(
        (Arrow arrow) => !board.isFree(arrow),
      );

      await tester.tapAt(tapPointFor(tester, level.size, stuck));
      await tester.pump();

      expect(heartsLeft(tester), 2);
      expect(
        find.text('easy · ${level.arrows.length} left'),
        findsOneWidget,
        reason: 'a blocked arrow stays exactly where it is',
      );
    },
  );

  testWidgets('a tap on bare board is not a mistake', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    final Rect board = tester.getRect(find.byKey(boardKey));
    await tester.tapAt(board.topLeft + const Offset(3, 3));
    await tester.pump();

    expect(heartsLeft(tester), 3);
  });

  testWidgets('the second arrow tapped moves as promptly as the first', (
    WidgetTester tester,
  ) async {
    // The regression this exists for: the ticker measures elapsed time from
    // zero every time it is started, so motions stamped against the previous
    // run of it read as not having begun. The first arrow moved, and every one
    // after it stood still for as long as the arrow before it had taken.
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    final Level level = generateLevel(1);
    final Board board = level.board();
    final List<Arrow> free = board.freeArrows;
    expect(free.length, greaterThanOrEqualTo(2), reason: 'level 1 is easy');

    Future<double> tapAndAdvance(Arrow arrow) async {
      await tester.tapAt(tapPointFor(tester, level.size, arrow));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Matched by shape, not by identity. The screen generated its level on
      // its own isolate, so its arrows are copies — equal dot for dot, and
      // never the same objects the test is holding.
      final Iterable<ArrowFrame> moving = framesOn(
        tester,
      ).where((ArrowFrame frame) => listEquals(frame.arrow.dots, arrow.dots));
      expect(moving, hasLength(1), reason: 'it should still be on screen');
      return moving.first.steps;
    }

    final double first = await tapAndAdvance(free[0]);
    expect(first, greaterThan(0));

    // Let the first arrow finish and the ticker stop, which is what sets the
    // trap.
    await tester.pump(const Duration(milliseconds: 800));

    final double second = await tapAndAdvance(free[1]);
    expect(
      second,
      greaterThan(0),
      reason: 'the second tap must animate from the moment it lands too',
    );
  });

  testWidgets('the clock starts on the first arrow touched, not on the level', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    // A board is read before it is played, and on the hard levels for a good
    // while. Nothing is timing that.
    expect(find.byType(RunningClock), findsOneWidget);
    expect(
      tester.widget<RunningClock>(find.byType(RunningClock)).since,
      isNull,
    );

    // A *wrong* tap starts it too — it is a move, and a run that opens with one
    // should be timed from it.
    final Level level = generateLevel(1);
    final Board board = level.board();
    final Arrow stuck = level.arrows.firstWhere(
      (Arrow arrow) => !board.isFree(arrow),
    );
    await tester.tapAt(tapPointFor(tester, level.size, stuck));
    await tester.pump();

    final Stopwatch? running = tester
        .widget<RunningClock>(find.byType(RunningClock))
        .since;
    expect(running, isNotNull);
    expect(running!.isRunning, isTrue);
  });

  testWidgets('a tap that misses everything does not start it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    final Rect board = tester.getRect(find.byKey(boardKey));
    await tester.tapAt(board.topLeft + const Offset(3, 3));
    await tester.pump();
    expect(
      tester.widget<RunningClock>(find.byType(RunningClock)).since,
      isNull,
    );
  });

  testWidgets('says so when a level beats a time it already had', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await progress.forget();
    // A slow run already on the board. The next one will be quicker, because a
    // widget test's clock only moves when it is told to.
    await progress.cleared(1, 1, const Duration(minutes: 5));

    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    // Clear it. Every arrow that can go, until none can — which on level 1 is
    // all of them, because a level cannot be dead-ended.
    final Level level = generateLevel(1);
    final Board board = level.board();
    while (!board.isEmpty) {
      final Arrow free = board.freeArrows.first;
      await tester.tapAt(tapPointFor(tester, level.size, free));
      await tester.pump();
      board.remove(free);
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Level 1 clear'), findsOneWidget);
    expect(find.text('new fastest time'), findsOneWidget);
    expect(progress.bestTime(1)!.inMinutes, lessThan(5));
  });

  testWidgets('and says nothing on a first finish', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await progress.forget();

    await tester.pumpWidget(const MaterialApp(home: GameScreen()));
    await settle(tester);

    final Level level = generateLevel(1);
    final Board board = level.board();
    while (!board.isEmpty) {
      final Arrow free = board.freeArrows.first;
      await tester.tapAt(tapPointFor(tester, level.size, free));
      await tester.pump();
      board.remove(free);
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Level 1 clear'), findsOneWidget);
    // There was nothing to break.
    expect(find.text('new fastest time'), findsNothing);
    expect(progress.bestTime(1), isNotNull);
  });
}
