/// Source-independent description of one request's outcome. The simulated
/// source maps simulator observations onto this. The Phase 3 gRPC source maps
/// gateway samples onto it.
enum PollOutcome { response, noResponse, negativeResponse, invalidResponse, linkDown }

class PollResult {
  const PollResult({
    required this.signalId,
    required this.at,
    required this.outcome,
    this.value,
    this.nrc,
    this.latencyMs,
    this.responder,
  });

  final String signalId;

  /// Monotonic time of the response (or of the give-up, for failures).
  final Duration at;
  final PollOutcome outcome;

  /// Canonical-unit value when [outcome] is [PollOutcome.response].
  final double? value;
  final int? nrc;
  final int? latencyMs;
  final String? responder;
}
