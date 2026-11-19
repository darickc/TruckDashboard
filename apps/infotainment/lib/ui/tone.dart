import 'package:flutter/widgets.dart';

import 'theme.dart';

/// What a status says about itself, mapped to a palette colour by the
/// widget so the derivations stay plain data (and testable): Home's
/// buttons, Settings › System's services.
enum HomeTone { ok, advisory, critical, stale, accent, simulated, text, dim }

Color homeToneColor(HomeTone t, Palette p) => switch (t) {
  HomeTone.ok => p.ok,
  HomeTone.advisory => p.advisory,
  HomeTone.critical => p.critical,
  HomeTone.stale => p.stale,
  HomeTone.accent => p.accent,
  HomeTone.simulated => p.simulated,
  HomeTone.text => p.text,
  HomeTone.dim => p.textDim,
};
