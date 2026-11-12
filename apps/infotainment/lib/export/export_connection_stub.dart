import '../data/gateway_connection.dart';
import 'export_state.dart';

/// Web builds have no sockets; the browser preview uses SimulatedExportSource.
ExportSource createGrpcExportSource(GatewayEndpoint endpoint) =>
    throw UnsupportedError('usb-export is not reachable from a web build');
