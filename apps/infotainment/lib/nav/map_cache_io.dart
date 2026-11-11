import 'dart:io';

final _root = Directory('${Directory.systemTemp.path}/f250-vector-map-$pid');
Future<void>? _emptied;

/// A folder for this run and this map only: the run's folder is emptied on
/// first use (a tile half-written when the power went off is never read
/// back), and each map opened gets its own (a replaced map's tiles never
/// show).
Future<Directory> Function()? mapCacheFolderFor(int generation) => () async {
  await (_emptied ??= () async {
    if (await _root.exists()) await _root.delete(recursive: true);
  }());
  return Directory('${_root.path}/$generation').create(recursive: true);
};
