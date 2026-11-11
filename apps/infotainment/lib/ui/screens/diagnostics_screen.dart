import 'package:flutter/material.dart';
import 'package:powerstroke_sim/powerstroke_sim.dart' show Scenario;

import '../../model/units.dart';
import '../../telemetry/calibration.dart';
import '../../telemetry/event_log.dart';
import '../../telemetry/signal_state.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../shell/status_bar.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

enum DiagSection { signals, link, dtcs, events, developer }

const _sectionLabels = {
  DiagSection.signals: 'Signals',
  DiagSection.link: 'Link',
  DiagSection.dtcs: 'DTCs',
  DiagSection.events: 'Events',
  DiagSection.developer: 'Developer',
};

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  var _section = DiagSection.signals;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: kMinTouch,
        child: Row(children: [
          for (final (i, d) in DiagSection.values.indexed) ...[
            if (i > 0) const SizedBox(width: kGap),
            Expanded(
              child: TapTarget(
                key: ValueKey('diag-${d.name}'),
                label: _sectionLabels[d]!,
                selected: d == _section,
                padding: EdgeInsets.zero,
                onTap: () => setState(() => _section = d),
                child: Text(_sectionLabels[d]!,
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
            DiagSection.signals => const _SignalList(),
            DiagSection.link => const _LinkHealth(),
            DiagSection.dtcs => const _DtcList(),
            DiagSection.events => const _EventList(),
            DiagSection.developer => const _Developer(),
          },
        ),
      ),
    ]);
  }
}

/// Rebuilds on telemetry or settings changes.
class _Live extends StatelessWidget {
  const _Live({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
        listenable: Listenable.merge([s.store, s.settings, ?s.simulation]),
        builder: (context, _) => builder(context));
  }
}

class _SignalList extends StatelessWidget {
  const _SignalList();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final now = s.store.clock.now();
      final rows = s.store.ordered.toList();
      final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textDim);
      return Column(children: [
        SizedBox(
          height: 20,
          child: Row(children: [
            SizedBox(width: 82, child: Text('SIGNAL', style: head)),
            SizedBox(width: 120, child: Text('VALUE', style: head)),
            SizedBox(width: 108, child: Text('STATE', style: head)),
            SizedBox(width: 64, child: Text('AGE', style: head)),
            SizedBox(width: 92, child: Text('SOURCE', style: head)),
            SizedBox(width: 92, child: Text('OK / FAIL', style: head)),
            Expanded(child: Text('REQUEST', style: head)),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemExtent: 34,
            itemBuilder: (context, i) => _signalRow(
                rows[i], now, s.settings.units, p, s.store.calibrationOf(rows[i].def.id)),
          ),
        ),
      ]);
    });
  }

  Widget _signalRow(
      SignalState st, Duration now, UnitSystem units, Palette p, Calibration cal) {
    final d = st.def;
    final value = st.isValid
        ? '${formatValue(d, st.value!, units)} ${displayUnitFor(d.quantity, units).label}'
        : st.lastGoodValue != null && !d.isComputed
            ? '(${formatValue(d, st.lastGoodValue!, units)})'
            : '—';
    final age = st.ageAt(now);
    final style = TextStyle(fontSize: 14, fontFeatures: tabular, color: p.text);
    final dim = TextStyle(fontSize: 13, color: p.textDim);
    return Row(key: ValueKey('diag-row-${d.id}'), children: [
      SizedBox(
          width: 82,
          child: Text(d.shortName,
              maxLines: 1, style: style.copyWith(fontWeight: FontWeight.w700))),
      SizedBox(width: 120, child: Text(value, maxLines: 1, style: style)),
      SizedBox(
          width: 108,
          child: Align(
              alignment: Alignment.centerLeft,
              child: Pill(validityLabel(st.validity),
                  color: validityColor(st.validity, p)))),
      SizedBox(
          width: 64,
          child: Text(age == null || d.isComputed ? '—' : formatAge(age), style: dim)),
      SizedBox(
          width: 92,
          child: Text(
              cal.isIdentity
                  ? provenanceLabel(d.provenance)
                  : '${provenanceLabel(d.provenance)} ×${cal.scale.toStringAsFixed(3)}',
              key: ValueKey('diag-source-${d.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dim)),
      SizedBox(
          width: 92,
          child: Text(d.isComputed ? '—' : '${st.successes} / ${st.failures}',
              style: dim.copyWith(fontFeatures: tabular))),
      Expanded(
        child: Text(
          d.isComputed
              ? '= ${d.inputs.join(' − ')}'
              : [d.request ?? '—', if (d.responder != null) '← ${d.responder}'].join(' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dim,
        ),
      ),
    ]);
  }
}

class _LinkHealth extends StatelessWidget {
  const _LinkHealth();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final store = s.store;
      final now = store.clock.now();
      final signals = store.ordered.where((x) => x.def.enabled && !x.def.isComputed).toList();
      final ok = signals.fold(0, (a, x) => a + x.successes);
      final fail = signals.fold(0, (a, x) => a + x.failures);
      final src = store.source;
      final simClock = s.simulation?.source?.scenarioSeconds ?? src.scenarioSeconds;
      final rows = <(String, String)>[
        ('Data source', src.simulated ? '${src.transport} — not the vehicle' : src.transport),
        ('Scenario', src.scenario ?? '—'),
        ('Scenario clock', simClock == null ? '—' : '${simClock.toStringAsFixed(0)} s'),
        if (src.machineState != null) ('Gateway state', src.machineState!),
        if (src.adapterVoltage != null)
          ('Adapter voltage (ATRV)', '${src.adapterVoltage!.toStringAsFixed(1)} V'),
        ('Link', '${linkLabel(store.link)} for ${formatAge(now - store.linkSince)}'),
        ('Requests/s (10 s avg)', store.requestsPerSecond(now).toStringAsFixed(1)),
        ('Responses OK / failed', '$ok / $fail'),
        ('Signals current',
            '${signals.where((x) => x.isValid).length} of ${signals.length}'),
        (
          'Transmit',
          switch (src.transmitEnabled) {
            null => 'n/a — in-app simulator',
            true => 'enabled (read-only services only)',
            false => 'off — passive only (ADR-0007)',
          }
        ),
      ];
      return ListView(children: [
        for (final (k, v) in rows)
          SizedBox(
            height: 34,
            child: Row(children: [
              SizedBox(
                  width: 220, child: Text(k, style: TextStyle(fontSize: 15, color: p.textDim))),
              Expanded(
                child: Text(v,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text)),
              ),
            ]),
          ),
      ]);
    });
  }
}

