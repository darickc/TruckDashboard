import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../shell/nav_buttons.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

/// The screens Home opens, in the order its buttons show them.
const homeButtons = [
  AppScreen.gauges,
  AppScreen.media,
  AppScreen.navigation,
  AppScreen.cameras,
  AppScreen.settings,
  AppScreen.diagnostics,
];

/// Home: one large button per screen, three across and two down. Every
/// other screen has Back at its top left (shell/nav_buttons.dart). Alerts
/// show above it in the banner, as on every screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    final screens = AppScope.of(context).screens;
    final rows = [
      for (var i = 0; i < homeButtons.length; i += _columns)
        homeButtons.sublist(i, (i + _columns).clamp(0, homeButtons.length)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (r, row) in rows.indexed) ...[
        if (r > 0) const SizedBox(height: kGap),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (c, screen) in row.indexed) ...[
              if (c > 0) const SizedBox(width: kGap),
              Expanded(
                child: TapTarget(
                  key: ValueKey('home-${screen.name}'),
                  label: screenLabels[screen]!,
                  onTap: () => screens.open(screen),
                  child: _HomeButton(screen),
                ),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton(this.screen);

  final AppScreen screen;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    // Scales down rather than overflow when the alert banner takes height.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(screenIcons[screen], size: 56, color: p.accent),
        const SizedBox(height: 8),
        Text(screenLabels[screen]!,
            maxLines: 1,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text)),
      ]),
    );
  }
}
