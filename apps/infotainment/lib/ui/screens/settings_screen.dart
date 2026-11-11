import 'package:flutter/material.dart';

import '../../cameras/camera_settings.dart';
import '../../cameras/camera_state.dart';
import '../../model/units.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/display_settings.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

/// The driver's settings (ADR-0029): Display (power-manager, ADR-0028),
/// Cameras (camera-manager: which USB port is which camera, and which
/// record), Units (the dashboard's own, kept in its settings file).
enum SettingsSection { display, cameras, units }

const _labels = {
  SettingsSection.display: 'Display',
  SettingsSection.cameras: 'Cameras',
  SettingsSection.units: 'Units',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  var _section = SettingsSection.display;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: kMinTouch,
        child: Row(children: [
          for (final (i, d) in SettingsSection.values.indexed) ...[
            if (i > 0) const SizedBox(width: kGap),
            Expanded(
              child: TapTarget(
                key: ValueKey('settings-${d.name}'),
                label: _labels[d]!,
                selected: d == _section,
                padding: EdgeInsets.zero,
                onTap: () => setState(() => _section = d),
                child: Text(_labels[d]!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ]),
      ),
      const SizedBox(height: kGap),
      Expanded(
        child: Panel(
          padding: const EdgeInsets.all(8),
          child: switch (_section) {
            SettingsSection.display => ListView(children: const [DisplaySettings()]),
            SettingsSection.cameras => const CameraSettingsView(),
            SettingsSection.units => const _Units(),
          },
        ),
      ),
    ]);
  }
}

class _Units extends StatelessWidget {
  const _Units();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: s.settings,
      builder: (context, _) {
        Widget option(UnitSystem u, String text) => SizedBox(
              width: 150,
              child: TapTarget(
                  key: ValueKey('units-${u.name}'),
                  label: text,
                  selected: s.settings.units == u,
                  onTap: () => s.settings.units = u,
                  child: Text(text, style: const TextStyle(fontSize: 16))),
            );
        return ListView(children: [
          Row(children: [
            option(UnitSystem.imperial, 'Imperial'),
            const SizedBox(width: kGap),
            option(UnitSystem.metric, 'Metric'),
          ]),
          const SizedBox(height: 6),
          Text('°F, psi, mph (Imperial) or °C, kPa, km/h (Metric). Kept on this head unit.',
              style: TextStyle(fontSize: 14, color: p.textDim)),
        ]);
      },
    );
  }
}

/// Which USB port is which camera, and which record (ADR-0029 decisions
/// 3–5). Changes are a draft until Apply, which restarts camera-manager; it
/// is offered only when something changed. Reads the settings again
/// whenever camera-manager (re)connects.
class CameraSettingsView extends StatefulWidget {
  const CameraSettingsView({super.key});

  @override
  State<CameraSettingsView> createState() => _CameraSettingsViewState();
}

class _CameraSettingsViewState extends State<CameraSettingsView> {
  CameraSettingsSnapshot? _snap;
  CameraSettings? _draft;
  String? _error;
  String? _message;
  bool _busy = false;

