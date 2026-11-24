import 'dart:ui';

import '../context.dart';

abstract class SymbolIcon {
  RenderedIcon? render(
    Offset offset, {
    required Size contentSize,
    required bool withRotation,
  });

  /// F-250 patch: where [render] would draw the icon (unturned), for the
  /// label space; null if it draws nothing.
  Rect? box(Offset offset, {required Size contentSize});
}

class RenderedIcon {
  final bool overlapsText;
  final Rect area;
  final Rect contentArea;

  RenderedIcon({
    required this.overlapsText,
    required this.area,
    required this.contentArea,
  });
}

/// F-250 patch: places [icon]'s box at [offset] in the label space, so
/// labels don't cover each other's icons (Mapbox GL checks icons too).
/// [text] is the label's text, just placed, or null for an icon alone. When
/// the icon doesn't fit, the text is taken back and the label isn't drawn.
bool placeIcon(
  Context context,
  SymbolIcon? icon,
  Offset offset, {
  required Size contentSize,
  required String? text,
}) {
  final box = icon?.box(offset, contentSize: contentSize);
  if (box == null) {
    return true;
  }
  final space = context.labelSpace;
  if (!space.canOccupyIcon(box, besideText: text != null)) {
    if (text != null) {
      space.vacate(text);
    }
    return false;
  }
  space.occupyIcon(box);
  return true;
}
