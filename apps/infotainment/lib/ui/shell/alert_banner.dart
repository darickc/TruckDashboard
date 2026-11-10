import 'package:flutter/material.dart';

import '../../telemetry/warnings.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';
import '../widgets/badges.dart';

/// The most important active alert, shown above every screen. It isn't
/// dismissible: it goes away when the condition clears. Its height is
/// reserved only while an alert is active.
///
/// [compact]: the status bar's height, for camera mode, where the alert
/// takes the status bar's place above the camera window. It carries a SIM
/// mark, since the status bar's SIMULATED badge is hidden under it.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.store, s.settings]),
      builder: (context, _) {
        final alerts = s.store.alerts;
        if (alerts.isEmpty) return const SizedBox.shrink();
        final p = Palette.of(context);
        final top = alerts.first;
        final critical = top.level == AlertLevel.critical;
        final color = critical ? p.critical : p.advisory;
        final (title, detail) = describeAlert(top, s.store, s.settings.units);
        return Container(
          key: const ValueKey('alert-banner'),
          height: compact ? kStatusBarHeight : kAlertBannerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: critical ? 0.95 : 0.22),
            border: Border(bottom: BorderSide(color: color, width: 2)),
          ),
          child: Row(children: [
            if (compact && s.store.source.simulated) ...[
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
          ]),
        );
      },
    );
  }
}
