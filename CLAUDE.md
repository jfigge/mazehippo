# CLAUDE.md

## Git — hands off

**Never run `git add`, `git rm --cached`, `git commit` or `git stash`.** Staging
and committing are the user's, always. Leave work in the working tree and say
what changed. Reading the repo — `git status`, `diff`, `log`, `show`, `blame` —
is fine, as is `git checkout`/`branch` when the user asks for it.

## What this is

A tap-to-clear puzzle. A square lattice of dots with arrows wound through it;
tap one and it threads itself off the board in the direction it points, or runs
into another arrow's body, turns red and costs a life. Three lives. A hundred
levels.

The interesting part is not the tapping, it is that **there is no level data and
no solver**. Every level is computed from its number, and it is generated along
its own solution — see `src/lib/puzzle/generate.dart`, which is where to start
reading and the only place a level comes from.

Roll Hippo is the sibling project (`../rollhippo`) and this repository follows
its layout, its Makefile and its conventions deliberately.

## Commands

Run from the repo root:

| | |
|---|---|
| `make test` | the suites — headless, no device |
| `make analyze` | `flutter analyze --fatal-infos --fatal-warnings` |
| `make format` | `dart format lib test tool` |
| `make all` | format + analyze + test |
| `make ci` | format-check + analyze + test |
| `make levels` | print all hundred levels — size, arrows, moves offered, and how long each took to weave |
| `make board` | render levels into `/tmp/mazehippo/`: one per difficulty band, level 100 at 250%, and the frame the player sees after a wrong tap |
| `make boop` | redraw `assets/boop.wav` from `tool/boop.dart`. Writes into the project, not `/tmp` — the tool is the sound's source of record |
| `make icon` | draw the app icon into the iOS, macOS and Android catalogues. Writes into the project — the files it makes *are* the icon |
| `make audio` | re-render the soundtrack: synthesise the three waveforms, then level and encode them to OGG Vorbis with ffmpeg. Needs `ffmpeg` with `libvorbis`. Writes into the project |
| `make desktop` | run the macOS harness |
| `make ios` / `make android` | run on a phone, `--profile` |

Raw `flutter`/`dart` commands must run from `src/`, which is the package root.

## Layout, and the one invariant

```
src/lib/puzzle/    arrow (Dot · Heading · Arrow — pathDot is the movement) · board (Board · Slide · lane)
                   level (Grade · LevelPlan · Level) · generate (Rng · generateLevel)
                   puzzle.dart re-exports the four, so one import brings the lot
src/lib/render/    camera (BoardCamera — the fit, the pinch, the clamp, the hit test)
                   board_painter (BoardPainter · ArrowFrame · ArrowMood)
src/lib/audio/     ambience (Ambience — the bed, the flourish, the blips, one engine)
                   audio_settings (AudioSettings — two volumes, persisted)
src/lib/app/       title_screen (the front page) · level_picker (all hundred, in bands)
                   game_screen (the board: taps, lives, motion, the end-of-level panel)
                   chrome (gradeColour · Hearts · MenuButton · Panel — what the menus share)
                   store (Progress, and the global)
src/assets/        laser_soft.wav — an arrow leaving; the one thing here that was not drawn
                   boop.wav — an arrow stopped, written by tool/boop.dart
                   audio/pad.ogg (97s) · audio/ether.ogg (71s) · audio/solved.ogg
                   — the bed and the flourish, written by tool/ambience.dart
                   audio/bells.ogg (71s) — what the upper layer used to be, kept
                   mazehippo.svg — the app icon's drawing of record. Not shipped:
                   nothing loads it at run time, only tool/app_icon.dart reads it
src/test/          puzzle · level · camera · game · store · menu · audio_settings
                   ambience — headless, and silent: there is no audio platform under
                   `flutter test`, which is the state `Ambience` is built to survive
src/tool/          levels (prints) · board (renders into /tmp/mazehippo/)
                   boop (synthesises assets/boop.wav — writes into the project)
                   ambience (synthesises the three audio/ files — writes into the project)
                   app_icon (draws assets/mazehippo.svg into every platform's
                   catalogue — writes into the project)
```

**`lib/puzzle/` does not import Flutter**, only `dart:math`-free integer
arithmetic — no `dart:ui`, no `package:flutter`. That is what lets all hundred
levels be generated and solved in a headless test in under a second, and it is
what lets `game_screen.dart` hand generation to `Isolate.run` with nothing to
marshal. Flutter starts at `render/`.

## Conventions

- **Explicit types** on locals and collection literals — `final Dot head =`,
  `<Arrow>[…]`, `for (final Arrow arrow in arrows)`. `always_specify_types` and
  `prefer_final_locals` are on, so the analyser will say so.
- **Comments say why, at length, and are load-bearing.** Match the density of
  the surrounding file rather than trimming to a house style. No linter can
  check this one.
- `flutter_lints` with infos and warnings fatal, plus `src/analysis_options.yaml`
  and the three `strict-*` language modes. Analysis must come back clean.

## Traps

