import 'package:flutter/material.dart';

import '../../telemetry/telemetry_store.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';
import '../widgets/badges.dart';

String linkLabel(LinkState s) => switch (s) {
      LinkState.connecting => 'Connecting',
      LinkState.up => 'Link up',
      LinkState.degraded => 'Degraded',
      LinkState.down => 'Link down',
    };

Color linkColor(LinkState s, Palette p) => switch (s) {
      LinkState.connecting => p.stale,
      LinkState.up => p.ok,
      LinkState.degraded => p.advisory,
      LinkState.down => p.critical,
    };

/// Always-visible strip: data source, link health, clock. Nothing here is
/// tappable; it is for glancing.
class StatusBar extends StatelessWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.store,
      builder: (context, _) {
        final p = Palette.of(context);
        final link = s.store.link;
        final source = s.store.source;
        final now = DateTime.now();
        final clock = formatClock(now);
        return Container(
          height: kStatusBarHeight,
          color: p.surface,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            if (source.simulated) ...[
              Pill('SIMULATED', key: const ValueKey('simulated-badge'), color: p.simulated, filled: true),
              const SizedBox(width: 8),
            ],
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: linkColor(link, p), shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(linkLabel(link),
                key: const ValueKey('link-state'),
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: linkColor(link, p))),
            const SizedBox(width: 6),
            Text('· ${formatAge(s.store.clock.now() - s.store.linkSince)}',
                style: TextStyle(fontSize: 13, color: p.textDim)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(source.scenario ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textDim)),
            ),
            Text(clock,
                key: const ValueKey('status-clock'),
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular, color: p.text)),
          ]),
        );
      },
    );
  }
}
