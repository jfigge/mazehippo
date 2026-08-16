// The soundtrack, drawn.
//
// Three files nobody recorded: a pad, a scatter of bells, and the flourish a
// solved board gets. Synthesised for the same reason `tool/boop.dart` is — so
// the sound is something in the repository that can be read and adjusted rather
// than a binary nobody can account for. Run it with `make audio`, which also
// encodes the results to OGG Vorbis.
//
// **The loops are 97 and 71 seconds and that is the whole trick.** They share
// no factors, so the two layers line up again only every 97 × 71 = 6,887
// seconds — an hour and fifty-five minutes — and until then the player hears a
// combination of pad and bells they have not heard before. Two files under a
// megabyte apiece do the work of a generative engine. Making them the same
// length, or near it, would throw all of it away.
//
// Both have to loop without a seam, and they get there by different routes:
//
// * The pad has no transients, so it is built to be *exactly periodic*. Every
//   oscillator and every slow sweep in it completes a whole number of cycles in
//   97 seconds, which makes the last sample continuous with the first by
//   construction rather than by repair. There is no crossfade because there is
//   nothing to cross.
// * The bells cannot be, because a bell is a transient with a long tail and the
//   ones struck near the end are still ringing when the file runs out. So they
//   are rendered into a longer buffer and the overhang is added back onto the
//   beginning — the tail of the last bell is already sounding when the loop
//   starts again, which is what a room does.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int rate = 44100;

/// The two loop lengths. Coprime on purpose — see the file comment.
const double padSeconds = 97;
const double bellsSeconds = 71;

/// And the flourish, which is a one-shot and loops nowhere.
const double solvedSeconds = 4.2;

/// A pentatonic minor on A, in Hz, low to high. Pentatonic because there is no
/// interval in it that can sound wrong against any other, which is what lets
/// bells be scattered at random and still never clash with the pad.
const List<double> scale = <double>[
  110.00, // A2
  130.81, // C3
  146.83, // D3
  164.81, // E3
  196.00, // G3
  220.00, // A3
  261.63, // C4
  293.66, // D4
  329.63, // E4
  392.00, // G4
  440.00, // A4
  523.25, // C5
];

/// Where the uncompressed renders go. Not `assets/`: what ships is the OGG the
/// Makefile encodes from these, and a 14 MiB pile of WAVs sitting next to it
/// would be eight times the size of the app.
const String scratch = '/tmp/mazehippo/audio';

void main() {
  Directory(scratch).createSync(recursive: true);
  _write('$scratch/pad.wav', _pad());
  _write('$scratch/ether.wav', _ether());
  // Kept, and still rendered, though nothing plays it at the moment: the upper
  // layer is one constant in `lib/audio/ambience.dart` and this is the other
  // thing it can be set to. Cheaper to keep making than to have to remember how
  // it went. See [_bells].
  _write('$scratch/bells.wav', _bells());
  _write('$scratch/solved.wav', _solved());
}

/// The upper layer: high voices that swell past each other and never arrive.
///
/// This is what plays over the pad. It replaced a scatter of bells, and the
/// difference is transients — a bell is a struck thing, and struck things are
/// events, and events are what an ambient bed is trying not to have. Nothing
/// here starts; everything is already sounding and only its loudness moves.
///
/// Like [_pad] and unlike [_bells], it is **exactly periodic** over its 71
/// seconds, so it needs no overlap-add and has no wrap to repair. Every voice
/// and every swell completes a whole number of cycles in the loop.
///
/// The shimmer is beating rather than vibrato: each voice is two sines a few
/// cents apart, and what the ear hears is the slow throb between them. Detune
/// is also locked to the loop, so the throb is at the same point in its cycle
/// at 71 seconds as it was at zero.
List<double> _ether() {
  final int frames = (rate * bellsSeconds).round();
  final List<double> out = List<double>.filled(frames, 0);

  double lock(double hz) =>
      math.max(1, (hz * bellsSeconds).roundToDouble()) / bellsSeconds;

  // High, and pentatonic, so nothing in the cluster can be wrong against
  // anything else or against the chord underneath it.
  const List<double> voices = <double>[
    440.00, // A4
    523.25, // C5
    587.33, // D5
    659.25, // E5
    783.99, // G5
    880.00, // A5
    1046.50, // C6
  ];

  for (int v = 0; v < voices.length; v++) {
    // How many times this voice blooms in a loop. Small, different for each,
    // and coprime-ish among themselves so the cluster never blooms together —
    // which would be a swell, and a swell is an event.
    final double blooms = <double>[2, 3, 5, 3, 7, 5, 2][v];
    final double phase = <double>[0.0, 1.7, 3.1, 0.8, 2.4, 4.2, 5.5][v];
    // Higher voices sit further back, or the top of the cluster becomes a
    // whistle.
    final double weight = 0.9 / (1 + v * 0.85);

    for (final double cents in <double>[-5.0, 5.0]) {
      final double hz = lock(voices[v] * math.pow(2, cents / 1200));
      for (int i = 0; i < frames; i++) {
        final double t = i / rate;
        // Raised to a power so the voice spends most of its time near silence
        // and only briefly near full — which is what makes the cluster feel
        // like it is drifting rather than pulsing.
        final double bloom = math
            .pow(
              0.5 -
                  0.5 *
                      math.cos(2 * math.pi * blooms * t / bellsSeconds + phase),
              2.2,
            )
            .toDouble();
        final double angle = 2 * math.pi * hz * t;
        // A trace of the octave above, which is the whole of the glassiness.
        final double tone = math.sin(angle) + 0.08 * math.sin(2 * angle);
        out[i] += tone * bloom * weight;
      }
    }
  }
  return out;
}

