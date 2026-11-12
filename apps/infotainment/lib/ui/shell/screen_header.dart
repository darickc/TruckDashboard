import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

const screenIcons = {
  AppScreen.home: Icons.home_rounded,
  AppScreen.gauges: Icons.speed_rounded,
  AppScreen.media: Icons.music_note_rounded,
  AppScreen.navigation: Icons.map_rounded,
  AppScreen.cameras: Icons.videocam_rounded,
  AppScreen.settings: Icons.settings_rounded,
  AppScreen.diagnostics: Icons.monitor_heart_rounded,
};

const screenLabels = {
  AppScreen.home: 'Home',
  AppScreen.gauges: 'Gauges',
  AppScreen.media: 'Media',
  AppScreen.navigation: 'Nav',
  AppScreen.cameras: 'Cameras',
  AppScreen.settings: 'Settings',
  AppScreen.diagnostics: 'Diagnostics',
};

/// Height of the row above every screen but Home: one touch target.
const kScreenHeaderHeight = kMinTouch;

/// Back at the top left of every screen but Home, and Home beside it when
/// Back would not go to Home (a screen opened from another screen), then
/// the screen's name.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.current, required this.previous});

  /// The screen showing, and the one Back returns to.
  final AppScreen current;
  final AppScreen previous;

  @override
  Widget build(BuildContext context) {
    final screens = AppScope.of(context).screens;
    final p = Palette.of(context);
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    Widget button(String key, String semantics, IconData icon, String text, VoidCallback onTap) =>
        SizedBox(
          width: 120,
          child: TapTarget(
            key: ValueKey(key),
            label: semantics,
            padding: EdgeInsets.zero,
            onTap: onTap,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 26, color: p.text),
              const SizedBox(width: 6),
              Text(text, style: label.copyWith(color: p.text)),
            ]),
          ),
        );
    return SizedBox(
      height: kScreenHeaderHeight,
      child: Row(children: [
        button('nav-back', 'Back to ${screenLabels[previous]}', Icons.arrow_back_rounded, 'Back',
            screens.back),
        if (previous != AppScreen.home) ...[
          const SizedBox(width: kGap),
          button('nav-home', 'Home', Icons.home_rounded, 'Home', screens.home),
        ],
        const SizedBox(width: 16),
        Icon(screenIcons[current], size: 26, color: p.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(screenLabels[current]!,
              key: const ValueKey('screen-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: p.text)),
        ),
      ]),
    );
  }
}