class _DtcList extends StatelessWidget {
  const _DtcList();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final dtcs = s.simulation?.current?.dtcs ?? const [];
      return ListView(children: [
        Text(
            s.simulation == null
                ? 'Reading trouble codes is not implemented in the gateway yet.'
                : 'Reading real trouble codes arrives with the vehicle gateway. '
                    'Codes below come from the simulator scenario.',
            style: TextStyle(fontSize: 14, color: p.textDim)),
        const SizedBox(height: 8),
        if (dtcs.isEmpty)
          Text('No trouble codes in this scenario.',
              style: TextStyle(fontSize: 16, color: p.text)),
        for (final d in dtcs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Pill('SIMULATED', color: p.simulated),
              const SizedBox(width: 8),
              Text(d.code,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: p.text)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('${d.description} · ${d.status}',
                      style: TextStyle(fontSize: 15, color: p.text))),
            ]),
          ),
      ]);
    });
  }
}

class _EventList extends StatelessWidget {
  const _EventList();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final events = s.store.events.newestFirst.toList();
      if (events.isEmpty) {
        return Text('No events yet.', style: TextStyle(fontSize: 15, color: p.textDim));
      }
      return ListView.builder(
        itemCount: events.length,
        itemExtent: 28,
        itemBuilder: (context, i) {
          final e = events[i];
          final color = switch (e.severity) {
            EventSeverity.critical => p.critical,
            EventSeverity.advisory => p.advisory,
            EventSeverity.info => p.textDim,
          };
          final t = e.wallTime;
          final stamp = '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
          return Row(children: [
            SizedBox(
                width: 80,
                child: Text(stamp,
                    style: TextStyle(fontSize: 13, fontFeatures: tabular, color: p.textDim))),
            Expanded(
                child: Text(e.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: color))),
          ]);
        },
      );
    });
  }
}

