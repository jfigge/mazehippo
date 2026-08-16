// The audio, where there is none.
//
// Every test in this suite runs without an audio platform, which is exactly the
// state `Ambience` has to survive: the engine will not start, no asset will
// load, and none of that may reach the game. So this is the contract the spec
// asks for, checked — **every public method is safe to call before `init()` has
// finished, and safe to call when it never will.**

import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/audio/ambience.dart';
import 'package:mazehippo/audio/audio_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('every method is safe before init, and without an engine', () async {
    final Ambience a = Ambience();
    // Deliberately not awaiting init first. Each of these has to look after
    // itself.
    a.arrowAway();
    a.arrowBlocked();
    a.sleep();
    a.wake();
    await a.playSolved();
    await a.startBed();
    await a.stopBed();
    await a.setMusicVolume(0.3);
    await a.setEffectsVolume(0.3);
    await a.dispose();
    expect(a.running, isFalse);
  });

  test('init is idempotent and never throws', () async {
    final Ambience a = Ambience();
    await Future.wait<void>(<Future<void>>[a.init(), a.init(), a.init()]);
    await a.init();
    await a.dispose();
  });

  test('the bed is never started when the music is at zero', () async {
    // Not merely faded to nothing: at the bottom stop there is no voice and no
    // audio session held open for the sake of it. See [AudioSettings.music].
    await audioSettings.setMusicVolume(0);
    final Ambience a = Ambience();
    await a.startBed();
    expect(a.running, isFalse);
    await a.dispose();
  });

  test('a solve is safe with no bed under it', () async {
    // The flourish and the duck are separate: a player with the music off still
    // gets told they solved it.
    await audioSettings.setMusicVolume(0);
    final Ambience a = Ambience();
    await a.playSolved();
    await a.playSolved();
    expect(a.running, isFalse);
    await a.dispose();
  });
}
