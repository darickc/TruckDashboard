// The vector renderer's patched sprite reader (third_party/vector_tile_renderer,
// F250_PATCH.md): Mapbox's `placeholder` isn't the `content` box.
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

void main() {
  test("Mapbox's placeholder isn't read as content; content still is", () {
    final index = vtr.SpriteIndexReader().read({
      // As in Mapbox's navigation-night-v1 sprite (2026-11-24).
      'us-highway-3': {
        'x': 1692, 'y': 1452, 'width': 156, 'height': 120,
        'pixelRatio': 2, 'placeholder': [0, 14, 52, 26], 'visible': true,
      },
      'label-box': {
        'x': 0, 'y': 0, 'width': 40, 'height': 20,
        'pixelRatio': 2, 'content': [4, 4, 36, 16],
      },
    });
    expect(index.spriteByName['us-highway-3']!.content, isNull);
    expect(index.spriteByName['us-highway-3']!.pixelRatio, 2);
    expect(index.spriteByName['label-box']!.content, [4, 4, 36, 16]);
  });
}
