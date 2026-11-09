/// A per-signal correction applied to every accepted reading:
/// `displayed = raw × scale + offset`.
///
/// For example, vehicle speed reported by the PCM is computed from the tire
/// size programmed into it. On a truck running different tires every reading
/// is off by the same ratio, so `scale` = true speed ÷ reported speed corrects
/// it. Calibration changes only what this head unit shows and records; it
/// never writes anything to the vehicle.
class Calibration {
  const Calibration({this.scale = 1.0, this.offset = 0.0, this.note});

  static const identity = Calibration();

  /// Sanity bounds. A factor outside them is almost certainly a typo
  /// (e.g. 10.3 for 1.03), not a tire size.
  static const minScale = 0.5;
  static const maxScale = 2.0;

  final double scale;

  /// Canonical units.
  final double offset;

  /// Why this calibration exists and how it was measured.
  final String? note;

  bool get isIdentity => scale == 1.0 && offset == 0.0;

  double apply(double raw) => raw * scale + offset;

  Calibration copyWith({double? scale, double? offset, String? note}) =>
      Calibration(scale: scale ?? this.scale, offset: offset ?? this.offset, note: note ?? this.note);

  /// Throws [FormatException] for a bad scale or offset.
  static Calibration validated(String signalId, double scale, double offset, {String? note}) {
    if (!scale.isFinite || scale < minScale || scale > maxScale) {
      throw FormatException('calibration $signalId: scale $scale is outside $minScale–$maxScale');
    }
    if (!offset.isFinite) throw FormatException('calibration $signalId: offset must be finite');
    return Calibration(scale: scale, offset: offset, note: note);
  }

  static Calibration fromJson(String signalId, Map<String, dynamic> j) => validated(
        signalId,
        (j['scale'] as num? ?? 1).toDouble(),
        (j['offset'] as num? ?? 0).toDouble(),
        note: j['note'] as String?,
      );
}
