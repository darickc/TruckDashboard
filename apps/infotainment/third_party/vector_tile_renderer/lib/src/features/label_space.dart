import 'dart:ui';

class LabelSpace {
  final Rect space;
  final List<_LabelRect> _occupied = [];
  final Set<String> texts = {};

  LabelSpace(this.space);

  bool canAccept(String? text) =>
      text != null && text.isNotEmpty && !texts.contains(text);

  bool canOccupy(String text, Rect rect) =>
      canAccept(text) &&
      space.containsCompletely(rect) &&
      !_occupied.any((existing) => existing.space.overlaps(rect));

  /// F-250 patch: whether a label's icon fits. With [besideText], the
  /// label's own text was the last box placed and is left out: an icon is
  /// drawn around or beside its own text.
  bool canOccupyIcon(Rect box, {required bool besideText}) {
    final others = besideText && _occupied.isNotEmpty
        ? _occupied.sublist(0, _occupied.length - 1)
        : _occupied;
    return space.containsCompletely(box) &&
        !others.any((existing) => existing.space.overlaps(box));
  }

  /// F-250 patch: an icon's box, which later labels then avoid.
  void occupyIcon(Rect box) => _occupied.add(_LabelRect('', box.inflate(margin)));

  /// F-250 patch: takes back [text], the last box placed, when its icon
  /// doesn't fit.
  void vacate(String text) {
    _occupied.removeLast();
    texts.remove(text);
  }

  void occupy(String text, Rect box) {
    final boxWithMargin = Rect.fromLTRB(
      box.left - margin,
      box.top - margin,
      box.right + (2 * margin),
      box.bottom + (2 * margin),
    );
    _occupied.add(_LabelRect(text, boxWithMargin));
    texts.add(text);
  }
}

extension _RectExtension on Rect {
  bool containsCompletely(Rect other) =>
      contains(other.topLeft) && contains(other.bottomRight);
}

const margin = 2.0;

class _LabelRect {
  final Rect space;
  final String text;
  _LabelRect(this.text, this.space);
}

/// F-250 patch: the labels of several tiles placed in one space, so a label
/// near a tile's edge can reach into the next tile instead of being dropped
/// (upstream keeps every label inside its own tile). Boxes are in the
/// coordinates of the canvas the tiles are drawn on (logical pixels).
///
/// - A label is placed only if its centre is visible ([isVisible]).
/// - Labels don't overlap, whichever tile they come from.
/// - The same text is placed again only [repeatDistance] or more from where
///   it already is, so a long road is named more than once per screen but a
///   name isn't repeated by every tile it crosses.
class SharedLabelSpace {
  SharedLabelSpace({required this.isVisible, this.repeatDistance = 400});

  final bool Function(Offset centre) isVisible;
  final double repeatDistance;
  final List<Rect> _occupied = [];
  final Map<String, List<Offset>> _placed = {};

  /// How many labels have been placed.
  int get count => _occupied.length;

  /// Where each text was placed: its boxes' centres.
  Map<String, List<Offset>> get placed => Map.unmodifiable(_placed);

  bool canOccupy(String text, Rect box) {
    final centre = box.center;
    if (!isVisible(centre)) {
      return false;
    }
    final same = _placed[text];
    if (same != null &&
        same.any((c) => (c - centre).distance < repeatDistance)) {
      return false;
    }
    return !_occupied.any((o) => o.overlaps(box));
  }

  void occupy(String text, Rect box) {
    _occupied.add(box.inflate(margin));
    (_placed[text] ??= []).add(box.center);
  }

  /// Whether a label's icon fits; see [LabelSpace.canOccupyIcon]. An icon
  /// with no text must have its centre on the screen.
  bool canOccupyIcon(Rect box, {required bool besideText}) {
    if (!besideText && !isVisible(box.center)) {
      return false;
    }
    final others = besideText && _occupied.isNotEmpty
        ? _occupied.sublist(0, _occupied.length - 1)
        : _occupied;
    return !others.any((o) => o.overlaps(box));
  }

  void occupyIcon(Rect box) => _occupied.add(box.inflate(margin));

  /// Takes back [text], the last box placed.
  void vacate(String text) {
    _occupied.removeLast();
    final same = _placed[text]!..removeLast();
    if (same.isEmpty) {
      _placed.remove(text);
    }
  }
}

/// F-250 patch: one tile's view of a [SharedLabelSpace]. The renderer gives
/// boxes in the tile's pixels (0 to 256 across); [origin] and [scale] put
/// them on the canvas. A tile places only labels whose centre is in [space]
/// (its own area): a feature near an edge is in both tiles' data (the tile
/// buffer), and only the tile it belongs to draws its label.
class TileLabelSpace extends LabelSpace {
  TileLabelSpace(
    this.shared, {
    required Rect own,
    required this.origin,
    required this.scale,
  }) : super(own);

  final SharedLabelSpace shared;
  final Offset origin;
  final double scale;

  @override
  bool canAccept(String? text) => text != null && text.isNotEmpty;

  @override
  bool canOccupy(String text, Rect rect) =>
      canAccept(text) &&
      space.contains(rect.center) &&
      shared.canOccupy(text, onCanvas(rect));

  @override
  void occupy(String text, Rect box) => shared.occupy(text, onCanvas(box));

  @override
  bool canOccupyIcon(Rect box, {required bool besideText}) =>
      (besideText || space.contains(box.center)) &&
      shared.canOccupyIcon(onCanvas(box), besideText: besideText);

  @override
  void occupyIcon(Rect box) => shared.occupyIcon(onCanvas(box));

  @override
  void vacate(String text) => shared.vacate(text);

  /// [rect] from the tile's pixels to the canvas.
  Rect onCanvas(Rect rect) => Rect.fromLTRB(
    origin.dx + rect.left * scale,
    origin.dy + rect.top * scale,
    origin.dx + rect.right * scale,
    origin.dy + rect.bottom * scale,
  );
}