  /// The camera whose device is being picked.
  CameraId? _picking;
  CameraLink? _lastLink;
  late CameraSource _cameras;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cameras = AppScope.of(context).cameras;
    _cameras.status.removeListener(_onStatus);
    _cameras.status.addListener(_onStatus);
    if (_lastLink == null) {
      _lastLink = _cameras.status.value.link;
      if (_lastLink == CameraLink.up) _read();
    }
  }

  @override
  void dispose() {
    _cameras.status.removeListener(_onStatus);
    super.dispose();
  }

  void _onStatus() {
    final link = _cameras.status.value.link;
    final was = _lastLink;
    _lastLink = link;
    if (link == CameraLink.up && was != CameraLink.up) _read(keepMessage: true);
    if (link != CameraLink.up && was == CameraLink.up && mounted) setState(() => _picking = null);
  }

  Future<void> _read({bool keepMessage = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!keepMessage) _message = null;
    });
    try {
      final snap = await _cameras.getSettings();
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _draft = snap.settings;
        _picking = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Camera settings can\'t be read: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply(CameraSettings? settings) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _cameras.setSettings(settings);
      if (!mounted) return;
      setState(() => _message = r.detail);
      // Applied: the link drops and comes back, and _onStatus reads them
      // again. The simulation doesn't drop: read now.
      if (r.applied && _cameras.status.value.link == CameraLink.up) await _read(keepMessage: true);
    } catch (e) {
      if (mounted) setState(() => _message = 'Not applied: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder<CameraStatus>(
      valueListenable: _cameras.status,
      builder: (context, status, _) {
        final note = TextStyle(fontSize: 14, color: p.textDim);
        if (status.link != CameraLink.up) {
          return Text(
              'camera-manager not connected${status.detail == null ? '' : ' (${status.detail})'}: '
              'the camera settings can\'t be read or changed.',
              key: const ValueKey('cam-settings-detail'),
              style: TextStyle(fontSize: 15, color: p.advisory));
        }
        final snap = _snap;
        final draft = _draft;
        if (_error != null || snap == null || draft == null) {
          return Text(_error ?? 'Reading the camera settings…',
              key: const ValueKey('cam-settings-detail'),
              style: TextStyle(fontSize: 15, color: _error == null ? p.textDim : p.advisory));
        }
        final picking = _picking;
        if (picking != null) return _picker(picking, snap, draft, p);
        final changed = !draft.sameChoices(snap.settings);
        // Left: the four cameras (they fit at 800×480 without scrolling).
        // Right: what applies, Apply and what it did, then the rest.
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ListView(children: [
              for (final c in CameraId.values) ...[
                _row(c, snap, draft, p),
                const SizedBox(height: 6),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 230,
            child: ListView(children: [
              Text(
                  snap.settings.source == SettingsSource.screen
                      ? 'Set on this screen.'
                      : 'From /etc/default/f250.',
                  key: const ValueKey('cam-source'),
                  style: note),
              const SizedBox(height: 6),
              _button('cam-apply', 'Apply', changed && !_busy ? () => _apply(draft) : null,
                  width: 230, emphasis: changed),
              const SizedBox(height: 4),
              Text(
                  _message ??
                      (changed
                          ? 'Apply restarts camera-manager: the cameras are off for a few seconds.'
                          : 'Plug a camera in, Rescan, then give its USB port a camera.'),
                  key: const ValueKey('cam-settings-detail'),
                  style: TextStyle(fontSize: 14, color: _message == null ? p.textDim : p.text)),
              const SizedBox(height: 6),
              Row(children: [
                _button('cam-revert', 'Undo',
                    changed && !_busy ? () => setState(() => _draft = snap.settings) : null,
                    width: 111),
                const SizedBox(width: kGap),
                _button('cam-rescan', 'Rescan', _busy ? null : () => _read(), width: 111),
              ]),
              if (snap.settings.source == SettingsSource.screen) ...[
                const SizedBox(height: 6),
                _button('cam-defaults', 'Use /etc/default/f250', _busy ? null : () => _apply(null),
                    width: 230),
              ],
              if (!draft.canRecord) ...[
                const SizedBox(height: 6),
                Text('Recording: ${draft.recordingUnavailable}',
                    key: const ValueKey('cam-recording-unavailable'),
                    style: TextStyle(fontSize: 14, color: p.advisory)),
              ],
            ]),
          ),
        ]);
      },
    );
  }

  /// One camera: its device (tap to change) and, for front and rear, Record.
  Widget _row(CameraId c, CameraSettingsSnapshot snap, CameraSettings draft, Palette p) {
    final device = draft.devices[c];
    final plugged = snap.plugged.where((d) => d.path == device).firstOrNull;
    final text = device == null
        ? 'None'
        : plugged != null
            ? _describe(plugged)
            : '${CameraDevice(path: device).port}: not plugged in';
    final missing = device != null && plugged == null;
    return Row(children: [
      SizedBox(
          width: 70,
          child: Text(cameraShortName(c),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
      Expanded(
        child: TapTarget(
          key: ValueKey('cam-device-${c.name}'),
          label: '${cameraName(c)} device: $text. Change',
          onTap: () => setState(() => _picking = c),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: missing ? p.advisory : p.text)),
          ),
        ),
      ),
      const SizedBox(width: kGap),
      SizedBox(
        width: 130,
        child: recordable.contains(c)
            ? TapTarget(
                key: ValueKey('cam-record-${c.name}'),
                label: 'Record the ${cameraName(c).toLowerCase()}',
                selected: draft.record.contains(c),
                onTap: () => setState(() => _draft = draft.withRecord(c, !draft.record.contains(c))),
                child: Text(draft.record.contains(c) ? 'Record: on' : 'Record: off',
                    style: const TextStyle(fontSize: 15)),
              )
            : Center(child: Text('Not recorded', style: TextStyle(fontSize: 13, color: p.textDim))),
      ),
    ]);
  }

  /// None and Cancel, then the devices plugged in now.
  Widget _picker(CameraId c, CameraSettingsSnapshot snap, CameraSettings draft, Palette p) {
    String? owner(CameraDevice d) =>
        draft.devices.entries.where((e) => e.value == d.path && e.key != c).firstOrNull?.key.name;
    return ListView(children: [
      Row(children: [
        Expanded(
          child: Text('${cameraName(c)}: which USB port?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
        ),
        SizedBox(
          width: 110,
          child: TapTarget(
            key: const ValueKey('cam-pick-none'),
            label: 'No ${cameraName(c).toLowerCase()}',
            selected: draft.devices[c] == null,
            padding: EdgeInsets.zero,
            onTap: () => setState(() {
              _draft = draft.withDevice(c, null);
              _picking = null;
            }),
            child: const Text('None', style: TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(width: kGap),
        _button('cam-pick-cancel', 'Cancel', () => setState(() => _picking = null), width: 110),
      ]),
      const SizedBox(height: 6),
      if (snap.plugged.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('No cameras plugged in. Plug one in, then Rescan.',
              style: TextStyle(fontSize: 14, color: p.advisory)),
        ),
      for (final (i, d) in snap.plugged.indexed) ...[
        TapTarget(
          key: ValueKey('cam-pick-$i'),
          label: _describe(d),
          selected: draft.devices[c] == d.path,
          onTap: () => setState(() {
            _draft = draft.withDevice(c, d.path);
            _picking = null;
          }),
          child: Row(children: [
            Expanded(
                child: Text(_describe(d),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
            if (owner(d) case final o?)
              Text('now $o; moves here', style: TextStyle(fontSize: 13, color: p.advisory)),
          ]),
        ),
        const SizedBox(height: 6),
      ],
    ]);
  }

  String _describe(CameraDevice d) => d.label.isEmpty ? d.port : '${d.port} · ${d.label}';

  Widget _button(String key, String text, VoidCallback? onTap,
      {required double width, bool emphasis = false}) {
    final p = Palette.of(context);
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: TapTarget(
          key: ValueKey(key),
          label: onTap == null ? '$text (unavailable)' : text,
          selected: emphasis,
          padding: EdgeInsets.zero,
          onTap: onTap ?? () {},
          child: Text(text, style: TextStyle(fontSize: 15, color: p.text)),
        ),
      ),
    );
  }
}
