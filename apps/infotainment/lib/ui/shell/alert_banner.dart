import 'package:flutter/material.dart';

import '../../telemetry/warnings.dart';
import '../app_scope.dart';
import '../banner_alerts.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/tap_target.dart';

/// The most important active alert, shown above every screen: the
/// vehicle's, and camera-manager's recording advisories (banner_alerts.dart).
/// It goes away when the condition clears. An advisory also has Clear,
/// which hides it while it lasts (ClearedAlerts); a critical alert has none.
/// Its height is reserved only while an alert is active.
///
/// [compact]: the status bar's height, for camera mode, where the alert
/// takes the status bar's place above the camera window. It carries a SIM
/// mark, since the status bar's SIMULATED badge is hidden under it, and no
/// Clear: 44 px is less than a touch target. Clear it outside camera mode.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.settings, s.cameras.status, s.cleared]),
      builder: (context, _) {
        final alerts = bannerAlerts(s);
        if (alerts.isEmpty) return const SizedBox.shrink();
        final p = Palette.of(context);
        final top = alerts.first;
        final critical = top.level == AlertLevel.critical;
        final color = critical ? p.critical : p.advisory;
        final (title, detail) = (top.title, top.detail);
        // In camera mode the status bar's SIMULATED badge is hidden under
        // this; elsewhere it shows, except for a simulated camera alert
        // over real vehicle data.
        final sim = top.simulated && (compact || !s.store.source.simulated);
        return Container(
          key: const ValueKey('alert-banner'),
          height: compact ? kStatusBarHeight : kAlertBannerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: critical ? 0.95 : 0.22),
            border: Border(bottom: BorderSide(color: color, width: 2)),
          ),
          child: Row(children: [
            if (sim) ...[
              Pill('SIM', color: critical ? Colors.white : p.simulated),
              const SizedBox(width: 8),
            ],
            Icon(critical ? Icons.error : Icons.warning_amber_rounded,
                size: compact ? 24 : 30, color: critical ? Colors.white : color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      key: const ValueKey('alert-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: compact ? 16 : 18,
                          height: compact ? 1.1 : null,
                          fontWeight: FontWeight.w800,
                          color: critical ? Colors.white : p.text)),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: compact ? 12 : 13,
                          height: compact ? 1.1 : null,
                          color: critical ? Colors.white : p.text)),
                ],
              ),
            ),
            if (alerts.length > 1)
              Text('+${alerts.length - 1} more',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: critical ? Colors.white : p.text)),
            if (top.clearable && !compact) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 120,
                height: kMinTouch,
                child: TapTarget(
                  key: const ValueKey('alert-clear'),
                  label: 'Clear: ${top.title}',
                  padding: EdgeInsets.zero,
                  onTap: () => s.cleared.clear(top, s.store.clock.now()),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.close_rounded, size: 24, color: p.text),
                    const SizedBox(width: 4),
                    Text('Clear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                  ]),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}