- **An arrow moves like a snake, so only one straight line of dots matters.**
  The head steps along its heading and the body threads up behind it, which
  means every dot the body will occupy is a dot the head has already passed. So
  `Board.lane` — the dots in front of the point, out to the edge — is the whole
  of the collision test, and a bend costs an arrow nothing. Do not reintroduce a
  swept-body test: that was the first implementation and it is a different, and
  wrong, game. `Arrow.pathDot` is the movement written down, and both the
  painter and `Board` read it.
- **An arrow may not point along its own body.** The head would land on a dot
  its own tail had not vacated. It takes three bends to wrap a body around in
  front of its own head and the generator draws at most two, so no generated
  level can contain one — but `Arrow` asserts it, because a hand-written arrow
  could, and it would move through itself rather than fail.
- **The arrow order is the solution, so it must never reach the player.**
  `Level.arrows` is placement order and its reverse clears the board. Anything
  the player can see that is derived from an arrow's index — a colour, a draw
  order, a z-order — gives the game away. `BoardPainter.colourOf` takes the
  colour from the head's *position* for exactly this reason.
- **A level cannot be dead-ended, and that is a theorem rather than a hope.**
  Removing an arrow can only free others, so a free arrow stays free; take any
  position and the latest-placed arrow still on it was free when it was placed
  onto a superset of that position. So there is always a move, a life is only
  ever lost to a wrong tap, and the game needs no undo to be fair. `Level`'s
  comment has the argument and `level_test.dart` plays it out at random.
- **The difficulty is one number and it is maintained, not searched for.**
  `Grade.branching` is how many arrows may be free at once — 4, 3, 2, 1 — and
  the generator holds the count there by requiring each placement past the first
  K to block exactly one currently-free arrow. Adding an arrow can never free
  another, which is why that arithmetic closes.
- **The ticker's clock restarts at zero every time it is started.** A motion
  stamped with `_now` from a previous run reads as not having begun, and the
  arrow stands still for as long as the last animation took — growing worse with
  every tap. `_GameScreenState._wake` zeroes `_now` before starting, and callers
  must wake the clock *before* stamping a motion against it. `game_test.dart`
  has the regression, and it is the only place the animation is observable at
  all: an arrow half way out is pixels, not widgets, so the test reads the
  frames handed to the painter.
- **Exit animation is linear, not eased-in.** An ease-in starts at zero
  velocity, so the arrow spends its first third visibly not leaving, which reads
  as the tap having missed.
- **97 and 71 are coprime and that is the whole soundtrack.** The two bed loops
  realign only every 6,887 seconds, which is why the music does not repeat
  inside a session. Anyone who "tidies" the lengths to match — or to 90 and 70,
  or to anything sharing a factor — has replaced a bed that does not repeat with
  one that repeats every minute and a half. It is stated at the top of both
  `lib/audio/ambience.dart` and `tool/ambience.dart` for that reason.
- **The audio engine starts on the way into the first puzzle, never at launch.**
  `GameScreen.initState` is the only caller of `Ambience.startBed`. Moving it to
  `main` would put an engine init and a hundred and seventy seconds of decode in
  front of every launch, to serve a title screen that makes no noise.
- **iOS needs its audio session set in `AppDelegate.swift`, not in Dart.**
  `flutter_soloud` does not set the category — its own miniaudio backend says the
  app is responsible — and the default one stops whatever the player already had
  playing and ignores the ring/silent switch. `.ambient` with `.mixWithOthers`
  answers both. Deleting it makes the game rude in a way no test will catch.
- **Never `SoLoud.instance.deinit()` on a lifecycle pause.** `Ambience.sleep`
  fades and pauses the handles; the engine stays up. Tearing it down and
  rebuilding costs a visible stutter on Android, and a player who switched away
  for ten seconds is a player who is coming back.
- **Levelling the audio uses a single linear gain, never `loudnorm` in its
  dynamic mode.** Dynamic normalisation rides the gain over the file, and a pad
  that loops seamlessly *because it is exactly periodic* stops being periodic the
  moment anything moves its level. `make audio` measures with `ebur128` and
  multiplies. Same reason the files are OGG and not MP3: Vorbis stores an exact
  sample count, where MP3's encoder padding puts a small gap at every loop point.
- **Nothing in `store.dart` or `audio_settings.dart` ever throws or refuses.**
  `Progress` and `AudioSettings` start at their defaults, `load()` fills them in if there is somewhere to load
  from, and a platform with no `shared_preferences` — every widget test — keeps
  the defaults. A game that would not start because it could not read a
  preference would be a worse game. It also means the tests need no mocking to
  run the real screens.
- **`Ambience` goes quiet rather than failing, and that is what makes the tests
  work.** There is no audio platform under `flutter test`: the engine will not
  start and no asset will load. `_failed` catches that once and every method
  after it is a no-op, so the widget tests run the real screens with the real
  audio object and no mock at all. Each asset is also loaded independently, so a
  build with one file missing loses that sound and keeps the others — a deleted
  `pad.ogg` costs the bed and not the arrows.
