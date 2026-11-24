import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../nav/data_licences.dart';
import '../../nav/map_cache.dart';
import '../../nav/map_update.dart';
import '../../nav/offline_map.dart';
import '../../nav/online_map.dart';
import '../../nav/online_vector_map.dart';
import '../../model/units.dart';
import '../../nav/position_state.dart';
import '../../nav/route_state.dart';
import '../../nav/search_state.dart';
import '../../nav/vector_map.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';
import 'nav_extras.dart';
import 'nav_places.dart';
import 'nav_search.dart';

/// The offline map, the truck's position and routing (Phase 6.4, 6.5.1 and
/// 6.5.2; ADR-0030, vector maps ADR-0032, routing ADR-0035). Heading up
/// (owner, 2026-11-12): while it follows the truck the map turns so the
/// direction of travel is up, from the receiver's course while moving; it
/// keeps its last turn while stopped (the course is noise then), and the
/// compass shows where north is. It follows the truck until the map is
/// dragged; the locate button follows again. Search for an address or place (ADR-0038), long-press the map, or
/// pick a saved place (ADR-0040) to choose a destination. Directions are
/// spoken by services/navigation; the route's buttons mute them.
///
/// Honest about what it knows: a fix that isn't current is drawn grey and
/// labelled "last known" with its age (CLAUDE.md rule 4), a simulated
/// position says so, a missing map says why, guidance pauses (no distances)
/// without a current position, and every route says it isn't checked for
/// heavy vehicles or trailers (ADR-0010).
///
/// Online (ADR-0052): while the Pi is on a network and navigation has a
/// Mapbox token, the map is Mapbox's (its tiles through navigation) and
/// routes come from Mapbox with traffic; otherwise the offline map and
/// Valhalla, as before. The screen says which.
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  /// Where the map opens without a fix or a tileset: the middle of the
  /// contiguous United States.
  static const fallbackCenter = LatLng(39.83, -98.58);
  static const fallbackZoom = 4.0;

  /// The default zoom once a fix arrives.
  static const followZoom = 15.0;

  /// The map turns only for a course at least this fast (the marker's
  /// arrow uses the same: below it the course is noise).
  static const headingMinMps = 1.0;

  /// Course changes smaller than this don't turn the map (GPS jitter).
  static const headingStepDeg = 2.0;

  /// The map's rotation for heading up: flutter_map turns the map by its
  /// rotation clockwise, so the course goes up when the map is turned by
  /// minus the course.
  static double rotationFor(double headingDeg) {
    final r = (-headingDeg) % 360;
    return r > 180 ? r - 360 : r;
  }

  /// A current course to turn to, or null (stale fix, no course, too slow).
  static double? courseOf(FixReport fix, bool current) {
    final track = fix.trackDeg;
    if (!current || track == null || !track.isFinite) return null;
    if ((fix.speedMps ?? 0) < NavigationScreen.headingMinMps) return null;
    return track % 360;
  }

  /// Above this the truck counts as moving, and search asks to type only
  /// when parked. An example value (5 mph), not a safety limit: typing is
  /// never locked out (owner's decision, docs/safety/assumptions.md).
  static const movingKmh = 8.0;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _map = MapController();

  /// Online or offline map, and the online map set aside while its tiles
  /// fail (ADR-0052 decision 7).
  final _chooser = OnlineMapChooser();

  /// Mapbox's vector map by night (true) and day, once read; which are
  /// being read; which couldn't be read (tried again 30 s later), and why;
  /// and the source they came from.
  final Map<bool, OnlineVectorMap> _onlineVector = {};
  final Set<bool> _onlineVectorLoading = {};
  final Set<bool> _onlineVectorFailedFor = {};
  String _onlineVectorWhy = '';
  Timer? _onlineVectorRetry;
  OnlineMapSource? _onlineVectorFrom;

  /// The vector style for [night] couldn't be read lately: the offline map
  /// meanwhile.
  bool _onlineVectorFailed(bool night) =>
      _onlineVectorFailedFor.contains(night) && !_onlineVector.containsKey(night);
  bool _ready = false;
  bool _follow = true;
  Timer? _tick;
  PositionSource? _source;
  LatLng? _lastCentered;

  /// A long-pressed point or a search result waiting for Route here or
  /// Cancel, and the result's name.
  LatLng? _pending;
  String? _pendingName;
  String _pendingDetail = '';

  /// The search panel is open, and what was typed in it last.
  bool _searching = false;
  String _searchQuery = '';

  /// The saved places panel is open, and a place being saved or edited.
  bool _placesOpen = false;
  PlaceDraft? _editing;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = AppScope.of(context).position;
    if (!identical(source, _source)) {
      _source?.status.removeListener(_onPosition);
      _source = source..status.addListener(_onPosition);
    }
    // Ages move and fixes go stale even when no message arrives.
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Starts reading the vector style for [night] unless it is read, being
  /// read, or failed less than 30 s ago. Never calls setState itself until
  /// the style is in.
  void _readOnlineVector(OnlineMapSource source, bool night) {
    if (!identical(source, _onlineVectorFrom)) {
      _onlineVector.clear();
      _onlineVectorFrom = source;
    }
    if (_onlineVector.containsKey(night) || _onlineVectorLoading.contains(night)) return;
    if (_onlineVectorFailed(night)) return;
    _onlineVectorLoading.add(night);
    OnlineVectorMap.load(
      source,
      night: night,
      pixelRatio: spritePixelRatio(MediaQuery.devicePixelRatioOf(context)),
      onResult: (ok, why) => _chooser.report(ok: ok, why: why),
    ).then(
      (m) {
        _onlineVectorLoading.remove(night);
        if (mounted && identical(source, _onlineVectorFrom)) {
          setState(() => _onlineVector[night] = m);
        }
      },
      onError: (Object e) {
        _onlineVectorLoading.remove(night);
        if (!mounted) return;
        setState(() {
          _onlineVectorFailedFor.add(night);
          _onlineVectorWhy = e is StateError ? e.message : '$e';
        });
        _onlineVectorRetry?.cancel();
        _onlineVectorRetry = Timer(const Duration(seconds: 30), () {
          if (mounted) setState(_onlineVectorFailedFor.clear);
        });
      },
    );
  }

  @override
  void dispose() {
    _chooser.dispose();
    _tick?.cancel();
    _onlineVectorRetry?.cancel();
    _source?.status.removeListener(_onPosition);
    _map.dispose();
    super.dispose();
  }

  void _onPosition() => _centre();

  /// The course the map is turned to (degrees clockwise from north); null
  /// until the truck has moved: north up until then.
  double? _heading;


  /// Turns the map to the truck's course while following (heading up).
  void _turn(FixReport fix, bool current) {
    final course = NavigationScreen.courseOf(fix, current);
    if (course != null) {
      final last = _heading;
      final step = last == null ? 360.0 : ((course - last + 540) % 360 - 180).abs();
      if (step >= NavigationScreen.headingStepDeg) _heading = course;
    }
    final want = _heading == null ? 0.0 : NavigationScreen.rotationFor(_heading!);
    if ((_map.camera.rotation - want).abs() > 0.01) _map.rotate(want);
  }

  /// While a route's banner covers the top of the map, the truck is kept
  /// this far below the middle so the banner never hides it.
  static const _belowBanner = Offset(0, 60);
  bool _lowered = false;

  /// Keeps the truck in the middle (lower while routing) while following.
  void _centre({bool force = false}) {
    if (!_ready || !_follow) return;
    final status = _source?.status.value;
    final fix = status?.report?.fix;
    if (status == null || fix == null) return;
    // Turned first, so the offset below is along the new up.
    _turn(fix, status.isCurrent(_source!.clock.now()));
    final at = LatLng(fix.lat, fix.lon);
    if (!force && at == _lastCentered) return;
    _lastCentered = at;
    final zoom = force && _map.camera.zoom < 10 ? NavigationScreen.followZoom : _map.camera.zoom;
    _map.move(at, zoom, offset: _lowered ? _belowBanner : Offset.zero);
  }

  void _zoom(double by, double minZoom, double maxZoom) {
    if (!_ready) return;
    final camera = _map.camera;
    _map.move(camera.center, (camera.zoom + by).clamp(minZoom, maxZoom));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ValueListenableBuilder(
          valueListenable: s.map.state,
          builder: (context, mapState, _) => ValueListenableBuilder(
            valueListenable: s.map.update,
            builder: (context, update, _) => ValueListenableBuilder(
              valueListenable: s.position.status,
              builder: (context, position, _) => ValueListenableBuilder(
                valueListenable: s.route.state,
                // Distances follow the unit setting at once.
                builder: (context, route, _) => ListenableBuilder(
                  // Also the network, the online map's status, and tile
                  // failures (ADR-0052).
                  listenable: Listenable.merge([s.settings, s.wifi.view, s.onlineMap.status, _chooser]),
                  builder: (context, _) => _build(
                    context,
                    p,
                    mapState,
                    update,
                    position,
                    s.position.clock.now(),
                    route,
                    s.route.clock.now(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    Palette p,
    MapFileState mapState,
    MapUpdateStatus? update,
    PositionState position,
    Duration now,
    RouteView route,
    Duration routeNow,
  ) {
    final s = AppScope.of(context);
    final reader = mapState is MapReady ? mapState.reader : null;
    final vector = mapState is MapReady ? mapState.vector : null;
    final header = reader?.header;
    // Mapbox's map while on a network, with a token (ADR-0052).
    final onlineStatus = s.onlineMap.status.value;
    final night = Theme.of(context).brightness == Brightness.dark;
    final wantOnline = _chooser.useOnline(
      onNetwork: s.wifi.view.value.onNetwork,
      configured: onlineStatus.configured,
    );
    // Mapbox's vector map, read once per look (ADR-0052 decision 6); while
    // its style can't be read, the offline map.
    final onlineVectorWanted = wantOnline && onlineStatus.vector;
    if (onlineVectorWanted) _readOnlineVector(s.onlineMap, night);
    final styleFailed = onlineVectorWanted && _onlineVectorFailed(night);
    final online = wantOnline && !styleFailed;
    final onlineVector = online && onlineStatus.vector ? _onlineVector[night] : null;
    final minZoom = online ? 2.0 : math.max(2.0, (header?.minZoom ?? 2).toDouble());
    final maxZoom = online
        ? 19.0
        : math.min(19.0, (header?.maxZoom ?? 17) + 2.0); // up to two zooms of overzoom
    final report = position.report;
    final fix = report?.fix;
    final current = position.isCurrent(now);
    final initialCenter = fix != null
        ? LatLng(fix.lat, fix.lon)
        : header != null
        ? LatLng(header.centerLat, header.centerLon)
        : NavigationScreen.fallbackCenter;
    final initialZoom = fix != null
        ? NavigationScreen.followZoom
        : header != null
        ? header.centerZoom.toDouble().clamp(minZoom, maxZoom)
        : NavigationScreen.fallbackZoom;

    // Routing (ADR-0035).
    final routeState = route.state;
    final navRoute = route.route;
    final onRoute = const {
      RouteState.routing,
      RouteState.active,
      RouteState.failed,
      RouteState.arrived,
    }.contains(routeState);
    if (onRoute != _lowered) {
      _lowered = onRoute;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centre(force: true);
      });
    }
    final progress = current ? route.currentProgress(routeNow) : null;
    final routeFetched = navRoute != null && navRoute.id == route.guidance?.routeId;
    final guiding = progress != null && routeFetched;
    final destination = onRoute ? (route.guidance?.destination ?? navRoute?.destination) : null;
    final attribution = online
        ? 'Mapbox · ${onlineStatus.attribution.isEmpty ? '© Mapbox © OpenStreetMap' : onlineStatus.attribution}'
        : reader != null
        ? [
            reader.attribution ?? kOsmCredit,
            if (reader.dataDate != null) 'data ${reader.dataDate}',
          ].join(' · ')
        : (onRoute && navRoute != null) || destination != null
        ? kOsmCredit
        : null;
    final canRoute =
        route.link == RouteLink.connected &&
        routeState != null &&
        routeState != RouteState.unavailable;
    final mapProblem = online
        ? null
        : switch (mapState) {
            MapLoading() => 'Opening the offline map…',
            MapUnavailable(:final why) => 'No map: $why. The position is still shown.',
            MapReady() => null,
          };
    final onlineSetAside = styleFailed ? _onlineVectorWhy : _chooser.backedOffBecause;
    final bottomNotices = <Widget>[
      // ADR-0030 decision 4: a simulated position is labelled as such,
      // down here rather than over the map and the route (owner,
      // 2026-11-17). In this column it stacks with the rest; beside the
      // map buttons it met the compass when an alert shortens the map.
      if (position.report?.simulated ?? false)
        Semantics(
          label: 'Simulated position, not the truck',
          excludeSemantics: true,
          child: _Chip('SIM', key: const ValueKey('nav-simulated'), color: p.simulated, filled: true),
        ),
      // While routing it is one small line instead (below), so the truck
      // stays visible between the banner and the buttons.
      if (mapProblem != null && !onRoute)
        _Notice(
          key: const ValueKey('nav-map-problem'),
          icon: Icons.layers_clear_outlined,
          text: mapProblem,
          palette: p,
        ),
      // A map stick being imported (ADR-0033), or one that just was. While
      // routing it is one small line: the card would reach the guidance
      // banner and hide its heavy-vehicle warning (seen on the Pi,
      // 2026-11-11). The status bar's chip shows it on every screen.
      if (update != null && update.shownAt(DateTime.now()))
        if (onRoute)
          Text(
            update.text,
            key: const ValueKey('nav-map-update'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _updateColor(update, p)),
          )
        else
          _Notice(
            key: const ValueKey('nav-map-update'),
            icon: Icons.usb,
            text: update.text,
            palette: p,
            color: _updateColor(update, p),
          ),
      if (onlineSetAside.isNotEmpty && !onRoute)
        _Notice(
          key: const ValueKey('nav-online-failing'),
          icon: Icons.cloud_off,
          text: 'Online map not loading ($onlineSetAside): the offline map for now',
          palette: p,
          color: p.advisory,
        ),
      if (route.commandError.isNotEmpty)
        _Notice(
          key: const ValueKey('nav-route-error'),
          icon: Icons.error_outline,
          text: route.commandError,
          palette: p,
          color: p.advisory,
        ),
      if (_pending != null)
        _PendingPanel(
          at: _pending!,
          name: _pendingName,
          palette: p,
          canRoute: canRoute,
          onRoute: () {
            final to = _pending!;
            final name = _pendingName ?? '';
            final detail = _pendingDetail;
            setState(() {
              _pending = null;
              _pendingName = null;
              _follow = true;
            });
            s.route.setDestination(to, name: name, detail: detail);
            _centre(force: true);
          },
          onSave: () => setState(
            () => _editing = PlaceDraft(location: _pending!, name: _pendingName ?? '', detail: _pendingDetail),
          ),
          onCancel: () => setState(() {
            _pending = null;
            _pendingName = null;
          }),
        )
      else if (onRoute)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (routeState == RouteState.failed && destination != null) ...[
              _textButton(
                'nav-retry',
                'Retry',
                Icons.refresh,
                () => s.route.setDestination(destination, name: route.guidance?.destinationName ?? ''),
              ),
              const SizedBox(width: kGap),
            ],
            if (destination != null) ...[
              _button(
                'nav-save-destination',
                'Save the destination',
                Icons.star_border,
                () => setState(
                  () => _editing = PlaceDraft(location: destination, name: route.guidance?.destinationName ?? ''),
                ),
              ),
              const SizedBox(width: kGap),
            ],
            // Spoken directions (ADR-0040). "No audio": prompts reach only
            // the log (no speech output yet on the Pi).
            if (route.guidance?.voice case final voice?) ...[
              _textButton(
                'nav-voice',
                voice.muted ? 'Muted' : (voice.audible ? 'Voice' : 'No audio'),
                voice.muted ? Icons.volume_off : Icons.volume_up,
                () => s.route.setVoice(muted: !voice.muted),
                selected: !voice.muted,
              ),
              const SizedBox(width: kGap),
            ],
            _textButton('nav-end-route', 'End route', Icons.close, () => s.route.clearRoute()),
            // Beside the buttons, never above them: a taller column would
            // reach the truck at the map's centre.
            const Flexible(child: NavGlance()),
          ],
        )
      else
        // Saved places (ADR-0040). In a Row so it keeps its own width.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _textButton('nav-places-open', 'Places', Icons.star, () => setState(() => _placesOpen = true)),
            const Flexible(child: NavGlance()),
          ],
        ),
    ];
    final routingHint = switch ((route.link, routeState)) {
      (_, RouteState.unavailable) => 'Routing unavailable: ${route.guidance!.detail}',
      (RouteLink.connecting, null) => 'Routing: connecting to the navigation service…',
      (RouteLink.lost, null) =>
        'Routing unavailable: navigation service unavailable${route.detail.isEmpty ? '' : ': ${route.detail}'}',
      (_, RouteState.idle) => 'Search, or long-press the map, to route',
      _ => null,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            // A new tileset, or online/offline, rebuilds the map with its zooms.
            key: ValueKey((header, online)),
            mapController: _map,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: initialZoom.clamp(minZoom, maxZoom),
              minZoom: minZoom,
              maxZoom: maxZoom,
              backgroundColor: p.background,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _ready = true;
                _centre(force: true);
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
              },
              onLongPress: canRoute
                  ? (_, at) => setState(() {
                      _pending = at;
                      _pendingName = null;
                      _pendingDetail = '';
                    })
                  : null,
            ),
            children: [
              if (onlineVector != null)
                VectorTileLayer(
                  // Day and night are two Mapbox styles; vector, as the
                  // offline map, so labels stay upright when the map turns.
                  key: ValueKey(('online-vector', night)),
                  layerMode: VectorTileLayerMode.vector,
                  tileProviders: onlineVector.providers,
                  theme: onlineVector.theme,
                  sprites: onlineVector.sprites,
                  // Mapbox's vector tiles are made for 512 pixels: one zoom
                  // behind 256-pixel ones.
                  tileOffset: TileOffset.mapbox,
                  cacheFolder: mapCacheFolderFor(night ? -2 : -1),
                  fileCacheMaximumSizeInBytes: mapCacheMaxBytes,
                  // Traffic's max-age; navigation keeps the map's tiles
                  // for 12 h, so only traffic is fetched from Mapbox again.
                  fileCacheTtl: const Duration(seconds: 90),
                )
              else if (online && onlineStatus.vector)
                // Mapbox's style is still being read: the background for a
                // moment.
                const SizedBox.shrink()
              else if (online)
                TileLayer(
                  // Day and night are two Mapbox styles, not darkened tiles.
                  key: ValueKey(('online', night)),
                  tileProvider: OnlineTileProvider(
                    s.onlineMap,
                    night: night,
                    onResult: (ok, why) => _chooser.report(ok: ok, why: why),
                  ),
                  // Mapbox's 512-pixel tiles are one zoom behind 256-pixel ones.
                  tileDimension: onlineStatus.tileSize,
                  zoomOffset: onlineStatus.tileSize == 512 ? -1 : 0,
                  maxNativeZoom: onlineStatus.maxZoom + (onlineStatus.tileSize == 512 ? 1 : 0),
                  evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
                )
              else if (vector != null)
                VectorTileLayer(
                  // Day and night are two styles (ADR-0032), not darkened tiles.
                  key: ValueKey(('vector', night, vector.generation)),
                  // Drawn from the vectors on each change, not as cached
                  // pictures: the default raster mode draws every tile once
                  // unturned, so road names turned with the map and read
                  // upside down (heading up; bench-log 2026-11-13).
                  layerMode: VectorTileLayerMode.vector,
                  tileProviders: TileProviders({vectorSource: vector.provider}),
                  theme: vector.styles.forNight(night).theme,
                  sprites: vector.styles.forNight(night).sprites,
                  cacheFolder: mapCacheFolderFor(vector.generation),
                  fileCacheMaximumSizeInBytes: mapCacheMaxBytes,
                )
              else if (reader != null)
                TileLayer(
                  tileProvider: PmTilesTileProvider(reader),
                  minNativeZoom: header!.minZoom,
                  maxNativeZoom: header.maxZoom,
                  tileBuilder: night ? darkModeTileBuilder : null,
                ),
              if (onRoute && navRoute != null && navRoute.shape.length >= 2)
                PolylineLayer(
                  key: const ValueKey('nav-route-line'),
                  polylines: [
                    Polyline(
                      points: navRoute.shape,
                      strokeWidth: 6,
                      // Grey while it isn't being followed: an old route
                      // during rerouting, or no current position.
                      color: guiding ? p.accent : p.stale,
                      borderStrokeWidth: 2,
                      borderColor: p.background.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              if (destination != null || _pending != null)
                MarkerLayer(
                  markers: [
                    if (destination != null)
                      Marker(
                        point: destination,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        rotate: true, // upright on a turned map
                        child: Icon(
                          Icons.flag,
                          key: const ValueKey('nav-destination'),
                          size: 40,
                          color: p.critical,
                          semanticLabel: 'Destination',
                        ),
                      ),
                    if (_pending != null)
                      Marker(
                        point: _pending!,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        rotate: true, // upright on a turned map
                        child: Icon(
                          Icons.place,
                          key: const ValueKey('nav-pending'),
                          size: 44,
                          color: p.advisory,
                          semanticLabel: 'Chosen point',
                        ),
                      ),
                  ],
                ),
              if (fix != null && current && fix.errorM != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(fix.lat, fix.lon),
                      radius: fix.errorM!,
                      useRadiusInMeter: true,
                      color: p.accent.withValues(alpha: 0.12),
                      borderColor: p.accent.withValues(alpha: 0.5),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
              if (fix != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(fix.lat, fix.lon),
                      width: 48,
                      height: 48,
                      rotate: true, // upright; the arrow turns itself
                      child: _TruckMarker(fix: fix, current: current, palette: p),
                    ),
                  ],
                ),
              Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14, bottom: 34),
                  child: _Compass(palette: p),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          right: 84,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!current) _StatusRow(position: position, now: now, palette: p),
              if (onRoute) ...[
                if (!current) const SizedBox(height: kGap),
                _GuidanceBanner(
                  view: route,
                  route: routeFetched ? navRoute : null,
                  progress: guiding ? progress : null,
                  paused: current
                      ? (route.pausedWhy(routeNow) ?? (routeFetched ? null : 'loading the route'))
                      : 'no current position',
                  units: s.settings.units,
                  palette: p,
                ),
              ],
            ],
          ),
        ),
        if (bottomNotices.isNotEmpty)
          Positioned(
            left: 8,
            right: 84,
            bottom: 28,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, w) in bottomNotices.indexed) ...[
                  if (i > 0) const SizedBox(height: 6),
                  w,
                ],
              ],
            ),
          ),
        Positioned(
          right: 8,
          top: 8,
          child: Column(
            children: [
              _button('nav-zoom-in', 'Zoom in', Icons.add, () => _zoom(1, minZoom, maxZoom)),
              const SizedBox(height: kGap),
              _button('nav-zoom-out', 'Zoom out', Icons.remove, () => _zoom(-1, minZoom, maxZoom)),
              const SizedBox(height: kGap),
              _button(
                'nav-follow',
                _follow ? 'Following the truck' : 'Follow the truck',
                _follow ? Icons.my_location : Icons.location_searching,
                () {
                  setState(() => _follow = true);
                  _centre(force: true);
                },
                selected: _follow,
              ),
              const SizedBox(height: kGap),
              _button('nav-search-open', 'Search', Icons.search, () => setState(() => _searching = true)),
            ],
          ),
        ),
        if (mapProblem != null && onRoute)
          Positioned(
            left: 8,
            right: 84,
            bottom: 6,
            child: Text(
              mapProblem,
              key: const ValueKey('nav-map-problem'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: p.advisory),
            ),
          ),
        if (routingHint != null)
          Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              routingHint,
              key: const ValueKey('nav-routing'),
              style: TextStyle(fontSize: 12, color: p.textDim),
            ),
          ),
        // ODbL: whatever the map shows, its attribution is on screen. With
        // no map file, a route or destination still comes from
        // OpenStreetMap (the routing and search data): credit it too.
        if (attribution != null)
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: p.surface.withValues(alpha: 0.85),
              child: Text(
                attribution,
                key: const ValueKey('nav-attribution'),
                style: TextStyle(fontSize: 12, color: p.text),
              ),
            ),
          ),
        if (_searching)
          Positioned.fill(
            child: NavSearchPanel(
              source: s.search,
              initialQuery: _searchQuery,
              onQueryChanged: (q) => _searchQuery = q,
              canRoute: canRoute,
              moving: _moving(s, position, now),
              units: s.settings.units,
              onClose: () => setState(() => _searching = false),
              onShow: (r) => _show(r),
              onSave: (r) => setState(
                () => _editing = PlaceDraft(location: r.location, name: r.title, detail: r.subtitle),
              ),
              onRoute: (r) {
                setState(() {
                  _searching = false;
                  _pending = null;
                  _pendingName = null;
                  _follow = true;
                });
                s.route.setDestination(r.location, name: r.title, detail: r.subtitle);
                _centre(force: true);
              },
            ),
          ),
        if (_placesOpen)
          Positioned.fill(
            child: NavPlacesPanel(
              source: s.places,
              canRoute: canRoute,
              here: current && fix != null ? LatLng(fix.lat, fix.lon) : null,
              units: s.settings.units,
              onClose: () => setState(() => _placesOpen = false),
              onSearch: () => setState(() {
                _placesOpen = false;
                _searching = true;
              }),
              onEdit: (place) => setState(
                () => _editing = PlaceDraft(
                  location: place.location,
                  name: place.name,
                  detail: place.detail,
                  existing: place,
                ),
              ),
              onRoute: (place) {
                setState(() {
                  _placesOpen = false;
                  _pending = null;
                  _pendingName = null;
                  _follow = true;
                });
                s.route.setDestination(place.location, name: place.name, detail: place.detail);
                _centre(force: true);
              },
            ),
          ),
        if (_editing case final draft?)
          Positioned.fill(
            child: NavPlaceEditor(
              key: ValueKey(draft),
              draft: draft,
              source: s.places,
              moving: _moving(s, position, now),
              onClose: () => setState(() => _editing = null),
            ),
          ),
      ],
    );
  }

  /// A search result on the map, waiting for Route here or Cancel.
  void _show(SearchResult r) {
    setState(() {
      _searching = false;
      _pending = r.location;
      _pendingName = r.title;
      _pendingDetail = r.subtitle;
      _follow = false;
    });
    if (_ready) _map.move(r.location, math.max(_map.camera.zoom, NavigationScreen.followZoom));
  }

  /// A current speed says the truck is moving: the vehicle's, else the
  /// receiver's. Stale speeds say nothing (CLAUDE.md rule 4).
  static bool _moving(AppServices s, PositionState position, Duration now) {
    final vss = s.store['speed'];
    if (vss != null && vss.isValid && vss.value != null) return vss.value! >= NavigationScreen.movingKmh;
    final fix = position.report?.fix;
    if (position.isCurrent(now) && fix?.speedMps != null) {
      return fix!.speedMps! * 3.6 >= NavigationScreen.movingKmh;
    }
    return false;
  }

  static Color _updateColor(MapUpdateStatus u, Palette p) => switch (u.state) {
    MapUpdateState.failed => p.advisory,
    MapUpdateState.updated || MapUpdateState.current => p.ok,
    _ => p.accent,
  };

  Widget _textButton(String key, String label, IconData icon, VoidCallback onTap, {bool selected = false}) {
    return TapTarget(
      key: ValueKey(key),
      label: label,
      selected: selected,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _button(
    String key,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool selected = false,
  }) {
    return TapTarget(
      key: ValueKey(key),
      label: label,
      selected: selected,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Icon(icon, size: 30),
    );
  }
}

