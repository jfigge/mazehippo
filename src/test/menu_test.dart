// The way in: title, picker, board, and back out again.
//
// Not a test of how any of it looks — that is what `make board` is for — but of
// the wiring, which is the part that can be silently wrong: a locked level that
// opens, a Continue button pointing at the wrong place, progress that does not
// come back when the game screen is popped.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/app/chrome.dart';
import 'package:mazehippo/app/game_screen.dart';
import 'package:mazehippo/app/level_picker.dart';
import 'package:mazehippo/app/store.dart';
import 'package:mazehippo/app/title_screen.dart';
import 'package:mazehippo/audio/audio_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wait for the isolate that generates a level, then paint. See game_test.dart.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await progress.forget();
    await audioSettings.setMusicVolume(AudioSettings.defaultMusic);
    await audioSettings.setEffectsVolume(AudioSettings.defaultEffects);
  });

  testWidgets('the title screen offers a new player level 1', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TitleScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Maze Hippo'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('0 of 100 cleared'), findsOneWidget);
  });

  testWidgets('and a returning one the level after their furthest', (
    WidgetTester tester,
  ) async {
    await progress.cleared(1, 3, const Duration(seconds: 30));
    await progress.cleared(2, 2, const Duration(seconds: 30));
    await tester.pumpWidget(const MaterialApp(home: TitleScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Continue — level 3'), findsOneWidget);
    expect(find.text('2 of 100 cleared'), findsOneWidget);
  });

  testWidgets('the two volumes are settable and are kept apart', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TitleScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Music'), findsOneWidget);
    expect(find.text('Effects'), findsOneWidget);

    // Drag the music fader to its bottom stop. Zero has to mean silence rather
    // than a very quiet noise — see [AudioSettings.music] — and the effects
    // must not follow it down.
    await tester.drag(find.byType(Slider).first, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(audioSettings.musicVolume, 0);
    expect(audioSettings.music, isFalse);
    expect(audioSettings.effectsVolume, AudioSettings.defaultEffects);
  });

  testWidgets('the picker locks everything past the frontier', (
    WidgetTester tester,
  ) async {
    await progress.cleared(1, 3, const Duration(seconds: 30));
    await tester.pumpWidget(const MaterialApp(home: LevelPicker()));
    await tester.pumpAndSettle();

    // Level 1 cleared and level 2 open; level 3 is not.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    // Each band is named and says what its grade means, rather than leaving
    // the player to infer it from fifty-five hard levels.
    expect(find.text('easy'), findsOneWidget);
    expect(find.text('4 arrows can go at a time'), findsOneWidget);

    // And the far end of the campaign is down there, off the bottom of a lazy
    // list, which is why this has to go and look.
    // The outer list, named explicitly: each band's grid is a Scrollable too
    // (a fixed one), so an unqualified search finds five of them.
    await tester.scrollUntilVisible(
      find.text('hard'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('one arrow can go at a time'), findsOneWidget);
  });

  testWidgets('the picker shows the best time under the hearts', (
    WidgetTester tester,
  ) async {
    await progress.cleared(1, 2, const Duration(milliseconds: 38400));
    await progress.cleared(2, 3, const Duration(milliseconds: 84000));
    await tester.pumpWidget(const MaterialApp(home: LevelPicker()));
    await tester.pumpAndSettle();

    // Tenths under a minute, minutes and seconds above it.
    expect(find.text('38.4s'), findsOneWidget);
    expect(find.text('1:24'), findsOneWidget);
    // And nothing at all on a level that has never been finished.
    expect(saidQuickly(const Duration(milliseconds: 38400)), '38.4s');
  });

  testWidgets('a square tile still holds a number, hearts and a time', (
    WidgetTester tester,
  ) async {
    // At the width that matters. The default test surface is 800 across, which
    // gives tiles half as big again as a phone does — so a layout that fits
    // there can still overflow in a hand, and Flutter reports that as a failed
    // test rather than a warning only if something is actually rendering it.
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await progress.cleared(1, 3, const Duration(milliseconds: 38400));
    await progress.cleared(2, 1, const Duration(milliseconds: 84000));
    await tester.pumpWidget(const MaterialApp(home: LevelPicker()));
    await tester.pumpAndSettle();

    expect(find.text('38.4s'), findsOneWidget);
    expect(find.text('1:24'), findsOneWidget);

    // Square, as asked: the grid is given no aspect ratio, so the tiles take
    // the default of one.
    final GridView grid = tester.widget<GridView>(find.byType(GridView).first);
    final SliverGridDelegateWithFixedCrossAxisCount delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.childAspectRatio, 1.0);
  });

  testWidgets('a locked level does not open', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LevelPicker()));
    await tester.pumpAndSettle();

    // With nothing cleared, only level 1 is unlocked, so the second tile is a
    // padlock and tapping it must do nothing at all.
    expect(find.byIcon(Icons.lock_outline), findsWidgets);
    await tester.tap(find.byIcon(Icons.lock_outline).first);
    await tester.pumpAndSettle();
    expect(find.byType(GameScreen), findsNothing);
  });

  testWidgets('an unlocked one does, and comes back', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LevelPicker()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await settle(tester);
    expect(find.byType(GameScreen), findsOneWidget);
    expect(find.text('Level 1'), findsOneWidget);

    // Back out the way the player would.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(LevelPicker), findsOneWidget);
  });
}
