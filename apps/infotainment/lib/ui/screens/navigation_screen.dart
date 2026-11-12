import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../nav/map_cache.dart';
import '../../nav/map_update.dart';
import '../../nav/offline_map.dart';
import '../../model/units.dart';
import '../../nav/position_state.dart';
import '../../nav/route_state.dart';
import '../../nav/vector_map.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

/// The offline map, the truck's position and routing (Phase 6.4, 6.5.1 and
/// 6.5.2; ADR-0030, vector maps ADR-0032, routing ADR-0035). North up. It
/// follows the truck until the map is dragged; the locate button follows
/// again. Long-press the map to choose a destination.
///
/// Honest about what it knows: a fix that isn't current is drawn grey and
/// labelled "last known" with its age (CLAUDE.md rule 4), a simulated
/// position says so, a missing map says why, guidance pauses (no distances)
/// without a current position, and every route says it isn't checked for
/// heavy vehicles or trailers (ADR-0010).
class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  /// Where the map opens without a fix or a tileset: the middle of the
  /// contiguous United States.
  static const fallbackCenter = LatLng(39.83, -98.58);
  static const fallbackZoom = 4.0;

  /// The default zoom once a fix arrives.
  static const followZoom = 15.0;

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final _map = MapController();
  bool _ready = false;
  bool _follow = true;
  Timer? _tick;
  PositionSource? _source;
  LatLng? _lastCentered;

  /// A long-pressed point waiting for Route here or Cancel.
  LatLng? _pending;

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

  @override
  void dispose() {
    _tick?.cancel();
    _source?.status.removeListener(_onPosition);
    _map.dispose();
    super.dispose();
  }

  void _onPosition() => _centre();

  /// While a route's banner covers the top of the map, the truck is kept
  /// this far below the middle so the banner never hides it.
  static const _belowBanner = Offset(0, 60);
  bool _lowered = false;

  /// Keeps the truck in the middle (lower while routing) while following.
  void _centre({bool force = false}) {
    if (!_ready || !_follow) return;
    final fix = _source?.status.value.report?.fix;
    if (fix == null) return;
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
                  listenable: s.settings,
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
    final minZoom = math.max(2.0, (header?.minZoom ?? 2).toDouble());
    final maxZoom = math.min(19.0, (header?.maxZoom ?? 17) + 2.0); // up to two zooms of overzoom
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
    final night = Theme.of(context).brightness == Brightness.dark;

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
    final canRoute =
        route.link == RouteLink.connected &&
        routeState != null &&
        routeState != RouteState.unavailable;
    final mapProblem = switch (mapState) {
      MapLoading() => 'Opening the offline map…',
      MapUnavailable(:final why) => 'No map: $why. The position is still shown.',
      MapReady() => null,
    };
    final bottomNotices = <Widget>[
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
          palette: p,
          onRoute: () {
            final to = _pending!;
            setState(() {
              _pending = null;
              _follow = true;
            });
            s.route.setDestination(to);
            _centre(force: true);
          },
          onCancel: () => setState(() => _pending = null),
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
                () => s.route.setDestination(destination),
              ),
              const SizedBox(width: kGap),
            ],
            _textButton('nav-end-route', 'End route', Icons.close, () => s.route.clearRoute()),
          ],
        ),
    ];
    final routingHint = switch ((route.link, routeState)) {
      (_, RouteState.unavailable) => 'Routing unavailable: ${route.guidance!.detail}',
      (RouteLink.connecting, null) => 'Routing: connecting to the navigation service…',
      (RouteLink.lost, null) =>
        'Routing unavailable: navigation service unavailable${route.detail.isEmpty ? '' : ': ${route.detail}'}',
      (_, RouteState.idle) => 'Long-press the map to route',
      _ => null,
    };

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            key: ValueKey(header), // a new tileset rebuilds the map with its zooms
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
              onLongPress: canRoute ? (_, at) => setState(() => _pending = at) : null,
            ),
            children: [
              if (vector != null)
                VectorTileLayer(
                  // Day and night are two styles (ADR-0032), not darkened tiles.
                  key: ValueKey(('vector', night, vector.generation)),
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
                      child: _TruckMarker(fix: fix, current: current, palette: p),
                    ),
                  ],
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
              _StatusRow(position: position, now: now, current: current, palette: p),
              if (onRoute) ...[
                const SizedBox(height: kGap),
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
        // ODbL: whatever the map shows, its attribution is on screen.
        if (reader != null)
          Positioned(
            right: 8,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: p.surface.withValues(alpha: 0.85),
              child: Text(
                [
                  reader.attribution ?? '© OpenStreetMap contributors',
                  if (reader.dataDate != null) 'data ${reader.dataDate}',
                ].join(' · '),
                key: const ValueKey('nav-attribution'),
                style: TextStyle(fontSize: 12, color: p.text),
              ),
            ),
          ),
      ],
    );
  }

  static Color _updateColor(MapUpdateStatus u, Palette p) => switch (u.state) {
    MapUpdateState.failed => p.advisory,
    MapUpdateState.updated || MapUpdateState.current => p.ok,
    _ => p.accent,
  };

  Widget _textButton(String key, String label, IconData icon, VoidCallback onTap) {
    return TapTarget(
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

/// What the receiver says, in one row over the map.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.position,
    required this.now,
    required this.current,
    required this.palette,
  });

  final PositionState position;
  final Duration now;
  final bool current;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final r = position.report;
    final fix = r?.fix;
    final age = position.fixAge(now);
    final chips = <Widget>[
      if (current)
        _Chip(r!.status == FixStatus.fix3d ? '3D FIX' : '2D FIX', color: p.ok, filled: true)
      else if (fix != null && age != null)
        _Chip('LAST KNOWN · ${_age(age)} AGO', color: p.advisory, filled: true)
      else
        _Chip('NO POSITION', color: p.stale, filled: true),
      if (r?.simulated ?? false) _Chip('SIMULATED', color: p.simulated, filled: true),
      if (current && r?.satellitesUsed != null)
        _Chip('${r!.satellitesUsed} SATS', color: p.textDim),
      if (current && fix?.errorM != null) _Chip('±${fix!.errorM!.round()} m', color: p.textDim),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(key: const ValueKey('nav-status'), spacing: 6, runSpacing: 4, children: chips),
        if (!current) ...[
          const SizedBox(height: 10),
          _Notice(
            key: const ValueKey('nav-why'),
            icon: Icons.gps_off,
            text: position.why(now),
            palette: p,
            color: p.advisory,
          ),
        ],
      ],
    );
  }
}

/// A status chip, larger than the gauges' pills: read at a glance while driving.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {required this.color, this.filled = false});

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
                angle: track * math.pi / 180,
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

/// Guidance over the map while there is a destination: the next maneuver
/// with its distance and what is left, or why guidance is paused (never
/// distances that aren't current), and always the heavy-vehicle caveat.
class _GuidanceBanner extends StatelessWidget {
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
            children: [
              Icon(maneuverIcon(m.type), size: 52, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
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

/// A long-pressed point: Route here or Cancel.
class _PendingPanel extends StatelessWidget {
  const _PendingPanel({
    required this.at,
    required this.palette,
    required this.onRoute,
    required this.onCancel,
  });

  final LatLng at;
  final Palette palette;
  final VoidCallback onRoute;
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
              '${at.latitude.toStringAsFixed(4)}, ${at.longitude.toStringAsFixed(4)}',
              key: const ValueKey('nav-pending-text'),
              style: TextStyle(fontSize: 15, color: p.text),
            ),
          ),
          const SizedBox(width: kGap),
          button('nav-route-here', 'Route here', Icons.directions, onRoute),
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
