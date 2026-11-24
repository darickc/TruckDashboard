import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// The online map (ADR-0052): Mapbox's tiles, which services/navigation
/// fetches (it has the token and the network; the dashboard has neither).
/// The Nav screen shows them while the Pi is on a network and the offline
/// map otherwise: vector tiles drawn with Mapbox's style
/// (`online_vector_map.dart`), or raster images.
@immutable
class OnlineMapStatus {
  const OnlineMapStatus({
    this.configured = false,
    this.detail = '',
    this.attribution = '',
    this.tileSize = 512,
    this.maxZoom = 22,
    this.routingOnline = false,
    this.vector = false,
  });

  /// navigation has a Mapbox token.
  final bool configured;
  final String detail;

  /// To show with the map ("© Mapbox © OpenStreetMap").
  final String attribution;
  final int tileSize;
  final int maxZoom;

  /// Routes go to Mapbox first now.
  final bool routingOnline;

  /// Vector tiles drawn with [OnlineMapSource.style]; else raster images
  /// from [OnlineMapSource.tile].
  final bool vector;
}

/// One vector source of the online map's style and Mapbox's zooms for it.
@immutable
class OnlineMapSourceZooms {
  const OnlineMapSourceZooms(this.id, this.minZoom, this.maxZoom);
  final String id;
  final int minZoom, maxZoom;
}

/// The vector map's style for day or night, as navigation hands it on.
class OnlineMapStyleData {
  const OnlineMapStyleData({
    required this.styleJson,
    required this.spriteJson,
    required this.spritePng,
    required this.sources,
  });
  final String styleJson;
  final String spriteJson;
  final Uint8List spritePng;
  final List<OnlineMapSourceZooms> sources;
}

/// services/navigation's OnlineMapService, or a stand-in.
abstract class OnlineMapSource {
  ValueListenable<OnlineMapStatus> get status;
  void start();
  void stop();

  /// One tile's image bytes, at Mapbox's zoom [z]. Throws when there is none.
  Future<Uint8List> tile(int z, int x, int y, {required bool night});

  /// The vector map's style, with its sprites for a screen of [pixelRatio]
  /// pixels per logical pixel (1 or 2). Throws when there is none.
  Future<OnlineMapStyleData> style({required bool night, required int pixelRatio});

  /// One vector tile of the style's [source], uncompressed; empty where
  /// Mapbox has nothing. Throws when it can't be had.
  Future<Uint8List> vectorTile(String source, int z, int x, int y, {required bool night});
}

/// No online map: no navigation service, or the browser preview.
class UnavailableOnlineMapSource implements OnlineMapSource {
  UnavailableOnlineMapSource([String why = 'no online map in this build'])
    : _status = ValueNotifier(OnlineMapStatus(detail: why));

  final ValueNotifier<OnlineMapStatus> _status;

  @override
  ValueListenable<OnlineMapStatus> get status => _status;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<OnlineMapStyleData> style({required bool night, required int pixelRatio}) =>
      Future.error(StateError(_status.value.detail));
  @override
  Future<Uint8List> vectorTile(String source, int z, int x, int y, {required bool night}) =>
      Future.error(StateError(_status.value.detail));
  @override
  Future<Uint8List> tile(int z, int x, int y, {required bool night}) =>
      Future.error(StateError(_status.value.detail));
}

/// Picks the map (ADR-0052 decision 7): online while the Pi is on a network
/// and navigation has a token, unless tiles have been failing. Three
/// failures within [failWindow] switch to the offline map for [backoff];
/// both are examples.
class OnlineMapChooser extends ChangeNotifier {
  OnlineMapChooser({
    DateTime Function()? now,
    this.failuresToBackOff = 3,
    this.failWindow = const Duration(seconds: 30),
    this.backoff = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int failuresToBackOff;
  final Duration failWindow;
  final Duration backoff;

  final List<DateTime> _failures = [];
  DateTime? _offlineUntil;
  String _lastFailure = '';

  /// Why the online map is set aside now, or empty.
  String get backedOffBecause => backingOff ? _lastFailure : '';

  bool get backingOff {
    final until = _offlineUntil;
    return until != null && _now().isBefore(until);
  }

  /// Whether to show the online map.
  bool useOnline({required bool onNetwork, required bool configured}) =>
      onNetwork && configured && !backingOff;

  /// A tile arrived ([ok]) or failed ([why]).
  void report({required bool ok, String why = ''}) {
    final t = _now();
    if (ok) {
      if (_failures.isNotEmpty) _failures.clear();
      return;
    }
    _lastFailure = why;
    _failures
      ..add(t)
      ..removeWhere((f) => t.difference(f) > failWindow);
    if (_failures.length >= failuresToBackOff && !backingOff) {
      _failures.clear();
      _offlineUntil = t.add(backoff);
      notifyListeners();
      // Come back by itself.
      Timer(backoff, notifyListeners);
    }
  }
}

/// flutter_map's tiles from an [OnlineMapSource]. With
/// `tileDimension: 512` and `zoomOffset: -1` (Mapbox's 512-pixel tiles are
/// one zoom level behind 256-pixel ones), the tile zoom asked for is the
/// layer's plus its offset, as flutter_map does for URLs.
class OnlineTileProvider extends TileProvider {
  OnlineTileProvider(this.source, {required this.night, this.onResult});

  final OnlineMapSource source;
  final bool night;

  /// Each tile's outcome, for [OnlineMapChooser.report].
  final void Function(bool ok, String why)? onResult;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => OnlineTileImage(
    source,
    z: (coordinates.z + options.zoomOffset).round(),
    x: coordinates.x,
    y: coordinates.y,
    night: night,
    onResult: onResult,
  );
}

/// One online tile as an image.
@immutable
class OnlineTileImage extends ImageProvider<OnlineTileImage> {
  const OnlineTileImage(
    this.source, {
    required this.z,
    required this.x,
    required this.y,
    required this.night,
    this.onResult,
  });

  final OnlineMapSource source;
  final int z, x, y;
  final bool night;
  final void Function(bool ok, String why)? onResult;

  @override
  Future<OnlineTileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(OnlineTileImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await source.tile(z, x, y, night: night);
      final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      onResult?.call(true, '');
      return codec;
    } catch (e) {
      onResult?.call(false, '$e');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is OnlineTileImage &&
      identical(other.source, source) &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      other.night == night;

  @override
  int get hashCode => Object.hash(identityHashCode(source), z, x, y, night);
}
