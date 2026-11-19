import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../display/display_state.dart';
import '../../model/units.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// Width of a setting's name on the left of its row.
const kSettingLabelWidth = 150.0;

/// A setting's row: its name (and a dim line under it) on the left, its
/// controls on the right.
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.subtitle, this.subtitleKey, required this.child});

  final String title;
  final String? subtitle;
  final Key? subtitleKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Row(
      children: [
        SizedBox(
          width: kSettingLabelWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  key: subtitleKey,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textDim),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    );
  }
}

/// A choice that can't be made now, shown where it would be so its absence
/// isn't a mystery: dim, not tappable. Its reason is said nearby.
class UnavailableChoice extends StatelessWidget {
  const UnavailableChoice(this.text, {super.key, required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      label: '$text, not available',
      child: Container(
        width: width,
        height: kMinTouch,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Text(text, style: TextStyle(fontSize: 16, color: p.textDim.withValues(alpha: 0.6))),
      ),
    );
  }
}

/// Brightness as ten steps of 10 %, filled up to the level.
class StepBar extends StatelessWidget {
  const StepBar({super.key, required this.pct, this.steps = 10});

  final int pct;
  final int steps;

  /// How many steps are filled at [pct] (rounded, at least one above 0).
  static int filled(int pct, int steps) => pct <= 0 ? 0 : ((pct * steps) / 100).round().clamp(1, steps);

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final n = filled(pct, steps);
    return SizedBox(
      height: 14,
      child: Row(
        children: [
          for (var i = 0; i < steps; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: Container(
                key: ValueKey('step-$i-${i < n ? 'on' : 'off'}'),
                decoration: BoxDecoration(
                  color: i < n ? p.accent : p.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Day/night and brightness (ADR-0028). power-manager decides and sets the
/// backlight; this shows what it decided and why, and sends the driver's
/// changes. Auto can be chosen only while power-manager is connected;
/// otherwise it shows, dim, with the reason in the line under the choices.
class DisplaySettings extends StatelessWidget {
  const DisplaySettings({super.key});

  static const _step = 10;
  static const _choiceWidth = 110.0;

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
          width: _choiceWidth,
          child: TapTarget(
            key: ValueKey('display-${c.name}'),
            label: 'Display $text',
            selected: st.choice == c,
            onTap: () => send(() => display.setChoice(c)),
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        );
        Widget step(String key, String semantic, String text, int delta) => SizedBox(
          width: kMinTouch,
          child: TapTarget(
            key: ValueKey(key),
            label: semantic,
            padding: EdgeInsets.zero,
            onTap: () => send(() => display.setBrightness(st.mode, st.pct! + delta)),
            child: Text(text, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
          ),
        );
        final mode = st.mode == DayNight.day ? 'Day' : 'Night';
        final backlight = describeBacklight(st);
        final sources = describeSources(st);
        final dim = TextStyle(fontSize: 13, color: p.textDim);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingRow(
              title: 'Theme',
              subtitle: '$mode now',
              child: Row(
                children: [
                  if (st.canAuto)
                    choice(DisplayChoice.auto, 'Auto')
                  else
                    const UnavailableChoice(
                      'Auto',
                      key: ValueKey('display-auto-unavailable'),
                      width: _choiceWidth,
                    ),
                  const SizedBox(width: kGap),
                  choice(DisplayChoice.day, 'Day'),
                  const SizedBox(width: kGap),
                  choice(DisplayChoice.night, 'Night'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: kSettingLabelWidth + 12, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeMode(st),
                    key: const ValueKey('display-detail'),
                    style: TextStyle(fontSize: 14, color: p.text),
                  ),
                  if (sources != null)
                    Text(
                      sources,
                      key: const ValueKey('display-sources'),
                      style: dim.copyWith(
                        color: st.report?.locationSource == LocationSource.gpsSimulated
                            ? p.advisory
                            : p.textDim,
                      ),
                    ),
                  if (backlight != null)
                    Text(
                      backlight,
                      key: const ValueKey('display-backlight'),
                      style: TextStyle(fontSize: 14, color: p.advisory),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (st.canSetBrightness)
              SettingRow(
                title: 'Brightness',
                subtitle: '$mode · never below ${st.minPct} %',
                subtitleKey: const ValueKey('brightness-mode'),
                child: Row(
                  children: [
                    step('brightness-down', 'Brightness down $_step %', '−', -_step),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StepBar(key: const ValueKey('brightness-bar'), pct: st.pct!),
                          const SizedBox(height: 6),
                          Text(
                            '${st.pct} %',
                            key: const ValueKey('brightness-level'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabular,
                              color: p.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    step('brightness-up', 'Brightness up $_step %', '+', _step),
                  ],
                ),
              )
            else
              SettingRow(
                title: 'Brightness',
                child: Text('Not controlled', key: const ValueKey('brightness-level'), style: dim),
              ),
          ],
        );
      },
    );
  }
}

/// The dashboard's own units, kept in its settings file (ADR-0029).
class UnitsSettings extends StatelessWidget {
  const UnitsSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: s.settings,
      builder: (context, _) {
        Widget option(UnitSystem u, String text) => SizedBox(
          width: 140,
          child: TapTarget(
            key: ValueKey('units-${u.name}'),
            label: text,
            selected: s.settings.units == u,
            onTap: () => s.settings.units = u,
            child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        );
        return SettingRow(
          title: 'Units',
          subtitle: 'Kept on this head unit',
          child: Row(
            children: [
              option(UnitSystem.imperial, 'Imperial'),
              const SizedBox(width: kGap),
              option(UnitSystem.metric, 'Metric'),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  s.settings.units == UnitSystem.imperial ? '°F · psi · mph' : '°C · kPa · km/h',
                  key: const ValueKey('units-detail'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: p.textDim),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
