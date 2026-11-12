import '../data/gateway_connection.dart';
import 'export_connection_stub.dart' if (dart.library.io) 'grpc_export_source.dart' as impl;
import 'export_state.dart';

/// services/usb-export over gRPC at [endpoint]. Not available on the web
/// build (no sockets): throws UnsupportedError there.
ExportSource connectUsbExport(GatewayEndpoint endpoint) => impl.createGrpcExportSource(endpoint);
