/// Where vehicle data comes from. The UI depends only on this interface and
/// on TelemetryStore, never on a transport.
///
/// Implementations:
/// - SimulatedVehicleDataSource (Phase 2): plays simulator scenarios in-process.
/// - A gRPC source against services/vehicle-gateway, added in Phase 3. It does
///   not exist yet.
abstract class VehicleDataSource {
  /// Short label for the status bar, e.g. "SIMULATED".
  String get label;

  /// True for any non-vehicle source. The UI marks simulated data
  /// unmistakably.
  bool get isSimulated;

  void start();
  void stop();
}