/// Sustained chords, no transients, exactly periodic over [padSeconds].
///
/// Periodicity is the whole design. Every partial's frequency is rounded to a
/// whole number of cycles per loop, and so is every slow sweep that moves it —
/// so the waveform at 97 seconds is the waveform at 0, to the sample. A pad
/// built any other way needs a crossfade, and a crossfade on a sustained chord
/// is a slow flam you can hear once you know it is there.
List<double> _pad() {
  final int frames = (rate * padSeconds).round();
  final List<double> out = List<double>.filled(frames, 0);

  /// Rounds a frequency to a whole number of cycles per loop.
  double lock(double hz) =>
      math.max(1, (hz * padSeconds).roundToDouble()) / padSeconds;

  // Two chords a fifth apart, breathing in and out of each other. Neither ever
  // arrives, which is what keeps it from being a chord progression the player
  // can follow.
  const List<double> voicing = <double>[110.00, 164.81, 220.00, 329.63];
  const List<double> answer = <double>[130.81, 196.00, 261.63, 392.00];

  for (int v = 0; v < voicing.length; v++) {
    for (final bool second in <bool>[false, true]) {
      final double root = second ? answer[v] : voicing[v];
      // A little detune per voice, itself locked to the loop, so the pair beat
      // slowly against each other rather than sitting in perfect tune.
      for (final double cents in <double>[-4.0, 4.0]) {
        final double hz = lock(root * math.pow(2, cents / 1200));
        // Where in its own cycle this voice starts. Spread so nothing lines up
        // at zero and gives the loop an audible downbeat.
        final double phase = (v * 0.37 + (second ? 0.61 : 0)) * 2 * math.pi;
        // How fast it breathes: a whole number of cycles per loop, and a
        // different number for every voice, so the crowd never swells together.
        final double swellCycles = second ? 2.0 + v : 3.0 + v * 2;
        final double swellPhase = v * 1.1 + (second ? 2.2 : 0);

        for (int i = 0; i < frames; i++) {
          final double t = i / rate;
          final double swell =
              0.5 -
              0.5 *
                  math.cos(
                    2 * math.pi * swellCycles * t / padSeconds + swellPhase,
                  );
          // Sine plus a whisper of the octave. Anything richer starts to sound
          // like an instrument, and an instrument is something you listen to.
          final double angle = 2 * math.pi * hz * t + phase;
          final double tone = math.sin(angle) + 0.14 * math.sin(2 * angle);
          // Higher voices further back, so the chord sits under everything.
          out[i] += tone * swell * (0.9 / (1 + v * 1.4));
        }
      }
    }
  }
  return out;
}

