import 'package:shared_preferences/shared_preferences.dart';

/// Everything the game remembers between launches.
///
/// Two objects, one file, and one habit worth stating once: **neither of them
/// ever throws, and neither of them ever refuses to work.** They start at their
/// defaults, [load] fills them in if there is somewhere to load from, and a
/// platform with no `shared_preferences` behind it — which is every widget test
/// in the suite — simply keeps the defaults. A game that would not start
/// because it could not read a preference would be a worse game.
///
/// Both are single global instances rather than something passed down the
/// widget tree, matching Roll Hippo. There is one player and one set of
/// progress; making that a parameter would be describing a situation that does
/// not arise.
class Progress {
  /// How the whole campaign fits in one string: one character per level, in
  /// order, `'0'` for a level not yet cleared and `'1'`–`'3'` for the most
  /// lives that were left when it was.
  ///
  /// A hundred characters, which is smaller than any of the alternatives and,
  /// more to the point, is legible when printed. A player who has cleared the
  /// first ten levels without losing a life reads as ten threes and ninety
  /// zeros, so a bug in it can be seen rather than deduced.
  static const String _key = 'progress';

  /// The other half of a result: how long the level took, in milliseconds, and
  /// zero for one that has never been finished.
  ///
  /// A separate key from [_key] rather than a wider character in it, because a
  /// time does not fit in a character and the whole virtue of that string is
  /// that it can be read. Comma-separated for the same reason.
  static const String _timesKey = 'times';

  /// Levels, in order. Index 0 is level 1.
  final List<int> _best = List<int>.filled(levelCount, 0);
  final List<int> _times = List<int>.filled(levelCount, 0);

  static const int levelCount = 100;

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(_key);
      if (stored == null) {
        return;
      }
      for (int i = 0; i < levelCount && i < stored.length; i++) {
        final int lives = stored.codeUnitAt(i) - 0x30;
        if (lives >= 0 && lives <= 3) {
          _best[i] = lives;
        }
      }
      final List<String> times = prefs.getStringList(_timesKey) ?? <String>[];
      for (int i = 0; i < levelCount && i < times.length; i++) {
        // Anything unreadable is treated as no time rather than trusted. A
        // preference outlives the code that wrote it.
        _times[i] = int.tryParse(times[i]) ?? 0;
      }
    } on Object {
      // No preferences here. The defaults are a new player, which is the right
      // thing to be when nothing is known.
    }
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        String.fromCharCodes(<int>[
          for (final int lives in _best) 0x30 + lives,
        ]),
      );
      await prefs.setStringList(_timesKey, <String>[
        for (final int ms in _times) '$ms',
      ]);
    } on Object {
      // Nowhere to write. The session still plays; it just will not be there
      // tomorrow.
    }
  }

  /// The most lives left on any clear of [number], or zero if it has never been
  /// cleared.
  int bestLives(int number) => _best[number - 1];

  bool isCleared(int number) => _best[number - 1] > 0;

  /// The quickest this level has ever been finished, or null if it has not
  /// been. Timed from the first arrow touched — see `game_screen.dart`.
  Duration? bestTime(int number) {
    final int ms = _times[number - 1];
    return ms > 0 ? Duration(milliseconds: ms) : null;
  }

  /// The furthest level the player may open: everything cleared, and the one
  /// after it. Level 1 is always available.
  int get unlocked {
    for (int n = levelCount; n >= 1; n--) {
      if (isCleared(n)) {
        return n < levelCount ? n + 1 : levelCount;
      }
    }
    return 1;
  }

  bool isUnlocked(int number) => number <= unlocked;

  int get clearedCount => _best.where((int lives) => lives > 0).length;

  /// Where the Play button goes: the first level not yet cleared, or the last
  /// one for a player who has finished.
  int get next => unlocked;

  /// Record a clear, and say whether the time was a new record.
  ///
  /// Only ever improves what is stored: replaying a level and doing worse takes
  /// neither the hearts nor the time away, and the two improve independently —
  /// a scrappy fast run and a careful slow one each keep the half they won.
  ///
  /// Returns true only when there was **already** a time and this one beat it.
  /// The first finish is not a record; there was nothing to break.
  Future<bool> cleared(int number, int livesLeft, Duration took) async {
    final int i = number - 1;
    final int ms = took.inMilliseconds;
    final bool hadTime = _times[i] > 0;
    final bool faster = ms > 0 && (!hadTime || ms < _times[i]);

    if (livesLeft <= _best[i] && !faster) {
      return false;
    }
    if (livesLeft > _best[i]) {
      _best[i] = livesLeft;
    }
    if (faster) {
      _times[i] = ms;
    }
    await _save();
    return faster && hadTime;
  }

  /// For the Settings screen. Deliberately the only way to go backwards.
  Future<void> forget() async {
    _best.fillRange(0, levelCount, 0);
    _times.fillRange(0, levelCount, 0);
    await _save();
  }
}

/// The one of it. See [Progress]'s comment for why this is a global.
///
/// The volume settings used to live here too. They are in
/// `audio/audio_settings.dart` now, next to the thing that reads them.
final Progress progress = Progress();
