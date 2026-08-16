// The volumes, and what they do when there is nowhere to keep them.

import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/audio/audio_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('starts at the defaults', () async {
    final AudioSettings a = AudioSettings();
    await a.load();
    expect(a.musicVolume, AudioSettings.defaultMusic);
    expect(a.effectsVolume, AudioSettings.defaultEffects);
    expect(a.music, isTrue);
    expect(a.effects, isTrue);
  });

  test('keeps the two apart', () async {
    final AudioSettings a = AudioSettings();
    await a.setMusicVolume(0);
    expect(a.musicVolume, 0);
    expect(a.effectsVolume, AudioSettings.defaultEffects);
  });

  test('zero is silence rather than a very quiet noise', () async {
    // The distinction [AudioSettings.music] exists to make: at the bottom stop
    // the bed is never started, so there is no voice being rendered and no
    // audio session being held open for the sake of nothing.
    final AudioSettings a = AudioSettings();
    await a.setMusicVolume(0);
    expect(a.music, isFalse);
    await a.setMusicVolume(0.01);
    expect(a.music, isTrue);
  });

  test('clamps whatever a slider hands it', () async {
    final AudioSettings a = AudioSettings();
    await a.setMusicVolume(4);
    expect(a.musicVolume, 1);
    await a.setEffectsVolume(-2);
    expect(a.effectsVolume, 0);
  });

  test('survives a relaunch', () async {
    final AudioSettings before = AudioSettings();
    await before.setMusicVolume(0.25);
    await before.setEffectsVolume(0);

    final AudioSettings after = AudioSettings();
    await after.load();
    expect(after.musicVolume, 0.25);
    expect(after.effectsVolume, 0);
    expect(after.effects, isFalse);
  });
}