- **The upper layer of the bed is one constant.** `Ambience._shimmerAsset` picks
  between `ether.ogg` (high voices swelling past each other, what plays) and
  `bells.ogg` (struck bells, what it started as). Both are rendered by
  `make audio` and both ship, so going back is an edit and not a re-render.
  Whatever it points at must be 71 seconds.
- **The level clock starts on the first arrow *touched*, not when the level
  appears.** A board is read before it is played, and on a hard level for a good
  while; a clock started with the level would be timing the reading. A wrong tap
  starts it too — that is a move. `_GameScreenState._clock` is null until then,
  which is also what tells `RunningClock` there is nothing to show yet.
- **`RunningClock` repaints itself and nothing else.** The obvious way to show a
  timer is to rebuild the screen ten times a second, and on a 30 × 30 board that
  repaints nine hundred dots and fifty arrows to move one digit. It holds its own
  ticker.
- **A first finish is not a record.** `Progress.cleared` returns true only when
  there was already a time and this one beat it, which is what the panel's "new
  fastest time" hangs on. Hearts and time improve independently, so a scrappy
  fast run and a careful slow one each keep the half they won.
- **`Isolate.run` must not be handed a closure written in an instance method.**
  It would capture `this`, which is the `State`, which reaches the whole widget
  tree, which holds a `Completer` and is unsendable. It fails at run time with
  forty lines of `<- _parent in Instance of …` and no mention of the line that
  caused it. `_GameScreenState._weave` is static for this reason alone.
- **`Rng` is written out rather than taken from `dart:math`.** `Random(seed)` is
  deterministic but its algorithm is not part of Dart's contract, and the levels
  are computed rather than stored — so level 63 has to be the same tangle on
  every machine and every SDK. Changing `Rng` changes all hundred levels.
- **What limits how full a board can be is the shape of the *empty* part, not
  how much of it is covered.** An arrow can only be placed if the straight line
  in front of it is clear the whole way to the edge. An arrow dropped in open
  space cuts every row and column it lies across in half; one laid against an
  arrow already there costs almost nothing, because those lines were spent
  already. So `_placeOne` scores candidates by how much of each is touching
  something and takes the best of a shortlist rather than the first that works
  — and that one change took the biggest boards from 17% covered to 25% at the
  same arrow count. Scattering is what runs a board out of room.
- **Boards get harder to fill the bigger they are, and that is geometry.** The
  lane an arrow needs is as long as the board is wide, so the chance a random
  one is clear falls off with size. Measured: a 14 × 14 board packs to about
  60%, a 30 × 30 to about 40%, a 50 × 50 to about 25%. `arrowsAtBlock` is a
  table of measurements rather than a formula for that reason. A completely full
  board is impossible at any size — the free arrow needs somewhere to move.
- **The board stops growing at level 50, and the campaign plateaus because of
  it.** `LevelPlan.lastSize` holds it at 30 dots, which is the largest a phone
  can show at a size a finger can aim at. From level 46 the grade is already as
  hard as it goes, so past 50 the only remaining lever is arrow count — and a
  30 × 30 board with one free arrow holds about forty. The back half is fifty
  different tangles of much the same difficulty rather than a climb. Anyone
  asked to make it harder should be pointed at the three things that actually
  set it: board size, branching, and the three lives.
- **The generator's tuning is empirical and the numbers have reasons.** Aiming
  each candidate arrow at its nearest edge — the obvious way to raise the odds
  it can escape — was tried and made things *worse* (three levels short, three
  times the runtime), because an arrow pointed at the near edge reaches across
  less of the board and reaching across the board is its whole job. Biasing
  blockers towards the near end of the corridor they block was tried and made
  things much better, and also stopped the tangle collecting in a ring around an
  empty middle. Both findings are recorded where the code makes the choice.
- **The icon's magenta is written down in three places and they have to agree.**
  `kMarkMagenta` in `tool/app_icon.dart` is what the rasters are drawn with,
  `assets/mazehippo.svg` is the drawing of record, and
  `android/app/src/main/res/values/ic_launcher_background.xml` is the field an
  adaptive icon sits on — a colour resource rather than five rasters of the same
  flat magenta. Change one and the Android icon gets a hippo of one shade on a
  square of another, on API 26 and up only, which is the sort of thing that
  ships. `#CA2BAF` is Maze Hippo's slot in the Hippo Herd's one-colour-per-app
  system: hue 310, the only gap left between Rest at 246 and Roll at 351.
- **The Android monochrome layer cuts the face out rather than painting it.**
  Material You throws the colours away and tints whatever alpha is left, so
  magenta-on-white and white-on-white arrive as the same colour and the hippo
  turns up as a blank head. `_writeLayer` passes a `BlendMode.clear` paint for
  exactly this, which is also why it needs a `saveLayer` — against the bare
  canvas the clear would take the whole picture with it.
- **iOS rejects an icon that merely *has* an alpha channel.** Every pixel of the
  field is opaque already, but validation looks at the channel count rather than
  the pixels, and Flutter's encoder always writes one. `_opaquePng` re-encodes
  to three channels through the `image` package — the only reason that package
  is a dependency at all. The macOS icons keep their alpha, because the 824/1024
  margin Apple's grid asks for has to be see-through.
