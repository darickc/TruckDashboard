/// Physical quantity; selects unit conversion and formatting.
enum Quantity {
  temperature,

  /// A difference of temperatures: converts by scale only, without the +32
  /// offset absolute temperatures get.
  temperatureDelta,
  pressure,
  voltage,
  speed,
  rotation,
  percent,
}

/// How much to trust a signal's definition. Mirrors `Provenance` in
/// docs/architecture/telemetry-model.md and the Phase 3 proto.
enum Provenance {
  /// Published SAE J1979 formula.
  sae,

  /// Confirmed on this truck; evidence in docs/diagnostics/VERIFICATION_LOG.md.
  verifiedOnTruck,

  /// Imported (Torque export) and not yet confirmed on the truck.
  importedUnverified,

  /// Derived from other signals.
  computed,

  /// Added hardware, e.g. an EGT probe.
  auxSensor,
}

/// Whether a sample may be shown as current. See telemetry-model.md.
enum Validity {
  valid,
  stale,
  noData,
  outOfRange,
  decodeError,
  unsupported,
  disabled,
}

typedef ComputeFn = double Function(List<double> inputs);

class SignalDef {
  const SignalDef({
    required this.id,
    required this.name,
    required this.shortName,
    required this.quantity,
    required this.unit,
    required this.provenance,
    required this.min,
    required this.max,
    this.staleAfter = const Duration(seconds: 3),
    this.request,
    this.responder,
    this.evidence,
    this.displayDecimals,
    this.enabled = true,
    this.disabledReason,
    this.inputs = const [],
    this.compute,
    this.maxInputSkew = const Duration(seconds: 2),
  });

  /// Stable API key (snake_case).
  final String id;
  final String name;

  /// Label for compact tiles, e.g. "EOT".
  final String shortName;
  final Quantity quantity;

  /// Canonical unit of [min]/[max] and of every value the source delivers.
  final String unit;
  final Provenance provenance;

  /// Plausibility limits (canonical unit). Outside them a response is
  /// OUT_OF_RANGE and never becomes the displayed value.
  final double min;
  final double max;
  final Duration staleAfter;

  /// Request as documented in docs/diagnostics/FORD_6_0_PIDS.md, for display.
  final String? request;

  /// CAN ID of the module that owns the value, when verified.
  final String? responder;

  /// Where the verification evidence lives (required for verifiedOnTruck).
  final String? evidence;

  /// Overrides the per-quantity display precision.
  final int? displayDecimals;
  final bool enabled;
  final String? disabledReason;

  /// For computed signals: input signal ids, in [compute]'s argument order.
  final List<String> inputs;
  final ComputeFn? compute;

  /// Computed signals are valid only when inputs were measured this close
  /// together.
  final Duration maxInputSkew;

  bool get isComputed => compute != null;
}
