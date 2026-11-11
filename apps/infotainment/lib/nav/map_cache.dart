import 'map_cache_stub.dart' if (dart.library.io) 'map_cache_io.dart' as impl;

/// Where the vector map layer keeps the tiles it has drawn for the map
/// opened [generation]th (ADR-0032, ADR-0033): a folder for this run and
/// this map in the system temporary directory (on the truck the dashboard's
/// private /tmp), never next to the map. Null on the web build.
final mapCacheFolderFor = impl.mapCacheFolderFor;

/// The cache's upper bound: the tiles are already on the device.
const mapCacheMaxBytes = 16 * 1024 * 1024;
