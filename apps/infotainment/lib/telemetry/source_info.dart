/// What the store's data comes from, for the status bar and diagnostics.
class SourceInfo {
  const SourceInfo({
    required this.transport,
    required this.simulated,
    this.scenario,
    this.scenarioSeconds,
    this.transmitEnabled,
    this.machineState,
    this.adapterVoltage,
    this.detail,
  });

  static const none = SourceInfo(transport: 'none', simulated: false);

  /// "simulator (in-app)", "gateway: obdlink", "gateway: simulated", ...
  final String transport;

  /// Any non-vehicle source. The UI marks simulated data unmistakably.
  final bool simulated;
  final String? scenario;
  final double? scenarioSeconds;

  /// Null when not applicable (the in-app simulator transmits nothing).
  final bool? transmitEnabled;

  /// Gateway link state machine, e.g. "POLLING" (diagnostic-recovery.md).
  final String? machineState;
  final double? adapterVoltage;
  final String? detail;
}
