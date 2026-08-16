# Maze Hippo — arrows out of a maze.
#
# The app lives in src/, matching Roll Hippo's layout.

SRC      := src
SCRATCH  ?= /tmp/mazehippo
AUDIO    ?= /tmp/mazehippo/audio
DEVICE   ?= 00008110-000414C63A51401E   # Jason's iPhone
BUNDLE   := com.mazehippo.mazehippo

# Where hippoherd is checked out. Maze Hippo has no site of its own, so
# hippoherd.com/mazehippo IS its site and `website/` here is where it is
# written; `make site` is the one direction that copy ever goes. Same default
# and same override as Roll Hippo's Makefile, which does the same thing.
HERD     ?= $(CURDIR)/../../../js/projects/hippoherd

.PHONY: help all ci format format-check analyze test desktop ios launch android levels board boop icon audio site site-images clean

help:  ## Show this help
	@grep -E '^[a-z0-9-]+:.*?## ' $(firstword $(MAKEFILE_LIST)) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

all: format analyze test  ## Format, analyse and test

ci: format-check analyze test  ## What CI checks, minus the builds
	@# The same three things in the same order, differing from `all` in one
	@# way and on purpose: it checks the formatting rather than applying it.

format:  ## Format all Dart sources
	cd $(SRC) && dart format lib test tool

format-check:  ## Report formatting drift instead of fixing it
	cd $(SRC) && dart format --output=none --set-exit-if-changed lib test tool

analyze:  ## Static analysis, warnings fatal
	cd $(SRC) && flutter analyze --fatal-infos --fatal-warnings

test:  ## The puzzle suite — headless, no device
	@# Every one of the hundred levels is generated and solved here. That is
	@# the whole safety net under `generate.dart`: the generator is the only
	@# thing that decides what a level is, so a level it gets wrong is a level
	@# nobody can finish, and this is where that gets caught.
	cd $(SRC) && flutter test

audio:  ## Re-render the soundtrack: pad, upper layer and the solve flourish
	@# Two steps, because they need different tools. `tool/ambience.dart`
	@# synthesises the waveforms — see the comment at the top of it for why the
	@# loops are 97 and 71 seconds and why that is the entire mechanism — and
	@# ffmpeg does the levelling and the encoding.
	@#
	@# The levelling is a **single linear gain** against a measured figure, never
	@# ffmpeg's `loudnorm` in its dynamic mode. Dynamic normalisation moves the
	@# gain around over the file, and a pad that loops seamlessly because it is
	@# exactly periodic stops being exactly periodic the moment something rides
	@# its level. Measure, multiply, encode.
	@#
	@# OGG Vorbis rather than MP3, and not by taste: Vorbis stores an exact
	@# sample count, so a 97-second loop decodes to 97 seconds. MP3's encoder
	@# padding puts a few milliseconds of silence at the end of every file, which
	@# is a gap at every single loop point.
	cd $(SRC) && dart run tool/ambience.dart
	@$(MAKE) --no-print-directory audio-encode

