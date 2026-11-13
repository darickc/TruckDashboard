import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
// The patched function lives in the renderer's src (F250_PATCH.md).
// ignore: implementation_imports
import 'package:vector_tile_renderer/src/features/symbol_line_renderer.dart' show rightSideUpAngle;

/// Road names on the turned map (heading up, ADR-0032): the vendored
/// vector_tile_renderer keeps a line label right side up on the *screen*.
/// The renderer draws a label with `canvas.rotate(-angle)` inside a layer
/// turned clockwise by the map's rotation, so on the screen it sits at
/// `rotation - angle` (clockwise). `[SIM]`.
void main() {
  const deg = pi / 180;
  // Upstream's tolerance: flipped beyond 90° + 3°.
  const upright = 93 * deg + 1e-9;

  double wrap(double a) {
    var r = a % (2 * pi);
    if (r > pi) r -= 2 * pi;
    return r;
  }

  test('not turned: exactly what upstream did', () {
    for (var a = -180; a <= 180; a += 1) {
      final r = a * deg;
      final upstream = (r > 93 * deg || r < -93 * deg) ? r + pi : r;
      expect(rightSideUpAngle(r, 0), closeTo(upstream, 1e-12), reason: '$a°');
    }
  });

  test('every heading, every road: upright on screen and along the road', () {
    for (var heading = 0; heading < 360; heading += 5) {
      // The map's rotation for heading up is minus the course.
      final mapRotation = -heading * deg;
      for (var a = -180; a <= 180; a += 3) {
        final road = a * deg;
        final drawn = rightSideUpAngle(road, mapRotation);
        final onScreen = wrap(mapRotation - drawn);
        expect(onScreen.abs(), lessThanOrEqualTo(upright),
            reason: 'heading $heading°, road at $a° on the tile: ${onScreen / deg}° on screen');
        // Turned by a whole or half turn only: still along the road.
        final off = wrap(drawn - road).abs();
        expect(off < 1e-9 || (off - pi).abs() < 1e-9, isTrue, reason: 'heading $heading°, road $a°');
      }
    }
  });

  test('the bench case: east up, a north-south road reads upright', () {
    // Heading 90°: the map turned by -90°. A north-south road is vertical
    // on the tile (90°); upstream left it, which put it upside down.
    final drawn = rightSideUpAngle(90 * deg, -90 * deg);
    expect(wrap(-90 * deg - drawn).abs(), lessThan(1e-9), reason: 'horizontal, reading left to right');
  });
}
