import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_settings.dart';

/// Everything the game sounds like.
///
/// A bed of two loops under play, a flourish when a board comes out, and the
/// two blips the arrows make. One engine and one audio session for the lot,
/// which is not tidiness: on iOS every audio library configures
/// `AVAudioSession` for itself, and two of them arguing is how a game ends up
/// stopping the music the player already had on.
///
/// **The bed is two loops of coprime length.** The pad is 97 seconds and the
/// layer over it is 71, they share no factors, and so the pair realign only every
/// 97 × 71 = 6,887 seconds — an hour and fifty-five minutes. Until then the
/// player keeps hearing combinations of the two they have not heard before,
/// out of two files that come to under half a megabyte. **Do not make the
/// lengths match, or nearly match.** The mismatch is the entire mechanism;
/// tidying it away turns a bed that does not repeat into one that repeats every
/// minute and a half.
///
/// **Nothing here ever throws, and nothing here is ever required.** If the
/// engine will not start, or an asset is missing, [_failed] goes up and every
/// method becomes a no-op — the game runs, silently, and nobody upstream has to
/// know. That is also what makes it safe under `flutter test`, where there is
/// no audio platform at all, without a mock or a second implementation.
class Ambience {
  static const String _padAsset = 'assets/audio/pad.ogg';

  /// The upper layer, and **the one line to change to swap it.**
  ///
  /// `ether.ogg` is high voices swelling past each other; `assets/audio/bells.ogg`
  /// is the scatter of struck bells this started as, still rendered by
  /// `make audio` and still shipped, so going back costs an edit here and no
  /// re-render. Whatever it points at has to be 71 seconds — see the class
  /// comment for why that number and the pad's 97 are the whole design.
  static const String _shimmerAsset = 'assets/audio/ether.ogg';
  static const String _solvedAsset = 'assets/audio/solved.ogg';
  static const String _awayAsset = 'assets/laser_soft.wav';
  static const String _blockedAsset = 'assets/boop.wav';

  /// How long the bed takes to arrive, and to leave.
  static const Duration _fadeIn = Duration(milliseconds: 2500);
  static const Duration _fadeOut = Duration(milliseconds: 1200);

  /// The duck under the flourish: how far down, how fast, how long it stays
  /// there, and how slowly it comes back.
  static const double _duckTo = 0.35;
  static const Duration _duckDown = Duration(milliseconds: 400);
  static const Duration _duckHold = Duration(seconds: 2);
  static const Duration _duckUp = Duration(milliseconds: 1500);

  /// What a lifecycle pause gets. Short, because the player has already gone.
  static const Duration _pauseFade = Duration(milliseconds: 600);

  AudioSource? _pad;
  AudioSource? _shimmer;
  AudioSource? _solved;
  AudioSource? _away;
  AudioSource? _blocked;

  SoundHandle? _padHandle;
  SoundHandle? _shimmerHandle;

  bool _initialised = false;
  bool _failed = false;
  Future<void>? _starting;

  /// Cancelled and restarted rather than stacked. Two flourishes in quick
  /// succession must leave the bed ducked once and come back up once — fades
  /// laid on top of each other fight, and what the player hears is the bed
  /// pumping.
  Timer? _unduck;
  Timer? _sleep;
  bool _bedRunning = false;
  bool _bedPaused = false;

  bool get running => _bedRunning;

  /// Start the engine and pull the five sources into memory. Idempotent, and
  /// cheap after the first call: concurrent callers wait on the same future
  /// rather than racing to initialise twice.
  Future<void> init() async {
    if (_failed || _initialised) {
      return;
    }
    return _starting ??= _init();
  }

  Future<void> _init() async {
    try {
      if (!SoLoud.instance.isInitialized) {
        await SoLoud.instance.init();
      }
    } on Object {
      // No audio here: a test, or a platform without the plugin. Say so once
      // and never ask again.
      _failed = true;
      _starting = null;
      return;
    }

    // Each file on its own, so one that is missing takes only itself with it.
    // A build with `pad.ogg` stripped out should lose the bed and keep the
    // blips, not go silent altogether — and the whole point of the guards
    // downstream is that a null source is an ordinary state rather than a
    // fault.
    _pad = await _source(_padAsset);
    _shimmer = await _source(_shimmerAsset);
    _solved = await _source(_solvedAsset);
    _away = await _source(_awayAsset);
    _blocked = await _source(_blockedAsset);
    _initialised = true;
    _starting = null;
  }

  Future<AudioSource?> _source(String asset) async {
    try {
      return await SoLoud.instance.loadAsset(asset);
    } on Object {
      return null;
    }
  }

  /// Bring the bed in. A no-op if it is already up, or if the player has the
  /// music at zero.
  ///
  /// Both loops start in the same call and fade together. The pad may lead the
  /// layer above it, never the other way round — an upper voice arriving over
  /// silence sounds like a mistake, where the same voice arriving over a pad
  /// that is already there sounds like part of it.
  Future<void> startBed() async {
    if (_bedRunning || !audioSettings.music) {
      return;
    }
    await init();
    if (_failed || _pad == null || _shimmer == null) {
      return;
    }
    try {
      _padHandle = SoLoud.instance.play(_pad!, volume: 0, looping: true);
      _shimmerHandle = SoLoud.instance.play(
        _shimmer!,
        volume: 0,
        looping: true,
      );
      _bedRunning = true;
      _bedPaused = false;
      _fadeBedTo(1, _fadeIn);
    } on Object {
      _failed = true;
    }
  }