/// Sparse bells over silence, wrapped so the last one is still ringing when the
/// first comes round again.
///
/// **Not currently used.** [_ether] took over the upper layer; this is kept
/// because going back is one constant in `lib/audio/ambience.dart` and because
/// the overlap-add below is the only place in the repository that shows how to
/// wrap a loop that *does* have transients in it.
List<double> _bells() {
  final int frames = (rate * bellsSeconds).round();
  // Long enough for the last strike to die away completely inside the buffer.
  const double tail = 9.0;
  final int overrun = (rate * tail).round();
  final List<double> long = List<double>.filled(frames + overrun, 0);

  // A fixed stream, so the file is the same file every time it is rendered.
  final _Rng rng = _Rng(0x5EED17);

  // About one strike every three and a half seconds. Sparse enough that the ear
  // never gets a rhythm to hold on to.
  double at = 0;
  while (at < bellsSeconds) {
    final double hz = scale[4 + rng.nextInt(scale.length - 4)];
    final double level = 0.35 + 0.4 * rng.nextDouble();
    _strike(long, at, hz, level);
    at += 2.2 + 3.0 * rng.nextDouble();
  }

  // The overlap-add: whatever is still sounding past the end is folded onto the
  // beginning. After this the buffer is a loop rather than a clip — the wrap has
  // no gap and no second attack, because the tail arriving at 0 is the same tail
  // that was leaving at 71.
  final List<double> out = long.sublist(0, frames);
  for (int i = 0; i < overrun; i++) {
    out[i % frames] += long[frames + i];
  }
  return out;
}

/// One bell: a struck partial series with a soft attack and a long decay.
void _strike(List<double> out, double when, double hz, double level) {
  final int start = (rate * when).round();
  // Inharmonic-ish, which is what makes it a bell and not an organ.
  const List<double> partials = <double>[1.0, 2.01, 2.99, 4.21];
  const List<double> weights = <double>[1.0, 0.45, 0.22, 0.09];
  // Higher partials die away first, exactly as they do on metal.
  const List<double> decays = <double>[3.6, 2.2, 1.4, 0.9];

  for (int p = 0; p < partials.length; p++) {
    final double f = hz * partials[p];
    final double tau = decays[p];
    final int span = math.min((rate * tau * 4).round(), out.length - start);
    for (int i = 0; i < span; i++) {
      final double t = i / rate;
      // A few milliseconds of rise rather than a step, so there is no click.
      final double rise = t < 0.004 ? t / 0.004 : 1;
      out[start + i] +=
          math.sin(2 * math.pi * f * t) *
          math.exp(-t / tau) *
          rise *
          weights[p] *
          level;
    }
  }
}

/// The flourish a solved board gets: four notes up the scale, each ringing on
/// over the next, arriving rather than stopping.
List<double> _solved() {
  final int frames = (rate * solvedSeconds).round();
  final List<double> out = List<double>.filled(frames, 0);
  const List<double> rising = <double>[220.00, 293.66, 329.63, 440.00];
  for (int n = 0; n < rising.length; n++) {
    // Accelerating slightly, which reads as arrival rather than as a scale.
    _strike(out, 0.11 * n * n + 0.16 * n, rising[n], 0.5 + 0.16 * n);
  }
  return out;
}

/// Write a buffer as 16-bit mono PCM, normalised to just under full scale. The
/// levelling proper is done afterwards by ffmpeg against a measured LUFS
/// target — see the Makefile — because loudness is a perceptual measurement and
/// not something to guess at from a peak.
void _write(String path, List<double> wave) {
  double loudest = 0;
  for (final double sample in wave) {
    loudest = math.max(loudest, sample.abs());
  }
  final double gain = loudest == 0 ? 0 : 0.89 * 32767 / loudest;

  final Int16List samples = Int16List(wave.length);
  for (int i = 0; i < wave.length; i++) {
    samples[i] = (wave[i] * gain).round().clamp(-32768, 32767);
  }

  File(path).writeAsBytesSync(_riff(samples));
  print(
    'wrote $path — ${(wave.length / rate).toStringAsFixed(1)}s, '
    '${(samples.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MiB pcm',
  );
}

Uint8List _riff(Int16List samples) {
  final int dataBytes = samples.length * 2;
  final ByteData header = ByteData(44);
  void tag(int at, String four) {
    for (int i = 0; i < 4; i++) {
      header.setUint8(at + i, four.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  header.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);

  final BytesBuilder out = BytesBuilder()
    ..add(header.buffer.asUint8List())
    ..add(samples.buffer.asUint8List(0, dataBytes));
  return out.takeBytes();
}

/// xorshift32, the same one `lib/puzzle/generate.dart` uses and for the same
/// reason: the scatter of bells has to be the same scatter on every machine.
class _Rng {
  _Rng(int seed) : _state = seed & 0xffffffff;
  int _state;

  int _next() {
    int x = _state;
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    _state = x;
    return x;
  }

  int nextInt(int bound) => _next() % bound;
  double nextDouble() => _next() / 0x100000000;
}
