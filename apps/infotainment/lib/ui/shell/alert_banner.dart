import 'package:flutter/material.dart';

import '../../telemetry/warnings.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';

/// The most important active alert, shown above every screen. It isn't
/// dismissible: it goes away when the condition clears. Its height is
/// reserved only while an alert is active.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key});

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
          height: kAlertBannerHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: critical ? 0.95 : 0.22),
            border: Border(bottom: BorderSide(color: color, width: 2)),
          ),
          child: Row(children: [
            Icon(critical ? Icons.error : Icons.warning_amber_rounded,
                size: 30, color: critical ? Colors.white : color),
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
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: critical ? Colors.white : p.text)),
                  Text(detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: critical ? Colors.white : p.text)),
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
