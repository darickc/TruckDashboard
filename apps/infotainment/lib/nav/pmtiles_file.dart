import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'pmtiles.dart';

/// Opens the tileset at [path] read-only. Throws [PmTilesException] saying
/// why it can't be shown (missing, unreadable, or not a raster PMTiles v3).
Future<PmTilesReader> openPmTilesFile(String path) async {
  final file = File(path);
  if (!await file.exists()) throw PmTilesException('no offline map at $path');
  final RandomAccessFile raf;
  try {
    raf = await file.open();
  } on FileSystemException catch (e) {
    throw PmTilesException('can\'t open $path: ${e.osError?.message ?? e.message}');
  }
  final reads = _SerialReads(raf);
  try {
    return await PmTilesReader.open(reads.read, decompress);
  } on PmTilesException catch (e) {
    await raf.close();
    throw PmTilesException('$path: ${e.message}');
  } on FileSystemException catch (e) {
    await raf.close();
    throw PmTilesException('can\'t read $path: ${e.osError?.message ?? e.message}');
  }
}

Uint8List decompress(Uint8List data, Compression c) => switch (c) {
  Compression.gzip => Uint8List.fromList(gzip.decode(data)),
  Compression.none || Compression.unknown => data,
  _ => throw PmTilesException('${c.name} compression is not supported'),
};

/// A RandomAccessFile allows one operation at a time; tiles load in
/// parallel, so reads queue.
class _SerialReads {
  _SerialReads(this._raf);
  final RandomAccessFile _raf;
  Future<void> _last = Future.value();

  Future<Uint8List> read(int offset, int length) {
    final done = Completer<Uint8List>();
    _last = _last.then((_) async {
      try {
        await _raf.setPosition(offset);
        final bytes = await _raf.read(length);
        if (bytes.length != length) {
          throw PmTilesException('the file ends early (wanted $length bytes at $offset)');
        }
        done.complete(bytes);
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }
}