/// Over the map only while the fix isn't current (rule 4): "last known"
/// with its age, or no position, and why. A current fix needs no words:
/// the marker says it (owner, 2026-11-17: the fix type, satellites and
/// accuracy took room from the route).
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.position,
    required this.now,
    required this.palette,
  });

  final PositionState position;
  final Duration now;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final fix = position.report?.fix;
    final age = position.fixAge(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          key: const ValueKey('nav-status'),
          spacing: 6,
          runSpacing: 4,
          children: [
            if (fix != null && age != null)
              _Chip('LAST KNOWN · ${_age(age)} AGO', color: p.advisory, filled: true)
            else
              _Chip('NO POSITION', color: p.stale, filled: true),
          ],
        ),
        const SizedBox(height: 10),
        _Notice(
          key: const ValueKey('nav-why'),
          icon: Icons.gps_off,
          text: position.why(now),
          palette: p,
          color: p.advisory,
        ),
      ],
    );
  }
}

/// A status chip, larger than the gauges' pills: read at a glance while driving.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {super.key, required this.color, this.filled = false});

  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : p.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: filled ? p.background : color,
        ),
      ),
    );
  }
}

String _age(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} S';
  if (d.inMinutes < 60) return '${d.inMinutes} MIN';
  return '${d.inHours} H';
}

