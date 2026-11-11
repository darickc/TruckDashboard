import 'pmtiles.dart';

Future<PmTilesReader> openPmTilesFile(String path) async =>
    throw PmTilesException('the browser preview has no offline map (no files)');

Future<String?> readTextFile(String path) async => null;