  Future<void> stopBed({Duration fade = _fadeOut}) async {
    if (!_bedRunning) {
      return;
    }
    _unduck?.cancel();
    _sleep?.cancel();
    _fadeBedTo(0, fade);
    final SoundHandle? pad = _padHandle;
    final SoundHandle? shimmer = _shimmerHandle;
    _padHandle = null;
    _shimmerHandle = null;
    _bedRunning = false;
    // Let the fade finish before the voices go, or the last thing the player
    // hears is the bed being cut off rather than leaving.
    await Future<void>.delayed(fade);
    try {
      if (pad != null) {
        await SoLoud.instance.stop(pad);
      }
      if (shimmer != null) {
        await SoLoud.instance.stop(shimmer);
      }
    } on Object {
      _failed = true;
    }
  }

  /// A board came out. Duck the bed, put the flourish over the top, and bring
  /// the bed back up under it.
  Future<void> playSolved() async {
    await init();
    if (_failed) {
      return;
    }
    // The duck first, so it is already moving by the time the flourish speaks.
    // If one is still in progress this restarts its timer rather than adding a
    // second set of fades to the first.
    _unduck?.cancel();
    if (_bedRunning && !_bedPaused) {
      _fadeBedTo(_duckTo, _duckDown);
      _unduck = Timer(_duckHold, () {
        if (_bedRunning && !_bedPaused) {
          _fadeBedTo(1, _duckUp);
        }
      });
    }
    _oneShot(_solved);
  }

  void arrowAway() => _oneShot(_away);

  void arrowBlocked() => _oneShot(_blocked);

  void _oneShot(AudioSource? source) {
    if (_failed || !_initialised || source == null) {
      return;
    }
    if (!audioSettings.effects) {
      return;
    }
    try {
      SoLoud.instance.play(source, volume: audioSettings.effectsVolume);
    } on Object {
      _failed = true;
    }
  }

  /// Move both bed voices to [part] of their proper level.
  ///
  /// The 6 dB the pad sits above the layer over it is **in the files** — they are
  /// mastered to -20 and -26 LUFS by `make audio` — so there is one gain here
  /// and not two. Balancing them a second time in code would mean two places
  /// disagreeing about the mix, and the one that was measured is the one to
  /// keep.
  void _fadeBedTo(double part, Duration over) {
    final double target = audioSettings.musicVolume * part;
    try {
      if (_padHandle != null) {
        SoLoud.instance.fadeVolume(_padHandle!, target, over);
      }
      if (_shimmerHandle != null) {
        SoLoud.instance.fadeVolume(_shimmerHandle!, target, over);
      }
    } on Object {
      _failed = true;
    }
  }

  Future<void> setMusicVolume(double v) async {
    await audioSettings.setMusicVolume(v);
    if (!audioSettings.music) {
      // Zero is silence, not a quiet noise: the voices go away rather than
      // staying up at nothing. See [AudioSettings.music].
      await stopBed(fade: const Duration(milliseconds: 250));
      return;
    }
    if (_bedRunning) {
      _fadeBedTo(1, const Duration(milliseconds: 200));
    }
  }

  Future<void> setEffectsVolume(double v) => audioSettings.setEffectsVolume(v);

  /// The app went away. Fade down, then pause — **never** deinit: bringing the
  /// engine back up costs a visible stutter, and the player is coming back.
  void sleep() {
    if (!_bedRunning || _bedPaused) {
      return;
    }
    _bedPaused = true;
    _unduck?.cancel();
    _fadeBedTo(0, _pauseFade);
    _sleep?.cancel();
    _sleep = Timer(_pauseFade, () {
      _setPaused(true);
    });
  }

  /// And came back.
  void wake() {
    if (!_bedRunning || !_bedPaused) {
      return;
    }
    _sleep?.cancel();
    _bedPaused = false;
    _setPaused(false);
    _fadeBedTo(1, _fadeIn);
  }

  void _setPaused(bool paused) {
    try {
      if (_padHandle != null) {
        SoLoud.instance.setPause(_padHandle!, paused);
      }
      if (_shimmerHandle != null) {
        SoLoud.instance.setPause(_shimmerHandle!, paused);
      }
    } on Object {
      _failed = true;
    }
  }

  /// From the app's dispose, not a screen's. A screen that tore the engine down
  /// on its way out would take the bed with it every time the player looked at
  /// the level list.
  Future<void> dispose() async {
    _unduck?.cancel();
    _sleep?.cancel();
    try {
      await stopBed(fade: Duration.zero);
      for (final AudioSource? source in <AudioSource?>[
        _pad,
        _shimmer,
        _solved,
        _away,
        _blocked,
      ]) {
        if (source != null) {
          await SoLoud.instance.disposeSource(source);
        }
      }
    } on Object {
      // Going away anyway.
    }
    _pad = _shimmer = _solved = _away = _blocked = null;
    _initialised = false;
  }
}

/// The one of it, alongside `progress` and `audioSettings`.
final Ambience ambience = Ambience();
