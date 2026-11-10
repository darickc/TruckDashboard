import 'package:flutter/material.dart';

import '../core/settings.dart';

/// Target panel: original Raspberry Pi 7" touchscreen, 800×480. The UI is
/// laid out in logical pixels equal to physical pixels on the target
/// (devicePixelRatio 1.0; confirm the flutter-auto setting in Phase 5).
const kScreenSize = Size(800, 480);
const kStatusBarHeight = 44.0;
const kNavBarHeight = 64.0;
const kAlertBannerHeight = 52.0;

/// Camera mode's button column (shell/camera_mode.dart). The camera window
/// fills the rest below the status bar: x 220, y 44, 580×435, the
/// activation area in agl/flutter/config.toml (one row short of the bottom:
/// the compositor ignores an area that reaches it). make agl-test checks
/// they agree. 580×435 is a 4:3 picture.
const kCameraControlsWidth = 220.0;

/// Minimum touch target: 60 px ≈ 11 mm on this panel (docs/safety/assumptions.md).
const kMinTouch = 60.0;

const kGap = 8.0;

/// Semantic colours. Status colours carry meaning, so they are defined once
/// and used everywhere: a warning never looks different on two screens.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textDim,
    required this.accent,
    required this.ok,
    required this.advisory,
    required this.critical,
    required this.stale,
    required this.simulated,
  });

  final Color background, surface, surfaceHigh, border, text, textDim, accent;
  final Color ok, advisory, critical, stale, simulated;

  static const night = Palette(
    background: Color(0xFF0B0D10),
    surface: Color(0xFF151A20),
    surfaceHigh: Color(0xFF1F2630),
    border: Color(0xFF2B3440),
    text: Color(0xFFE8EAED),
    textDim: Color(0xFF8C939D),
    accent: Color(0xFF58A6FF),
    ok: Color(0xFF3DDC84),
    advisory: Color(0xFFFFB020),
    critical: Color(0xFFFF4D4D),
    stale: Color(0xFF7A828C),
    simulated: Color(0xFFB98BFF),
  );

  static const day = Palette(
    background: Color(0xFFEEF0F3),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF5F6F8),
    border: Color(0xFFD3D8DF),
    text: Color(0xFF111827),
    textDim: Color(0xFF4B5563),
    accent: Color(0xFF1D6FD8),
    ok: Color(0xFF15803D),
    advisory: Color(0xFFB45309),
    critical: Color(0xFFC81E1E),
    stale: Color(0xFF6B7280),
    simulated: Color(0xFF7C3AED),
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

ThemeData buildTheme(DayNight mode) {
  final p = mode == DayNight.night ? Palette.night : Palette.day;
  final base = mode == DayNight.night ? ThemeData.dark() : ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    colorScheme: base.colorScheme.copyWith(primary: p.accent, surface: p.surface),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    extensions: [p],
  );
}

/// Numerals with fixed-width digits, so values don't jitter as they change.
const tabular = [FontFeature.tabularFigures()];
