import '../telemetry/calibration.dart';
import '../telemetry/telemetry_store.dart';
import 'gateway_connection_stub.dart'
    if (dart.library.io) 'grpc_vehicle_data_source.dart' as impl;
import 'vehicle_data_source.dart';

/// Where the vehicle gateway listens.
sealed class GatewayEndpoint {
  const GatewayEndpoint();

  /// `unix:/path/to.sock` or `tcp:host:port`.
  static GatewayEndpoint parse(String s) {
    if (s.startsWith('unix:')) return UnixEndpoint(s.substring(5));
    if (s.startsWith('tcp:')) {
      final rest = s.substring(4);
      final i = rest.lastIndexOf(':');
      final port = i < 0 ? null : int.tryParse(rest.substring(i + 1));
      if (port == null) throw FormatException('expected tcp:host:port, got $s');
      return TcpEndpoint(rest.substring(0, i), port);
    }
    throw FormatException('gateway endpoint must start with unix: or tcp:, got $s');
  }
}

class UnixEndpoint extends GatewayEndpoint {
  const UnixEndpoint(this.path);
  final String path;
  @override
  String toString() => 'unix:$path';
}

class TcpEndpoint extends GatewayEndpoint {
  const TcpEndpoint(this.host, this.port);
  final String host;
  final int port;
  @override
  String toString() => 'tcp:$host:$port';
}

/// A data source backed by services/vehicle-gateway (Phase 3). The gateway
/// decides validity, link state and alerts; the app mirrors them and keeps a
/// feed watchdog of its own.
abstract class GatewayConnection implements VehicleDataSource {
  /// Sends a calibration to the gateway (docs/diagnostics/CALIBRATION.md).
  Future<void> setCalibration(String signalId, Calibration c);

  /// Not available on the web build (no sockets); throws UnsupportedError.
  static GatewayConnection create(TelemetryStore store, GatewayEndpoint endpoint) =>
      impl.createGatewayConnection(store, endpoint);
}
