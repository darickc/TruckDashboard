import 'map_file_stub.dart' if (dart.library.io) 'pmtiles_file.dart' as impl;
import 'pmtiles.dart';

/// Opens the offline map at [path]. On the web build there are no files:
/// it throws a [PmTilesException] saying so.
Future<PmTilesReader> openOfflineMap(String path) => impl.openPmTilesFile(path);

/// The map import's status file (ADR-0033), or null if there is none.
Future<String?> readMapStatus(String path) => impl.readTextFile(path);
