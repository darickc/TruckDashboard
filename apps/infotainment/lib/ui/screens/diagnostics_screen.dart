import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../model/units.dart';
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
        listenable: Listenable.merge([s.store, s.settings, s.simulation]),
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
            itemBuilder: (context, i) => _signalRow(rows[i], now, s.settings.units, p),
          ),
        ),
      ]);
    });
  }

  Widget _signalRow(SignalState st, Duration now, UnitSystem units, Palette p) {
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
      SizedBox(width: 92, child: Text(provenanceLabel(d.provenance), style: dim)),
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
      final sim = s.simulation;
      final rows = <(String, String)>[
        ('Data source', sim.current == null ? 'none' : 'Simulator (in-app) — not the vehicle'),
        ('Scenario', sim.current?.name ?? '—'),
        ('Scenario clock',
            sim.source == null ? '—' : '${sim.source!.scenarioSeconds.toStringAsFixed(0)} s'),
        ('Link', '${linkLabel(store.link)} for ${formatAge(now - store.linkSince)}'),
        ('Requests/s (10 s avg)', store.requestsPerSecond(now).toStringAsFixed(1)),
        ('Responses OK / failed', '$ok / $fail'),
        ('Signals current',
            '${signals.where((x) => x.isValid).length} of ${signals.length}'),
        ('Transmit', 'n/a — simulator (gateway arrives in Phase 3)'),
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
      final dtcs = s.simulation.current?.dtcs ?? const [];
      return ListView(children: [
        Text('Reading real trouble codes arrives with the vehicle gateway (Phase 3–4). '
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

/// Simulator scenario selection and display preferences.
class _Developer extends StatelessWidget {
  const _Developer();

  @override
  Widget build(BuildContext context) {
    return _Live(builder: (context) {
      final s = AppScope.of(context);
      final p = Palette.of(context);
      final sim = s.simulation;
      final label = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textDim);
      Widget option(String key, String text, bool selected, VoidCallback onTap) => SizedBox(
            width: 150,
            child: TapTarget(
                key: ValueKey(key),
                label: text,
                selected: selected,
                onTap: onTap,
                child: Text(text, style: const TextStyle(fontSize: 16))),
          );
      return ListView(children: [
        Text('SIMULATOR SCENARIO', style: label),
        const SizedBox(height: 6),
        for (final scenario in sim.available.values)
          Padding(
            padding: const EdgeInsets.only(bottom: kGap),
            child: TapTarget(
              key: ValueKey('scenario-${scenario.id}'),
              label: 'Scenario ${scenario.name}',
              selected: sim.current?.id == scenario.id,
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
        Text('UNITS', style: label),
        const SizedBox(height: 6),
        Row(children: [
          option('units-imperial', 'Imperial', s.settings.units == UnitSystem.imperial,
              () => s.settings.units = UnitSystem.imperial),
          const SizedBox(width: kGap),
          option('units-metric', 'Metric', s.settings.units == UnitSystem.metric,
              () => s.settings.units = UnitSystem.metric),
        ]),
        const SizedBox(height: kGap),
        Text('THEME', style: label),
        const SizedBox(height: 6),
        Row(children: [
          option('theme-day', 'Day', s.settings.theme == DayNight.day,
              () => s.settings.theme = DayNight.day),
          const SizedBox(width: kGap),
          option('theme-night', 'Night', s.settings.theme == DayNight.night,
              () => s.settings.theme = DayNight.night),
        ]),
      ]);
    });
  }
}
