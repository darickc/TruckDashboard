import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../../cameras/camera_state.dart';
import '../../core/system_info.dart';
import '../../display/display_state.dart';
import '../../export/export_state.dart';
import '../../model/signal.dart';
import '../../model/units.dart';
import '../../nav/offline_map.dart';
import '../../nav/places_state.dart';
import '../../nav/position_state.dart';
import '../../nav/route_state.dart';
import '../../switch/switch_state.dart';
import '../../telemetry/telemetry_store.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../tone.dart';
import 'tap_target.dart';

/// One service's line: its name, its state in a word or two, and a tone.
@immutable
class ServiceRow {
  const ServiceRow(this.id, this.name, this.state, this.tone);

  final String id;
  final String name;
  final String state;
  final HomeTone tone;

  @override
  String toString() => 'ServiceRow($id: "$state", $tone)';
}

String _vehicleLink(LinkState l) => switch (l) {
      LinkState.connecting => 'connecting',
      LinkState.up => 'link up',
      LinkState.degraded => 'degraded',
      LinkState.down => 'link down',
    };

/// Every service the dashboard talks to, as it last heard from each: the
/// links it already follows, gathered in one place. Simulated sources say
/// so; nothing here is checked anew.
List<ServiceRow> serviceRows(AppServices s) {
  final store = s.store;
  final cams = s.cameras.status.value;
  final audio = s.audio.status.value;
  final display = s.display.status.value;
  final position = s.position.status.value;
  final route = s.route.state.value;
  final places = s.places.state.value;
  final export = s.exports.status.value;
  final map = s.map.state.value;
  return [
    store.source.simulated
        ? const ServiceRow('vehicle', 'Vehicle data', 'in-app simulator', HomeTone.simulated)
        : ServiceRow('vehicle', 'Vehicle data', _vehicleLink(store.link), switch (store.link) {
            LinkState.up => HomeTone.ok,
            LinkState.degraded => HomeTone.advisory,
            LinkState.down => HomeTone.critical,
            LinkState.connecting => HomeTone.stale,
          }),
    switch (cams.link) {
      CameraLink.up when cams.simulated => const ServiceRow('cameras', 'Cameras', 'simulated', HomeTone.simulated),
      CameraLink.up => const ServiceRow('cameras', 'Cameras', 'connected', HomeTone.ok),
      CameraLink.connecting => const ServiceRow('cameras', 'Cameras', 'connecting', HomeTone.stale),
      CameraLink.down => const ServiceRow('cameras', 'Cameras', 'not reachable', HomeTone.advisory),
    },
    switch (audio.link) {
      AudioLink.up when audio.report?.simulated ?? false =>
        const ServiceRow('audio', 'Audio and phone', 'simulated', HomeTone.simulated),
      AudioLink.up => const ServiceRow('audio', 'Audio and phone', 'connected', HomeTone.ok),
      AudioLink.connecting => const ServiceRow('audio', 'Audio and phone', 'connecting', HomeTone.stale),
      AudioLink.down => const ServiceRow('audio', 'Audio and phone', 'not reachable', HomeTone.advisory),
    },
    switch (display.link) {
      DisplayLink.simulated => const ServiceRow('power', 'Power manager', 'simulated', HomeTone.simulated),
      DisplayLink.connecting => const ServiceRow('power', 'Power manager', 'connecting', HomeTone.stale),
      DisplayLink.connected => const ServiceRow('power', 'Power manager', 'connected', HomeTone.ok),
      DisplayLink.lost => const ServiceRow('power', 'Power manager', 'not reachable', HomeTone.advisory),
    },
    switch (position.link) {
      PositionLink.connected when position.report?.simulated ?? false =>
        const ServiceRow('gps', 'GPS position', 'simulated', HomeTone.simulated),
      PositionLink.connected => const ServiceRow('gps', 'GPS position', 'connected', HomeTone.ok),
      PositionLink.connecting => const ServiceRow('gps', 'GPS position', 'connecting', HomeTone.stale),
      PositionLink.lost => const ServiceRow('gps', 'GPS position', 'not reachable', HomeTone.advisory),
    },
    route.state == RouteState.unavailable
        ? const ServiceRow('routing', 'Routing', 'not available', HomeTone.dim)
        : switch (route.link) {
            RouteLink.connected => const ServiceRow('routing', 'Routing', 'connected', HomeTone.ok),
            RouteLink.connecting => const ServiceRow('routing', 'Routing', 'connecting', HomeTone.stale),
            RouteLink.lost => const ServiceRow('routing', 'Routing', 'not reachable', HomeTone.advisory),
          },
    switch (places.link) {
      PlacesLink.connected => const ServiceRow('places', 'Saved places', 'connected', HomeTone.ok),
      PlacesLink.connecting => const ServiceRow('places', 'Saved places', 'connecting', HomeTone.stale),
      PlacesLink.lost => const ServiceRow('places', 'Saved places', 'not available', HomeTone.dim),
    },
    switch (export.link) {
      ExportLink.up when export.simulated => const ServiceRow('export', 'USB export', 'simulated', HomeTone.simulated),
      ExportLink.up => const ServiceRow('export', 'USB export', 'connected', HomeTone.ok),
      ExportLink.connecting => const ServiceRow('export', 'USB export', 'connecting', HomeTone.stale),
      ExportLink.down => const ServiceRow('export', 'USB export', 'not reachable', HomeTone.advisory),
    },
    switch (map) {
      MapReady() => const ServiceRow('map', 'Map', 'loaded', HomeTone.ok),
      MapLoading() => const ServiceRow('map', 'Map', 'opening', HomeTone.stale),
      MapUnavailable() => const ServiceRow('map', 'Map', 'no map file', HomeTone.dim),
    },
  ];
}

