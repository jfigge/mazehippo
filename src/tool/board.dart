// The board, drawn to a file.
//
// The same arrangement Roll Hippo's tool/ uses: a `flutter test` that renders
// rather than asserts, because a painter is checked by looking at it. Run it
// with `make board`, which writes into /tmp/mazehippo/.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/puzzle/puzzle.dart';
import 'package:mazehippo/render/board_painter.dart';
import 'package:mazehippo/render/camera.dart';

/// A phone, less the chrome the game screen puts above and below the board.
const Size phone = Size(390, 700);

Future<void> write(
  String name,
  BoardCamera camera,
  List<ArrowFrame> frames,
) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  BoardPainter(
    camera: camera,
    frames: frames,
  ).paint(Canvas(recorder), camera.viewport);
  final ui.Image image = await recorder.endRecording().toImage(
    camera.viewport.width.round(),
    camera.viewport.height.round(),
  );
  final ByteData bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!;
  final File file = File('/tmp/mazehippo/$name.png');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes.buffer.asUint8List());
  print('wrote ${file.path}');
}

void main() {
  test('every band, fitted', () async {
    for (final int number in <int>[1, 12, 30, 60, 100]) {
      final Level level = generateLevel(number);
      final BoardCamera camera = BoardCamera(size: level.size, viewport: phone)
        ..fit();
      await write(
        '${number.toString().padLeft(3, '0')}-${level.grade.name}',
        camera,
        <ArrowFrame>[for (final Arrow arrow in level.arrows) ArrowFrame(arrow)],
      );
    }
  });

  test('level 100 at 250%, which is what the camera is for', () async {
    final Level level = generateLevel(100);
    final BoardCamera camera = BoardCamera(size: level.size, viewport: phone)
      ..fit()
      ..zoom = 2.5;
    await write('100-zoomed', camera, <ArrowFrame>[
      for (final Arrow arrow in level.arrows) ArrowFrame(arrow),
    ]);
  });

  test('an arrow threading itself out', () async {
    // The movement, caught in the middle. A bent arrow part way out should be
    // wrapped around its own corner — body on the old path, head on the new —
    // which is the one thing a still picture can show about how it moves.
    final Level level = generateLevel(12);
    final Board board = level.board();
    final BoardCamera camera = BoardCamera(size: level.size, viewport: phone)
      ..fit();
    final Arrow bent = board.freeArrows.firstWhere(
      (Arrow arrow) => arrow.corners.length > 2,
      orElse: () => board.freeArrows.first,
    );
    for (final double part in <double>[0, 0.35, 0.7]) {
      await write(
        '012-thread-${(part * 100).round().toString().padLeft(3, '0')}',
        camera,
        <ArrowFrame>[
          for (final Arrow other in level.arrows)
            if (!identical(other, bent)) ArrowFrame(other),
          ArrowFrame(bent, steps: board.exitSteps(bent) * part),
        ],
      );
    }
  });

  test('a tap that was wrong', () async {
    // The first blocked arrow on level 12, shown where it ran out of room, with
    // whatever stopped it lit behind. This is the frame the player is looking
    // at when they have just lost a life, so it is the one worth checking.
    final Level level = generateLevel(12);
    final Board board = level.board();
    final BoardCamera camera = BoardCamera(size: level.size, viewport: phone)
      ..fit();
    for (final Arrow arrow in level.arrows) {
      final Slide slide = board.slide(arrow);
      if (slide.escapes) {
        continue;
      }
      await write('012-blocked', camera, <ArrowFrame>[
        for (final Arrow other in level.arrows)
          if (!identical(other, arrow) && !identical(other, slide.blocker))
            ArrowFrame(other),
        ArrowFrame(slide.blocker!, mood: ArrowMood.culprit),
        ArrowFrame(
          arrow,
          steps: slide.steps.toDouble(),
          mood: ArrowMood.blocked,
        ),
      ]);
      return;
    }
  });
}
