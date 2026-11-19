import '../model/signal.dart';
import 'poll_result.dart';

/// Everything known about one signal right now.
///
/// [value] is non-null **only** while [validity] is [Validity.valid]. A
/// display that wants the last reading must ask for [lastGoodValue] and show
/// its age. That split is deliberate: it makes "a frozen number shown as
/// current" impossible to write by accident.
class SignalState {
  SignalState(this.def);

  final SignalDef def;

  Validity validity = Validity.noData;
  double? value;

  /// Last reading that passed validation (calibrated), and when it was
  /// measured.
  double? lastGoodValue;
  Duration? lastGoodAt;

  /// The decoded value before calibration, for the last good reading.
  double? lastGoodRaw;

  /// Most recent request outcome of any kind.
  PollOutcome? lastOutcome;
  Duration? lastOutcomeAt;
  int? lastNrc;
  String? lastResponder;
  int? lastLatencyMs;

  /// Most recent in-range response arrived after the last good one but was
  /// out of the plausible range.
  double? lastRejectedValue;

  int successes = 0;
  int failures = 0;
  int consecutiveFailures = 0;

  /// For computed signals: ids of inputs that are not valid.
  List<String> invalidInputs = const [];

  /// The highest and lowest valid value since the dashboard started (or the
  /// scenario or calibration changed), canonical units. Only values that
  /// were valid when sampled, and only while the signal's warning-rule gate
  /// holds (TelemetryStore._trackPeaks). Null: none yet.
  double? peakHigh, peakLow;

  Duration? ageAt(Duration now) => lastGoodAt == null ? null : now - lastGoodAt!;

  bool get isValid => validity == Validity.valid;

  void reset() {
    validity = def.enabled ? Validity.noData : Validity.disabled;
    value = lastGoodValue = lastGoodRaw = lastRejectedValue = null;
    lastGoodAt = lastOutcomeAt = null;
    lastOutcome = null;
    lastNrc = lastLatencyMs = null;
    lastResponder = null;
    successes = failures = consecutiveFailures = 0;
    invalidInputs = const [];
    peakHigh = peakLow = null;
  }
}