class _Notice extends StatelessWidget {
  const _Notice({
    super.key,
    required this.icon,
    required this.text,
    required this.palette,
    this.color,
  });

  final IconData icon;
  final String text;
  final Palette palette;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final c = color ?? p.textDim;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// An arrow along the course while moving, a dot while stopped; grey and
/// hollow when the fix isn't current.
class _TruckMarker extends StatelessWidget {
  const _TruckMarker({required this.fix, required this.current, required this.palette});

  final FixReport fix;
  final bool current;
  final Palette palette;

  /// Below this the course is noise.
  static const movingMps = 1.0;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final colour = current ? p.accent : p.stale;
    final track = fix.trackDeg;
    final moving = current && track != null && (fix.speedMps ?? 0) >= movingMps;
    // The marker stays upright; the arrow points along the course on the
    // map, however the map is turned.
    final mapTurn = MapCamera.maybeOf(context)?.rotation ?? 0;
    return Semantics(
      label: current ? 'Truck position' : 'Last known truck position',
      child: Container(
        key: ValueKey(current ? 'nav-marker-current' : 'nav-marker-stale'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: current ? p.surface : p.surface.withValues(alpha: 0.6),
          border: Border.all(color: colour, width: 3),
        ),
        child: moving
            ? Transform.rotate(
                key: const ValueKey('nav-marker-arrow'),
                angle: (track + mapTurn) * math.pi / 180,
                child: Icon(Icons.navigation, color: colour, size: 30),
              )
            : Icon(
                current ? Icons.circle : Icons.question_mark,
                color: colour,
                size: current ? 18 : 24,
              ),
      ),
    );
  }
}

