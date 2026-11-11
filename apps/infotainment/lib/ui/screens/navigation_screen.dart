import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../nav/offline_map.dart';
import '../../nav/position_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

/// The offline map and the truck's position (Phase 6.4 and 6.5.1,
/// ADR-0030). North up. It follows the truck until the map is dragged;
/// the locate button follows again.
///
/// Honest about what it knows: a fix that isn't current is drawn grey and
/// labelled "last known" with its age (CLAUDE.md rule 4), a simulated
/// position says so, a missing map says why, and routing says it isn't
/// implemented yet.
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

  /// Keeps the truck in the middle while following.
  void _centre({bool force = false}) {
    if (!_ready || !_follow) return;
    final fix = _source?.status.value.report?.fix;
    if (fix == null) return;
    final at = LatLng(fix.lat, fix.lon);
    if (!force && at == _lastCentered) return;
    _lastCentered = at;
    final zoom = force && _map.camera.zoom < 10 ? NavigationScreen.followZoom : _map.camera.zoom;
    _map.move(at, zoom);
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
            valueListenable: s.position.status,
            builder: (context, position, _) =>
                _build(context, p, mapState, position, s.position.clock.now()),
          ),
        ),
      ),
    );
  }

  Widget _build(
    BuildContext context,
    Palette p,
    MapFileState mapState,
    PositionState position,
    Duration now,
  ) {
    final reader = mapState is MapReady ? mapState.reader : null;
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
            ),
            children: [
              if (reader != null)
                TileLayer(
                  tileProvider: PmTilesTileProvider(reader),
                  minNativeZoom: header!.minZoom,
                  maxNativeZoom: header.maxZoom,
                  tileBuilder: night ? darkModeTileBuilder : null,
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
          child: _StatusRow(position: position, now: now, current: current, palette: p),
        ),
        if (mapState is! MapReady)
          Positioned(
            left: 8,
            right: 84,
            bottom: 36,
            child: _Notice(
              key: const ValueKey('nav-map-problem'),
              icon: Icons.layers_clear_outlined,
              text: switch (mapState) {
                MapLoading() => 'Opening the offline map…',
                MapUnavailable(:final why) => 'No map: $why. The position is still shown.',
                MapReady() => '',
              },
              palette: p,
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
        Positioned(
          left: 8,
          bottom: 6,
          child: Text(
            'Routing: not implemented yet (6.5.2)',
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
                reader.attribution ?? '© OpenStreetMap contributors',
                key: const ValueKey('nav-attribution'),
                style: TextStyle(fontSize: 12, color: p.text),
              ),
            ),
          ),
      ],
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