.PHONY: audio-encode
audio-encode:
	@set -e; \
	cd $(SRC); \
	lufs() { ffmpeg -hide_banner -nostats -i "$$1" -af ebur128 -f null - 2>&1 \
	  | grep -E '^[[:space:]]+I:' | tail -1 | awk '{print $$2}'; }; \
	peak() { ffmpeg -hide_banner -nostats -i "$$1" -af ebur128=peak=true -f null - 2>&1 \
	  | grep -E '^[[:space:]]+Peak:' | tail -1 | awk '{print $$2}'; }; \
	for pair in pad:-20 ether:-26 bells:-26; do \
	  f=$${pair%:*}; target=$${pair#*:}; \
	  have=$$(lufs $(AUDIO)/$$f.wav); \
	  gain=$$(python3 -c "print(round($$target - ($$have), 2))"); \
	  echo "  $$f: $$have LUFS -> $$target LUFS ($$gain dB)"; \
	  ffmpeg -hide_banner -loglevel error -y -i $(AUDIO)/$$f.wav \
	    -af "volume=$${gain}dB" -c:a libvorbis -q:a 5 assets/audio/$$f.ogg; \
	done; \
	have=$$(peak $(AUDIO)/solved.wav); \
	gain=$$(python3 -c "print(round(-6.6 - ($$have), 2))"); \
	echo "  solved: peak $$have dBFS -> -6.6 dBFS ($$gain dB)"; \
	ffmpeg -hide_banner -loglevel error -y -i $(AUDIO)/solved.wav \
	  -af "volume=$${gain}dB" -c:a libvorbis -q:a 5 assets/audio/solved.ogg; \
	ls -l assets/audio/*.ogg

boop:  ## Redraw assets/boop.wav from tool/boop.dart
	@# The sound an arrow makes when it is stopped, synthesised rather than
	@# sourced — so it is code that can be read and adjusted rather than a
	@# binary nobody can account for. Writes into the project, not /tmp.
	cd $(SRC) && dart run tool/boop.dart

icon:  ## Draw the app icon into the iOS, macOS and Android catalogues
	@# Writes into the project, not /tmp: the files it makes are the icon.
	@# `assets/mazehippo.svg` is the drawing of record and tool/app_icon.dart
	@# is that file transcribed onto a canvas — change both together.
	cd $(SRC) && flutter test tool/app_icon.dart

board:  ## Render levels to /tmp/mazehippo/ — one per band, zoomed, and a wrong tap
	@# A painter is checked by looking at it. Run via `flutter test` rather
	@# than `dart run` because it needs dart:ui to rasterise.
	cd $(SRC) && flutter test tool/board.dart

site-images:  ## Redraw website/images/ from the real painter
	@# The pictures on hippoherd.com/mazehippo, drawn by the game rather than
	@# captured from it. Writes into the project, not /tmp: those files are
	@# what `make site` publishes, so they are tracked and this is how they
	@# are redrawn. The absolute path is not decoration — a `flutter test`
	@# runs with its working directory at $(SRC), and the website is a level
	@# above that.
	cd $(SRC) && WEBSITE_OUT=$(CURDIR)/website flutter test tool/website.dart
	@echo '→ website/images/'

site: site-images  ## Copy the site into hippoherd's Maze Hippo page
	@# hippoherd's generator leaves that one page alone rather than
	@# overwriting it; see `externalSite` in its content/hippos.mjs, which is
	@# what makes this safe. Depends on site-images so that what is published
	@# is what the current painter draws — the pictures going stale silently
	@# is the one failure this whole arrangement exists to prevent.
	@test -d "$(HERD)" || { \
	  echo "make site: no hippoherd checkout at $(HERD)"; \
	  echo "  Clone jfigge/hippoherd beside this repo, or pass HERD=<path>."; \
	  exit 1; }
	@# --exclude .DS_Store because Finder leaves one in any directory it has
	@# been asked to show, and it would otherwise be published and committed.
	rsync -a --delete --exclude .DS_Store website/ "$(HERD)/website/mazehippo/"
	@echo "→ $(HERD)/website/mazehippo/"
	@echo "  Commit and push there; the Pages workflow deploys it."

levels:  ## Print every level's shape — size, arrows, branching factor
	@# What `make test` asserts, written out to be read rather than checked.
	@# Useful when tuning the difficulty bands: the last column is the number
	@# of arrows free at the start, which is the whole of what makes a level
	@# easy or hard.
	cd $(SRC) && dart run tool/levels.dart

desktop:  ## Run the macOS harness — the board, mouse-driven
	cd $(SRC) && flutter run -d macos

ios:  ## Build and install on the iPhone
	@# --profile rather than debug. The board is repainted every frame while
	@# anything is moving and a level is woven on an isolate on the way in;
	@# debug's JIT is not the shipping feel of either.
	@#
	@# Installed with `xcrun devicectl`, **never `flutter install`** — that one
	@# uninstalls the old copy first and cannot be told not to, and an
	@# uninstalled iOS app takes its container with it — and since `Progress`
	@# lives in that container, that is every level the player has cleared.
	@# Same reasoning as Roll Hippo's, same command.
	cd $(SRC) && flutter build ios --profile
	@# Absolute, via CURDIR. devicectl resolves a relative path against its own
	@# sandbox rather than the shell's working directory, and what it reports
	@# when it cannot find it is a bookmark-and-entitlements error that reads
	@# like a signing problem and is not one.
	xcrun devicectl device install app --device $(DEVICE) \
	  $(CURDIR)/$(SRC)/build/ios/iphoneos/Runner.app
	@# Fails if the phone is locked, which is not a build problem — unlock it
	@# and either tap the icon or run `make launch`.
	-$(MAKE) launch

launch:  ## Launch the installed app on the iPhone
	xcrun devicectl device process launch --device $(DEVICE) $(BUNDLE)

android:  ## Run on the Android phone
	cd $(SRC) && flutter run --profile

clean:  ## Remove build output and the scratch directory
	cd $(SRC) && flutter clean
	rm -rf $(SCRATCH)