/// Where north is on the turned map (heading up): the needle points north.
/// Shown always, so north up is visible as such too.
class _Compass extends StatelessWidget {
  const _Compass({required this.palette});
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final turn = MapCamera.maybeOf(context)?.rotation ?? 0;
    return Semantics(
      label: 'Compass: north is ${_bearingWords(turn)}',
      child: Container(
        key: const ValueKey('nav-compass'),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.surface.withValues(alpha: 0.92),
          border: Border.all(color: p.border, width: 1.5),
        ),
        child: Transform.rotate(
          key: const ValueKey('nav-compass-needle'),
          angle: turn * math.pi / 180,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('N', style: TextStyle(fontSize: 13, height: 1, fontWeight: FontWeight.w900, color: p.critical)),
              Icon(Icons.navigation, size: 22, color: p.critical),
            ],
          ),
        ),
      ),
    );
  }

  /// Up, right, down or left of the screen, for the screen reader.
  static String _bearingWords(double deg) {
    final d = (deg % 360 + 360) % 360;
    if (d < 45 || d >= 315) return 'up';
    if (d < 135) return 'to the right';
    if (d < 225) return 'down';
    return 'to the left';
  }
}

/// Guidance over the map while there is a destination: the next maneuver
/// with its distance and what is left, or why guidance is paused (never
/// distances that aren't current), and always the heavy-vehicle caveat.
/// As wide as its words, up to [maxWidth], so the route line beside it
/// stays in sight (owner, 2026-11-17).
class _GuidanceBanner extends StatelessWidget {
  /// Long instructions wrap to a second line rather than cross the map.
  static const maxWidth = 380.0;

