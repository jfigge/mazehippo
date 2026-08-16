import 'package:shared_preferences/shared_preferences.dart';

/// How loud the game is, and the memory of it.
///
/// Two numbers rather than the one on/off switch this replaced, because the bed
/// and the effects are not the same kind of sound: a player who wants the
/// arrows to click but not to be played music at has no way to say so with a
/// switch. Both are 0..1.
///
/// Follows `app/store.dart` in the one habit that matters: **it never throws and
/// never refuses.** It starts at the defaults, [load] fills them in if there is
/// somewhere to load from, and a platform with no `shared_preferences` — every
/// widget test — keeps the defaults.
class AudioSettings {
  static const String _musicKey = 'musicVolume';
  static const String _effectsKey = 'effectsVolume';

  /// Quiet enough to be under the game rather than over it.
  static const double defaultMusic = 0.5;

  /// Louder, because an effect is information and the bed is not.
  static const double defaultEffects = 0.8;

  double musicVolume = defaultMusic;
  double effectsVolume = defaultEffects;

  /// Whether either is worth doing any work for.
  ///
  /// **Zero means silence, not a very quiet noise.** A fader left at its bottom
  /// stop still hands the mixer a voice to render and still opens an audio
  /// session, and on a phone that is a battery cost and a reason for the
  /// player's own music to duck. Asked this way, zero means the sound is never
  /// started at all.
  bool get music => musicVolume > 0;
  bool get effects => effectsVolume > 0;

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      musicVolume = prefs.getDouble(_musicKey) ?? defaultMusic;
      effectsVolume = prefs.getDouble(_effectsKey) ?? defaultEffects;
    } on Object {
      // Defaults stand.
    }
  }

  Future<void> setMusicVolume(double v) async {
    musicVolume = v.clamp(0.0, 1.0);
    await _put(_musicKey, musicVolume);
  }

  Future<void> setEffectsVolume(double v) async {
    effectsVolume = v.clamp(0.0, 1.0);
    await _put(_effectsKey, effectsVolume);
  }

  Future<void> _put(String key, double value) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } on Object {
      // Nowhere to write. The session still sounds right; it just will not
      // tomorrow.
    }
  }
}

/// The one of them, alongside `progress` in `app/store.dart` and for the same
/// reason: there is one player, and making that a parameter would be describing
/// a situation that does not arise.
final AudioSettings audioSettings = AudioSettings();
