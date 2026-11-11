import 'dart:io';

Directory? _folder;

/// A folder for this run only: emptied on first use, so a tile half-written
/// when the power went off is never read back.
Future<Directory> Function()? get mapCacheFolder => () async {
  final d = _folder ??= Directory('${Directory.systemTemp.path}/f250-vector-map-$pid');
  if (!_ready) {
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
    _ready = true;
  }
  return d;
};

bool _ready = false;