  const _GuidanceBanner({
    required this.view,
    required this.route,
    required this.progress,
    required this.paused,
    required this.units,
    required this.palette,
  });

  final RouteView view;

  /// The route guidance names, once fetched.
  final NavRoute? route;

  /// Current progress on that route, or null.
  final RouteProgress? progress;

  /// Why guidance is paused on an active route, or null.
  final String? paused;
  final UnitSystem units;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final g = view.guidance!;
    final Widget body;
    switch (g.state) {
      case RouteState.routing:
        body = _line(
          Icons.route,
          g.reroutes > 0
              ? 'Off the route: finding a new one'
              // e.g. "Waiting for a current position to route from"
              : (g.detail.isNotEmpty ? g.detail : 'Finding a route…'),
          p.accent,
        );
      case RouteState.failed:
        body = _line(
          Icons.error_outline,
          'No route${g.detail.isEmpty ? '' : ': ${g.detail}'}',
          p.advisory,
        );
      case RouteState.arrived:
        body = _line(Icons.flag, 'Arrived', p.ok);
      case RouteState.active:
        final r = route;
        final pr = progress;
        if (r == null || pr == null || r.maneuvers.isEmpty) {
          body = _line(
            Icons.pause_circle_outline,
            'Guidance paused: ${paused ?? 'waiting for a current position'}',
            p.advisory,
          );
        } else {
          final m = r.maneuvers[pr.maneuverIndex.clamp(0, r.maneuvers.length - 1)];
          body = Row(
            key: const ValueKey('nav-guidance-active'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(maneuverIcon(m.type), size: 52, color: p.accent),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatDistance(pr.toManeuverM, units),
                      key: const ValueKey('nav-to-maneuver'),
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: p.text),
                    ),
                    Text(
                      m.instruction,
                      key: const ValueKey('nav-instruction'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.text),
                    ),
                    Text(
                      [
                        '${formatDistance(pr.remainingM, units)} · ${formatDuration(pr.remainingS)} left',
                        if (pr.offRoute) 'off the route',
                      ].join(' · '),
                      key: const ValueKey('nav-remaining'),
                      style: TextStyle(fontSize: 15, color: pr.offRoute ? p.advisory : p.textDim),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
      case RouteState.idle:
      case RouteState.unavailable:
        body = const SizedBox.shrink();
    }
    return Container(
      key: const ValueKey('nav-guidance'),
      constraints: const BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          const SizedBox(height: 4),
          // Where the route came from (ADR-0052).
          if (route case final r?)
            Text(
              r.online ? 'Mapbox route · live traffic' : 'Offline route',
              key: const ValueKey('nav-route-source'),
              style: TextStyle(fontSize: 13, color: p.textDim),
            ),
          // ADR-0010: OSM restriction data is incomplete.
          Text(
            'Not checked for heavy vehicles or trailers',
            key: const ValueKey('nav-heavy-warning'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.advisory),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 30, color: color),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          text,
          key: const ValueKey('nav-guidance-text'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: palette.text),
        ),
      ),
    ],
  );
}