/// What Settings › System's switch row says about the directions.
String switchState(SwitchStatus s) {
  final r = s.report;
  if (!s.usable || r == null) return 'power-manager not connected';
  if (r.learning) return 'setting up';
  return r.defaultMapping ? 'default directions' : 'directions set';
}

/// Settings › System: what the head unit says about itself on the left,
/// every service's link on the right. Read again every few seconds while it
/// shows; nothing is kept.
class SystemSettings extends StatefulWidget {
  const SystemSettings({super.key, this.refresh = const Duration(seconds: 5), this.onSwitch});

  final Duration refresh;

  /// Opens the 5-way switch's directions (ADR-0051); no button without it.
  final VoidCallback? onSwitch;

  @override
  State<SystemSettings> createState() => _SystemSettingsState();
}

class _SystemSettingsState extends State<SystemSettings> {
  SystemFacts? _facts;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(widget.refresh, (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final f = await AppScope.of(context).systemInfo.read();
    if (mounted) setState(() => _facts = f);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.store,
        s.settings,
        s.cameras.status,
        s.audio.status,
        s.display.status,
        s.switchSource.status,
        s.position.status,
        s.route.state,
        s.places.state,
        s.exports.status,
        s.map.state,
      ]),
      builder: (context, _) {
        final f = _facts;
        final units = s.settings.units;
        String show<T>(Fact<T>? fact, String Function(T v) text) =>
            fact == null ? 'reading…' : (fact.known ? text(fact.value as T) : 'not available: ${fact.why}');
        final drive = s.cameras.status.value;
        final rec = drive.link == CameraLink.up ? drive.recording : null;
        // camera-manager says nothing of the drive while no camera is set
        // to record: unknown then, not "not mounted" (bench 2026-11-19).
        final driveText = rec == null
            ? 'not reported (needs camera-manager)'
            : rec.isOff
                ? 'not reported while recording is off'
                : rec.driveMounted
                ? '${formatGb(rec.driveFreeBytes)} free · video ${formatGb(rec.recordedBytes)}'
                    '${drive.simulated ? ' (simulated)' : ''}'
                : 'not mounted';
        final temp = f?.cpuTemperature;
        final tempLabel = temp != null && temp.known && !temp.value!.zone.contains('cpu') && temp.value!.zone.isNotEmpty
            ? 'Temperature (${temp.value!.zone})'
            : 'CPU temperature';
        final unit = displayUnitFor(Quantity.temperature, units);
        Widget fact(String key, String label, String value, {bool known = true}) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 15, color: p.textDim))),
                // A label that fills its width (the panel's font) still
                // keeps apart from its value.
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value,
                      key: ValueKey('system-$key'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: known ? 15 : 13,
                          fontWeight: known ? FontWeight.w600 : FontWeight.w400,
                          fontFeatures: tabular,
                          color: known ? p.text : p.textDim)),
                ),
              ]),
            );
        Widget heading(String t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: p.textDim)),
            );
        final rows = serviceRows(s);
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            // Six short rows: all built, scrolling only when they outgrow it.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // The switch's directions open from here (ADR-0051): a row
              // that says where it leads and whether they are set, not a
              // fifth section button (it wouldn't fit the section row).
              if (widget.onSwitch != null) ...[
                TapTarget(
                  key: const ValueKey('system-switch'),
                  label: 'Set up the 5-way switch',
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: widget.onSwitch!,
                  child: Row(children: [
                    Text('5-way switch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(switchState(s.switchSource.status.value),
                          key: const ValueKey('system-switch-state'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.textDim)),
                    ),
                    Icon(Icons.chevron_right, size: 24, color: p.textDim),
                  ]),
                ),
                const SizedBox(height: 10),
              ],
              heading('THIS HEAD UNIT'),
              fact('dashboard', 'Dashboard', show(f?.dashboard, (v) => v), known: f?.dashboard.known ?? false),
              fact('image', 'Image', show(f?.image, (v) => v), known: f?.image.known ?? false),
              fact('commit', 'Image built from', show(f?.commit, (v) => 'commit $v'),
                  known: f?.commit.known ?? false),
              fact('uptime', 'Up for', show(f?.uptime, formatUptime), known: f?.uptime.known ?? false),
              fact(
                  'temperature',
                  tempLabel,
                  show(temp, (v) => '${unit.convert(v.celsius).toStringAsFixed(0)} ${unit.label}'),
                  known: temp?.known ?? false),
              fact('drive', 'Data drive', driveText, known: rec != null && !rec.isOff && rec.driveMounted),
              ]),
            ),
          ),
          VerticalDivider(width: 24, color: p.border),
          SizedBox(
            width: 330,
            // Nine short rows: all built, scrolling only under an alert.
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              heading('SERVICES'),
              for (final r in rows)
                Container(
                  key: ValueKey('system-service-${r.id}'),
                  margin: const EdgeInsets.only(bottom: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: homeToneColor(r.tone, p), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text))),
                    Text(r.state,
                        key: ValueKey('system-state-${r.id}'),
                        style: TextStyle(
                            fontSize: 13, color: r.tone == HomeTone.dim ? p.textDim : homeToneColor(r.tone, p))),
                  ]),
                ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}
