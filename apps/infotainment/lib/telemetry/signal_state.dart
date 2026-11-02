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

  /// Last reading that passed validation, and when it was measured.
  double? lastGoodValue;
  Duration? lastGoodAt;

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

  Duration? ageAt(Duration now) => lastGoodAt == null ? null : now - lastGoodAt!;

  bool get isValid => validity == Validity.valid;

  void reset() {
    validity = def.enabled ? Validity.noData : Validity.disabled;
    value = lastGoodValue = lastRejectedValue = null;
    lastGoodAt = lastOutcomeAt = null;
    lastOutcome = null;
    lastNrc = lastLatencyMs = null;
    lastResponder = null;
    successes = failures = consecutiveFailures = 0;
    invalidInputs = const [];
  }
}
