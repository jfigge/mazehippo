/// The game, with no Flutter in it.
///
/// Everything under `lib/puzzle/` is integer lattice arithmetic and nothing
/// else — it imports neither `dart:ui` nor anything from `package:flutter`, and
/// that is worth defending rather than merely noticing. It is what lets a
/// hundred levels be generated and solved in a headless test in under a second,
/// with no device, no display and no frame.
///
/// One import brings the lot.
library;

export 'arrow.dart';
export 'board.dart';
export 'generate.dart';
export 'level.dart';
