import 'package:flutter/material.dart';

import '../../cameras/camera_settings.dart';
import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../shell/nav_buttons.dart';
import '../theme.dart';
import '../widgets/display_settings.dart';
import '../widgets/panel.dart';
import '../widgets/power_buttons.dart';
import '../widgets/speaker_settings.dart';
import '../widgets/system_settings.dart';
import '../widgets/tap_target.dart';

/// The driver's settings (ADR-0029): Display (power-manager, ADR-0028),
/// Cameras (camera-manager: which USB port is which camera, and which
/// record), Speakers (audio-manager: fader, balance, sub level, crossover;
/// ADR-0039), System (what the head unit says about itself and every
/// service's link, 2026-11-18). Display also holds Units (the dashboard's
/// own, kept in its settings file; its own section until 2026-11-18). After
/// the sections, Diagnostics (a screen of its own, opened from here rather
/// than Home). Restart and Power, when the launcher offers them, at the
/// right.
enum SettingsSection { display, cameras, speakers, system }

/// The Diagnostics button's width in the section row.
const kDiagnosticsButtonWidth = 150.0;

const _labels = {
  SettingsSection.display: 'Display',
  SettingsSection.cameras: 'Cameras',
  SettingsSection.speakers: 'Speakers',
  SettingsSection.system: 'System',
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
      // Restart and Power at the right of the sections: the driver's only
      // way to shut down before key-off.
      PowerRow(
        leading: Row(children: [
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
          const SizedBox(width: kGap),
          // Not a section: it opens Diagnostics, whose Back returns here.
          // Wide enough for its icon and word at full size in the panel's
          // font (DejaVu Sans Bold on AGL); scales down rather than clip.
          SizedBox(
            width: kDiagnosticsButtonWidth,
            child: TapTarget(
              key: const ValueKey('settings-diagnostics'),
              label: 'Open Diagnostics',
              padding: const EdgeInsets.symmetric(horizontal: 6),
              onTap: () => AppScope.of(context).screens.open(AppScreen.diagnostics),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(screenIcons[AppScreen.diagnostics], size: 20, color: Palette.of(context).text),
                  const SizedBox(width: 4),
                  const Text('Diagnostics', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: kGap),
      Expanded(
        child: Panel(
          padding: const EdgeInsets.all(8),
          child: switch (_section) {
            SettingsSection.display => ListView(padding: const EdgeInsets.all(6), children: [
                const DisplaySettings(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1, color: Palette.of(context).border),
                ),
                const UnitsSettings(),
              ]),
            SettingsSection.cameras => const CameraSettingsView(),
            SettingsSection.speakers => const SpeakerSettingsView(),
            SettingsSection.system => const SystemSettings(),
          },
        ),
      ),
    ]);
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
        final detail = _message ??
            (changed
                ? 'Apply restarts camera-manager: the cameras are off for a few seconds.'
                : 'Plug a camera in, Rescan, then give its USB port a camera.');
        // A card per camera, front and rear (the two that record) on top;
        // under them why nothing records, if so; then what applies and the
        // buttons in one row. Under an alert banner it scrolls instead of
        // squeezing the 60 px controls (design review, 2026-11-19).
        Widget pair(CameraId a, CameraId b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _card(a, snap, draft, p)),
              const SizedBox(width: kGap),
              Expanded(child: _card(b, snap, draft, p)),
            ]);
        final bottom = SizedBox(
          height: kMinTouch,
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(detail,
                        key: const ValueKey('cam-settings-detail'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _message == null && !changed ? p.textDim : p.text)),
                    Text(
                        snap.settings.source == SettingsSource.screen
                            ? 'Set on this screen.'
                            : 'From /etc/default/f250.',
                        key: const ValueKey('cam-source'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: p.textDim)),
                  ]),
            ),
            if (snap.settings.source == SettingsSource.screen) ...[
              const SizedBox(width: kGap),
              _button('cam-defaults', 'Use /etc/default/f250', _busy ? null : () => _apply(null), width: 170),
            ],
            const SizedBox(width: kGap),
            _button('cam-rescan', 'Rescan', _busy ? null : () => _read(), width: 104),
            const SizedBox(width: kGap),
            _button('cam-revert', 'Undo', changed && !_busy ? () => setState(() => _draft = snap.settings) : null,
                width: 96),
            const SizedBox(width: kGap),
            _button('cam-apply', 'Apply', changed && !_busy ? () => _apply(draft) : null,
                width: 130, primary: true),
          ]),
        );
        return LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  pair(CameraId.front, CameraId.rear),
                  const SizedBox(height: kGap),
                  pair(CameraId.left, CameraId.right),
                  if (!draft.canRecord) ...[
                    const SizedBox(height: 6),
                    Text('Recording: ${draft.recordingUnavailable}',
                        key: const ValueKey('cam-recording-unavailable'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.advisory)),
                  ],
                  const Spacer(),
                  const SizedBox(height: kGap),
                  bottom,
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// One camera: its name and whether its device is plugged in; its USB
  /// port (tap to change); for front and rear, Record or Live only, and
  /// for left and right why they don't record.
  Widget _card(CameraId c, CameraSettingsSnapshot snap, CameraSettings draft, Palette p) {
    final device = draft.devices[c];
    final plugged = snap.plugged.where((d) => d.path == device).firstOrNull;
    final missing = device != null && plugged == null;
    final (state, stateColor) = device == null
        ? ('no camera', p.textDim)
        : missing
            ? ('not plugged in', p.advisory)
            : ('plugged in', p.ok);
    final port = device == null ? 'None' : (plugged ?? CameraDevice(path: device)).port;
    final second = device == null
        ? null
        : missing
            ? 'not plugged in'
            : (plugged!.label.isEmpty ? null : plugged.label);
    final text = second == null ? port : '$port · $second';
    final recording = draft.record.contains(c);
    final name = cameraName(c).toLowerCase();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Color.lerp(p.surface, p.surfaceHigh, 0.5),
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(cameraShortName(c), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
          const SizedBox(width: 8),
          Container(
              width: 8, height: 8, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(state,
              key: ValueKey('cam-state-${c.name}'), style: TextStyle(fontSize: 12, color: stateColor)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            width: 150,
            child: TapTarget(
              key: ValueKey('cam-device-${c.name}'),
              label: '${cameraName(c)} device: $text. Change',
              padding: const EdgeInsets.only(left: 10, right: 4),
              onTap: () => setState(() => _picking = c),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(port,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
                        if (second != null)
                          Text(second,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: missing ? p.advisory : p.textDim)),
                      ]),
                ),
                Icon(Icons.chevron_right, size: 20, color: p.textDim),
              ]),
            ),
          ),
          const SizedBox(width: kGap),
          Expanded(
            child: recordable.contains(c)
                ? Row(children: [
                    Expanded(
                      child: TapTarget(
                        key: ValueKey('cam-record-${c.name}'),
                        label: 'Record the $name',
                        selected: recording,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onTap: () => setState(() => _draft = draft.withRecord(c, true)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: recording ? p.critical : p.textDim, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Record',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: recording ? p.text : p.textDim)),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: TapTarget(
                        key: ValueKey('cam-live-${c.name}'),
                        label: 'Don\'t record the $name: live only',
                        selected: !recording,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onTap: () => setState(() => _draft = draft.withRecord(c, false)),
                        child: Text('Live only',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: recording ? p.textDim : p.text)),
                      ),
                    ),
                  ])
                : Container(
                    key: ValueKey('cam-live-${c.name}'),
                    height: kMinTouch,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.border),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Live only',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.textDim)),
                      Text('only front and rear record',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: p.textDim)),
                    ]),
                  ),
          ),
        ]),
      ]),
    );
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

  /// [primary]: filled while it can be tapped (Apply once something changed).
  Widget _button(String key, String text, VoidCallback? onTap, {required double width, bool primary = false}) {
    final p = Palette.of(context);
    final fill = primary && onTap != null ? p.accent : null;
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: TapTarget(
          key: ValueKey(key),
          label: onTap == null ? '$text (unavailable)' : text,
          fill: fill,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          onTap: onTap ?? () {},
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: fill == null ? p.text : TapTarget.onFill(fill))),
        ),
      ),
    );
  }
}
