import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/circular_gauge.dart';
import '../widgets/gauge_tile.dart';
import '../widgets/panel.dart';
import '../widgets/tap_target.dart';

class GaugesScreen extends StatelessWidget {
  const GaugesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: s.settings,
      builder: (context, _) {
        final profiles = s.config.profiles;
        final profile = profiles.firstWhere((x) => x.id == s.settings.profileId,
            orElse: () => profiles.first);
        final rows = [
          profile.tiles.take(4).toList(),
          if (profile.tiles.length > 4) profile.tiles.skip(4).toList(),
        ];
        return Column(children: [
          SizedBox(
            height: kMinTouch,
            child: Row(children: [
              for (final pr in profiles) ...[
                SizedBox(
                  width: 150,
                  child: TapTarget(
                    key: ValueKey('profile-${pr.id}'),
                    label: '${pr.name} profile',
                    selected: pr.id == profile.id,
                    onTap: () => s.settings.profileId = pr.id,
                    child: Text(pr.name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: kGap),
              ],
            ]),
          ),
          const SizedBox(height: kGap),
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const SizedBox(height: kGap),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (j, tile) in row.indexed) ...[
                  if (j > 0) const SizedBox(width: kGap),
                  Expanded(child: _tile(tile)),
                ],
                // Keep tile widths constant when a row is short.
                for (var k = row.length; k < 4; k++) ...[
                  const SizedBox(width: kGap),
                  const Expanded(child: SizedBox()),
                ],
              ]),
            ),
          ],
        ]);
      },
    );
  }

  Widget _tile(GaugeTileSpec t) => switch (t.style) {
        GaugeStyle.digital => DigitalGauge(signalId: t.signalId),
        GaugeStyle.circular => CircularGauge(signalId: t.signalId),
        GaugeStyle.compact => Panel(child: Center(child: CompactIndicator(signalId: t.signalId))),
      };
}
