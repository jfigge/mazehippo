# Maze Hippo

Arrows wound through a grid of dots. Tap one and it threads itself off the
board the way it points — or runs into another arrow's body, turns red, and
costs one of three lives. A hundred levels, from a 14 × 14 board with
twenty-two arrows to a 30 × 30 board with thirty-eight.

Two decisions are the whole of how it works.

## An arrow moves like a snake

The head takes one step along the direction it points, and every other dot moves
up onto the one in front of it. The body threads itself along the line the head
has already travelled. It does not translate rigidly and it does not drag its
bends sideways through the board.

Everything else follows from that. **Whether an arrow can leave depends on one
straight line of dots — the ones in front of its point, out to the edge — and on
nothing else.** Its own bends cost it nothing, because every dot the body will
pass through is a dot the head has already been through and found empty. A
four-bend arrow tucked into a corner is under no more threat than a straight one
of the same reach.

That is why the dots are drawn. The player sights down the line in front of an
arrowhead and reads off whether anything crosses it — and because the arrows run
along the dots, "crosses it" is something you can see rather than estimate. Two
axis-aligned unit-lattice polylines can only ever meet *at* a dot, so the picture
and the rule are the same thing, and the collision test is a set membership check
rather than an approximation of one.

## The levels are generated backwards

There is no level data in this repository and no solver in it either. A level is
computed from its number, and the trick is the direction.

Place arrows one at a time, each with a clear lane to the edge past everything
already placed. Then **the reverse of the placement order is a solve**: when an
arrow was put down, its run was clear of exactly the arrows that are still on
the board when its turn comes to be lifted. No search, no verification pass —
the level is generated along its own solution.

The difficulty falls out of the same construction. What makes one of these
puzzles hard is not its size but how many arrows can leave at any moment: at
four the player nearly always has an obvious move, and at one there is never a
choice, so every tap is a claim about the whole tangle. Adding an arrow can
never free another one — it is one more obstacle, not one fewer — so the count
of free arrows only moves by the arrow being added and by whichever free arrows
that arrow blocks. Require each placement to block exactly one free arrow and
the count holds where it was put. Ten easy levels hold it at four, fifteen
moderate at three, twenty difficult at two, and the last fifty-five at one.

One more thing comes free. Removing an arrow can only free others, so an arrow
that is free stays free — and the latest-placed arrow still on any position the
player has reached was free when it was placed onto a superset of that position.
So it is free now. **There is always a move, whatever order the player plays
in.** A level can never be dead-ended, a life is only ever lost to a wrong tap,
and the game needs no undo to be fair.

## How full a board can get

Not completely full, and the reason is the game rather than the generator: the
arrow that is about to leave needs an empty line in front of it to leave along,
and every other arrow needs something *on* its line so that there is a puzzle at
all. A board with no empty dots has no moves.

Short of that, what limits it is the shape of the empty part rather than the
size of it. An arrow dropped into open space cuts every row and column it lies
across in half; one laid against an arrow already there costs almost nothing,
because those lines were spent already. So the generator prefers candidates that
touch what is already down, and the boards pack instead of scattering — worth
about half as many arrows again on the large boards, at no cost anywhere.

The rest is geometry. The line an arrow needs is as long as the board is wide,
so big boards are harder to fill than small ones however cleverly it is done: a
14 × 14 board packs to about 60% of its dots, a 30 × 30 to about 40%. That is
why the arrow counts are a table of measurements rather than a formula.

The board grows for the first fifty levels and then holds at 30 × 30, which is
the largest a phone can show at a size a finger can aim at. The second half of
the campaign gets its difficulty from the two things that do not cost
legibility — one free arrow rather than two, and more arrows in the same square
— rather than from getting bigger and further away.

## The soundtrack does not repeat

Two loops play under the game at once: a pad of 97 seconds and a layer of high
voices over it of 71. They share no factors, so the pair line up again only every
97 × 71 = 6,887 seconds — an hour and fifty-five minutes — and until then the
player keeps hearing combinations of the two they have not heard before. Two
files totalling under half a megabyte do the work of a generative engine.

**The mismatch is the mechanism.** Rounding the lengths towards each other, or
to something tidy, turns a bed that does not repeat inside any plausible sitting
into one that repeats every minute and a half.

Both are synthesised rather than recorded — `src/tool/ambience.dart` is their
source of record and `make audio` renders them — and they reach a seamless wrap
by different routes. The pad has no transients, so it is built to be *exactly
periodic*: every oscillator and every slow sweep completes a whole number of
cycles in 97 seconds, which makes the last sample continuous with the first by
construction rather than by repair. The upper layer is built the same way, and for the same reason: nothing in it
starts, so there is nothing to cross-fade. It replaced a scatter of struck
bells, which could not be periodic — a bell is a transient with a long tail — and
which wrapped instead by being rendered into a longer buffer and having the
overhang folded back onto the beginning. That render is still in the repository
and still ships, because swapping back is one constant in
`src/lib/audio/ambience.dart`.

Nothing about the audio happens at launch. The engine starts, and the loops are
decoded, on the way into the first puzzle — which is the first thing that needs
a sound.

## Running it

`make desktop` for the macOS harness, `make ios` or `make android` for a phone.

**Linux needs `libasound2-dev`** installed before it will build — `flutter_soloud`
links ALSA. `sudo apt install libasound2-dev`. Nothing else has a system
dependency. Note that only iOS, Android and macOS are set up in this checkout;
Linux and Windows would need `flutter create --platforms=linux,windows .` run in
`src/` first.
`make levels` prints all hundred; `make board` draws a few into `/tmp/mazehippo/`.
`make all` formats, analyses and tests.

Pinch to zoom between 50% and 400%, drag to pan. The tangle cannot be pushed off
the screen. An arrow leaving makes a noise; four players take it in turns, so a
quick run of taps sounds like a quick run of taps rather than one clipped
noise.
