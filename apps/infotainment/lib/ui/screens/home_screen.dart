import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../presentation.dart';
import '../shell/status_bar.dart';
import '../theme.dart';
import '../widgets/gauge_tile.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = AppScope.of(context).tab;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Expanded(
        flex: 5,
        child: Column(children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: DigitalGauge(signalId: 'eot')),
              SizedBox(width: kGap),
              Expanded(child: DigitalGauge(signalId: 'ect')),
            ]),
          ),
          SizedBox(height: kGap),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: DigitalGauge(signalId: 'eot_ect_delta')),
              SizedBox(width: kGap),
              Expanded(child: DigitalGauge(signalId: 'trans_temp')),
            ]),
          ),
        ]),
      ),
      const SizedBox(width: kGap),
      Expanded(
        flex: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Expanded(child: _HealthPanel()),
          const SizedBox(height: kGap),
          SizedBox(
            height: kMinTouch,
            child: Row(children: [
              Expanded(
                child: TapTarget(
                  key: const ValueKey('home-media'),
                  label: 'Media',
                  onTap: () => tab.value = AppTab.media,
                  child: const _Shortcut(Icons.music_note_rounded, 'Media'),
                ),
              ),
              const SizedBox(width: kGap),
              Expanded(
                child: TapTarget(
                  key: const ValueKey('home-nav'),
                  label: 'Navigation',
                  onTap: () => tab.value = AppTab.navigation,
                  child: const _Shortcut(Icons.map_rounded, 'Nav'),
                ),
              ),
              const SizedBox(width: kGap),
              Expanded(
                child: TapTarget(
                  key: const ValueKey('home-cameras'),
                  label: 'Cameras',
                  onTap: () => tab.value = AppTab.cameras,
                  child: const _Shortcut(Icons.videocam_rounded, 'Cam'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 24, color: p.text),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: p.textDim)),
    ]);
  }
}

/// Vehicle health at a glance: link state, how many signals are current, the
/// top alert, and the media state.
class _HealthPanel extends StatelessWidget {
  const _HealthPanel();

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.settings]),
      builder: (context, _) {
        final p = Palette.of(context);
        final store = s.store;
        final enabled = store.ordered.where((x) => x.def.enabled && !x.def.isComputed);
        final current = enabled.where((x) => x.isValid).length;
        final link = store.link;
        final alerts = store.alerts;
        return Panel(
          title: 'Vehicle health',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(linkLabel(link),
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: linkColor(link, p))),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$current/${enabled.length} current',
                    key: const ValueKey('health-current'),
                    maxLines: 1,
                    style: TextStyle(fontSize: 14, color: p.textDim)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
                alerts.isEmpty
                    ? 'No alerts'
                    : describeAlert(alerts.first, store, s.settings.units).$1 +
                        (alerts.length > 1 ? '  (+${alerts.length - 1})' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: alerts.isEmpty ? p.ok : p.advisory)),
            Divider(height: 12, color: p.border),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (final id in const ['fuel_level', 'speed', 'rpm', 'boost', 'ficm_main', 'battery'])
                    CompactIndicator(signalId: id),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}
