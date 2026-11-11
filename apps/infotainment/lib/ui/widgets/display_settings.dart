import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../display/display_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// Day/night and brightness (ADR-0028). power-manager decides and sets the
/// backlight; this shows what it decided and why, and sends the driver's
/// changes. Auto is offered only while power-manager is connected.
class DisplaySettings extends StatelessWidget {
  const DisplaySettings({super.key});

  static const _step = 10;

  @override
  Widget build(BuildContext context) {
    final display = AppScope.of(context).display;
    final p = Palette.of(context);
    return ValueListenableBuilder<DisplayStatus>(
      valueListenable: display.status,
      builder: (context, st, _) {
        void send(Future<void> Function() call) {
          // A failed call shows as the link going down; nothing to add here.
          call().catchError((Object _) {});
        }

        Widget choice(DisplayChoice c, String text) => SizedBox(
              width: 150,
              child: TapTarget(
                  key: ValueKey('display-${c.name}'),
                  label: 'Display $text',
                  selected: st.choice == c,
                  onTap: () => send(() => display.setChoice(c)),
                  child: Text(text, style: const TextStyle(fontSize: 16))),
            );
        Widget step(String key, String text, int delta) => SizedBox(
              width: 92,
              child: TapTarget(
                  key: ValueKey(key),
                  label: 'Brightness $text',
                  padding: EdgeInsets.zero,
                  onTap: () => send(() => display.setBrightness(st.mode, st.pct! + delta)),
                  child: Text(text, style: const TextStyle(fontSize: 16))),
            );
        final modeName = st.mode == DayNight.day ? 'day' : 'night';
        final backlight = describeBacklight(st);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (st.canAuto) ...[choice(DisplayChoice.auto, 'Auto'), const SizedBox(width: kGap)],
            choice(DisplayChoice.day, 'Day'),
            const SizedBox(width: kGap),
            choice(DisplayChoice.night, 'Night'),
          ]),
          const SizedBox(height: 6),
          Text(describeMode(st),
              key: const ValueKey('display-detail'), style: TextStyle(fontSize: 14, color: p.text)),
          if (backlight != null)
            Text(backlight,
                key: const ValueKey('display-backlight'),
                style: TextStyle(fontSize: 14, color: p.advisory)),
          const SizedBox(height: 6),
          if (st.canSetBrightness)
            Row(children: [
              SizedBox(
                width: 200,
                child: Text('Brightness ($modeName) ${st.pct} %',
                    key: const ValueKey('brightness-level'),
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular, color: p.text)),
              ),
              step('brightness-down', '−$_step %', -_step),
              const SizedBox(width: kGap),
              step('brightness-up', '+$_step %', _step),
              const SizedBox(width: kGap),
              Expanded(
                child: Text('Never below ${st.minPct} %',
                    style: TextStyle(fontSize: 13, color: p.textDim)),
              ),
            ])
          else
            Text('Brightness: not controlled',
                key: const ValueKey('brightness-level'), style: TextStyle(fontSize: 14, color: p.textDim)),
        ]);
      },
    );
  }
}