/// Simulator scenario selection and the speed-calibration procedure. The
/// driver's preferences are on the Settings tab (ADR-0029).
class _Developer extends StatelessWidget {
  const _Developer();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final sim = s.simulation;
      final label = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textDim);
      return ListView(children: [
        Text('SIMULATOR SCENARIO', style: label),
        const SizedBox(height: 6),
        if (sim == null)
          Padding(
            padding: const EdgeInsets.only(bottom: kGap),
            child: Text(
                'Data comes from the vehicle gateway. Its scenario (when simulated) '
                'is chosen when the gateway starts.',
                style: TextStyle(fontSize: 14, color: p.textDim)),
          ),
        for (final scenario in sim?.available.values ?? const <Scenario>[])
          Padding(
            padding: const EdgeInsets.only(bottom: kGap),
            child: TapTarget(
              key: ValueKey('scenario-${scenario.id}'),
              label: 'Scenario ${scenario.name}',
              selected: sim!.current?.id == scenario.id,
              onTap: () => sim.select(scenario.id),
              child: Row(children: [
                SizedBox(
                    width: 180,
                    child: Text(scenario.name,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                Expanded(
                    child: Text(scenario.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.textDim))),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Text('SPEED CALIBRATION', style: label),
        const SizedBox(height: 6),
        const _SpeedCalibration(),
      ]);
    });
  }
}

/// Adjusts the vehicle-speed correction factor while driving alongside a GPS
/// reference. Changes last until the app restarts; the note says how to keep
/// one.
class _SpeedCalibration extends StatelessWidget {
  const _SpeedCalibration();

  static const _id = 'speed';
  static const _steps = [(-0.01, '−1%'), (-0.001, '−0.1%'), (0.001, '+0.1%'), (0.01, '+1%')];

  @override
  Widget build(BuildContext context) => _Live(builder: _build);

  Widget _build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final store = s.store;
    final cal = store.calibrationOf(_id);
    final configured = s.config.calibrations[_id] ?? Calibration.identity;
    final st = store[_id]!;
    final units = s.settings.units;
    final unit = displayUnitFor(st.def.quantity, units).label;
    final raw = st.lastGoodRaw;
    final reading = raw == null
        ? 'No speed reading yet'
        : 'Truck reports ${formatValue(st.def, raw, units)} $unit → '
            'shown ${formatValue(st.def, cal.apply(raw), units)} $unit';
    final changed = cal.scale != configured.scale;

    void set(double scale) {
      final clamped = scale.clamp(Calibration.minScale, Calibration.maxScale).toDouble();
      // Round away float drift from repeated steps (1.0 + 0.001 × n).
      final rounded = (clamped * 10000).roundToDouble() / 10000;
      s.setCalibration(_id, cal.copyWith(scale: rounded));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
          width: 120,
          child: Text('×${cal.scale.toStringAsFixed(4)}',
              key: const ValueKey('speed-scale'),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, fontFeatures: tabular, color: p.text)),
        ),
        for (final (delta, text) in _steps) ...[
          SizedBox(
            width: 92,
            child: TapTarget(
                key: ValueKey('speed-scale-$text'),
                label: 'Speed scale $text',
                padding: EdgeInsets.zero,
                onTap: () => set(cal.scale * (1 + delta)),
                child: Text(text, style: const TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: kGap),
        ],
        SizedBox(
          width: 110,
          child: TapTarget(
              key: const ValueKey('speed-scale-reset'),
              label: 'Reset speed scale to the configured value',
              padding: EdgeInsets.zero,
              onTap: () => s.setCalibration(_id, configured),
              child: const Text('Reset', style: TextStyle(fontSize: 16))),
        ),
      ]),
      const SizedBox(height: 6),
      Text(reading,
          key: const ValueKey('speed-scale-reading'),
          style: TextStyle(fontSize: 14, color: p.text)),
      Text(
          changed
              ? 'Adjusted from ×${configured.scale.toStringAsFixed(4)}. Lasts until restart: to keep it, '
                  'set "scale" for speed in assets/config/calibration.json.'
              : 'Scale = true speed ÷ speed the truck reports (from a steady GPS comparison).',
          style: TextStyle(fontSize: 13, color: changed ? p.advisory : p.textDim)),
    ]);
  }
}
