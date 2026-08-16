// The boop, drawn.
//
// The sound an arrow makes when it runs into another one, synthesised rather
// than sourced — so it is a hundred lines that can be read and adjusted rather
// than a binary nobody can account for. `assets/boop.wav` is the output; this
// is the drawing of record. Run it with `make boop`.
//
// It has one job and two constraints. It is heard far more often than the laser
// — a wrong tap is the thing the player is being told about — so it has to be
// short enough not to be in the way, and soft enough not to be a punishment.
// Ninety milliseconds against the laser's two hundred and twenty, and a peak a
// little under it.
//
// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Everything with a number in it.
const int rate = 44100;

/// Shorter than the laser on purpose. See the file comment.
const double seconds = 0.09;

/// Where the pitch settles, and how far above it the boop starts. The drop is
/// what makes it read as *no* rather than as a notification: a tone that falls
/// is a tone that has given up.
const double settleHz = 300;
const double dropHz = 220;

/// How fast it falls. Quick enough that the glide is heard as a shape rather
/// than as a slide.
const double glideTau = 0.018;

/// A little of the second harmonic, for body. A pure sine at this length is a
/// dot rather than a boop.
const double secondHarmonic = 0.22;

/// Raised-cosine attack, exponential decay, raised-cosine taper. The taper is
/// not decoration: at 90 ms the decay has only reached a twentieth, and cutting
/// a wave off at a twentieth of full scale is a click.
const double attack = 0.003;
const double decayTau = 0.030;
const double taper = 0.010;

/// Peak, as a fraction of full scale. The laser measures 0.55; this sits just
/// under it, because it is the sound of getting it wrong and should not be the
/// loudest thing in the game.
const double peak = 0.48;

void main() {
  final int frames = (rate * seconds).round();
  final List<double> wave = List<double>.filled(frames, 0);

  double phase = 0;
  for (int i = 0; i < frames; i++) {
    final double t = i / rate;
    final double hz = settleHz + dropHz * math.exp(-t / glideTau);
    phase += 2 * math.pi * hz / rate;

    final double shape = math.sin(phase) + secondHarmonic * math.sin(2 * phase);

    final double rise = t < attack
        ? 0.5 - 0.5 * math.cos(math.pi * t / attack)
        : 1;
    final double fall = math.exp(-t / decayTau);
    final double left = seconds - t;
    final double out = left < taper
        ? 0.5 - 0.5 * math.cos(math.pi * left / taper)
        : 1;

    wave[i] = shape * rise * fall * out;
  }

  // Normalised at the end rather than balanced by hand: the harmonic and the
  // envelope both move the peak around, and the number that matters is the one
  // that comes out.
  double loudest = 0;
  for (final double sample in wave) {
    loudest = math.max(loudest, sample.abs());
  }
  final double gain = peak * 32767 / loudest;

  final Int16List samples = Int16List(frames);
  double sumOfSquares = 0;
  for (int i = 0; i < frames; i++) {
    final double scaled = wave[i] * gain;
    samples[i] = scaled.round().clamp(-32768, 32767);
    sumOfSquares += samples[i] * samples[i];
  }

  final File file = File('assets/boop.wav');
  file.writeAsBytesSync(_riff(samples));
  print('wrote ${file.path}');
  print('  ${(1000 * seconds).round()} ms, $rate Hz, mono, 16-bit');
  print(
    '  peak ${(peak * 100).round()}% of full scale, '
    'rms ${(100 * math.sqrt(sumOfSquares / frames) / 32768).toStringAsFixed(1)}%',
  );
}

/// A RIFF/WAVE wrapper for 16-bit mono PCM.
Uint8List _riff(Int16List samples) {
  final int dataBytes = samples.length * 2;
  final BytesBuilder out = BytesBuilder();
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
  header.setUint32(16, 16, Endian.little); // PCM header length
  header.setUint16(20, 1, Endian.little); // uncompressed
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * 2, Endian.little); // bytes per second
  header.setUint16(32, 2, Endian.little); // bytes per frame
  header.setUint16(34, 16, Endian.little); // bits per sample
  tag(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);

  out.add(header.buffer.asUint8List());
  out.add(samples.buffer.asUint8List(0, dataBytes));
  return out.takeBytes();
}
