// What the game remembers, and what it does when there is nowhere to remember
// it.

import 'package:flutter_test/flutter_test.dart';
import 'package:mazehippo/app/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('Progress', () {
    test('starts a new player at level 1 with nothing behind them', () async {
      final Progress fresh = Progress();
      await fresh.load();
      expect(fresh.clearedCount, 0);
      expect(fresh.unlocked, 1);
      expect(fresh.isUnlocked(1), isTrue);
      expect(fresh.isUnlocked(2), isFalse);
      expect(fresh.bestLives(1), 0);
    });

    test('unlocks the level after the furthest one cleared', () async {
      final Progress p = Progress();
      await p.cleared(1, 3, const Duration(seconds: 30));
      await p.cleared(2, 1, const Duration(seconds: 30));
      expect(p.unlocked, 3);
      expect(p.isUnlocked(3), isTrue);
      expect(p.isUnlocked(4), isFalse);
      // Clearing out of order — which the picker allows for a replay — moves
      // the frontier to the furthest, not to the latest.
      await p.cleared(9, 2, const Duration(seconds: 30));
      expect(p.unlocked, 10);
    });

    test('keeps the best result and never a worse one', () async {
      final Progress p = Progress();
      await p.cleared(5, 1, const Duration(seconds: 30));
      expect(p.bestLives(5), 1);
      await p.cleared(5, 3, const Duration(seconds: 30));
      expect(p.bestLives(5), 3);
      // Replaying badly must not take the three hearts away.
      await p.cleared(5, 1, const Duration(seconds: 30));
      expect(p.bestLives(5), 3);
    });

    test('survives a relaunch', () async {
      final Progress before = Progress();
      await before.cleared(1, 3, const Duration(seconds: 30));
      await before.cleared(2, 2, const Duration(seconds: 30));
      await before.cleared(7, 1, const Duration(seconds: 30));

      final Progress after = Progress();
      await after.load();
      expect(after.bestLives(1), 3);
      expect(after.bestLives(2), 2);
      expect(after.bestLives(7), 1);
      expect(after.isCleared(3), isFalse);
      expect(after.clearedCount, 3);
    });

    test('records a time, and only a faster one after that', () async {
      final Progress p = Progress();
      expect(p.bestTime(3), isNull);

      // The first finish is not a record — there was nothing to break — so it
      // stores the time and answers no.
      expect(await p.cleared(3, 2, const Duration(seconds: 40)), isFalse);
      expect(p.bestTime(3), const Duration(seconds: 40));

      // Slower leaves it alone.
      expect(await p.cleared(3, 2, const Duration(seconds: 55)), isFalse);
      expect(p.bestTime(3), const Duration(seconds: 40));

      // Faster takes it, and says so.
      expect(await p.cleared(3, 1, const Duration(seconds: 21)), isTrue);
      expect(p.bestTime(3), const Duration(seconds: 21));
    });

    test('improves hearts and time independently', () async {
      // A scrappy fast run and a careful slow one each keep the half they won.
      final Progress p = Progress();
      await p.cleared(4, 3, const Duration(seconds: 90));
      await p.cleared(4, 1, const Duration(seconds: 20));
      expect(p.bestLives(4), 3);
      expect(p.bestTime(4), const Duration(seconds: 20));
    });

    test('carries times across a relaunch', () async {
      final Progress before = Progress();
      await before.cleared(2, 3, const Duration(milliseconds: 12345));

      final Progress after = Progress();
      await after.load();
      expect(after.bestTime(2), const Duration(milliseconds: 12345));
      expect(after.bestTime(3), isNull);
    });

    test('forgets everything when asked, and only then', () async {
      final Progress p = Progress();
      await p.cleared(1, 3, const Duration(seconds: 30));
      await p.forget();
      expect(p.clearedCount, 0);
      expect(p.unlocked, 1);
      expect(p.bestTime(1), isNull);

      final Progress after = Progress();
      await after.load();
      expect(after.clearedCount, 0);
    });

    test('caps the last level rather than unlocking past the end', () async {
      final Progress p = Progress();
      await p.cleared(Progress.levelCount, 3, const Duration(seconds: 30));
      expect(p.unlocked, Progress.levelCount);
      expect(p.next, Progress.levelCount);
    });

    test('ignores a stored string that has been damaged', () async {
      // Not a hypothetical: it is a preference, and preferences outlive the
      // code that wrote them. Anything that is not a digit 0-3 is skipped
      // rather than trusted, and the rest of the string still loads.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'progress': '3x9-2',
      });
      final Progress p = Progress();
      await p.load();
      expect(p.bestLives(1), 3);
      expect(p.bestLives(2), 0);
      expect(p.bestLives(3), 0);
      expect(p.bestLives(5), 2);
    });
  });
}