/// A long-pressed point or a search result: Route here or Cancel.
class _PendingPanel extends StatelessWidget {
  const _PendingPanel({
    required this.at,
    required this.palette,
    required this.onRoute,
    required this.onSave,
    required this.onCancel,
    this.name,
    this.canRoute = true,
  });

  final LatLng at;

  /// A search result's name, shown instead of the coordinates.
  final String? name;

  /// Route here only while routing works (a search result can be shown
  /// without it).
  final bool canRoute;
  final Palette palette;
  final VoidCallback onRoute;

  /// Save it as a favourite or as Home (ADR-0040).
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    Widget button(String key, String label, IconData icon, VoidCallback onTap) => TapTarget(
      key: ValueKey(key),
      label: label,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 26),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('nav-pending-panel'),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.advisory),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          Icon(Icons.place, color: p.advisory, size: 26),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name ?? '${at.latitude.toStringAsFixed(4)}, ${at.longitude.toStringAsFixed(4)}',
              key: const ValueKey('nav-pending-text'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: p.text),
            ),
          ),
          if (canRoute) ...[
            const SizedBox(width: kGap),
            button('nav-route-here', 'Route here', Icons.directions, onRoute),
          ],
          const SizedBox(width: kGap),
          button('nav-pending-save', 'Save', Icons.star_border, onSave),
          const SizedBox(width: kGap),
          button('nav-route-cancel', 'Cancel', Icons.close, onCancel),
        ],
      ),
    );
  }
}

/// Valhalla's maneuver type (odin's DirectionsLeg_Maneuver_Type) as an icon.
IconData maneuverIcon(int type) => switch (type) {
  1 || 2 || 3 => Icons.trip_origin, // start
  4 || 5 || 6 => Icons.flag, // destination
  7 || 8 || 22 => Icons.straight, // becomes, continue, stay straight
  9 => Icons.turn_slight_right,
  10 => Icons.turn_right,
  11 => Icons.turn_sharp_right,
  12 => Icons.u_turn_right,
  13 => Icons.u_turn_left,
  14 => Icons.turn_sharp_left,
  15 => Icons.turn_left,
  16 => Icons.turn_slight_left,
  17 => Icons.straight, // ramp straight
  18 || 20 => Icons.ramp_right, // ramp right, exit right
  19 || 21 => Icons.ramp_left, // ramp left, exit left
  23 => Icons.fork_right, // stay right
  24 => Icons.fork_left, // stay left
  25 || 37 || 38 => Icons.merge,
  26 || 27 => Icons.roundabout_right,
  28 || 29 => Icons.directions_boat,
  _ => Icons.navigation,
};
