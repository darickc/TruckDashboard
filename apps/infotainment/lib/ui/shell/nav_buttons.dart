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

/// Back, at the top left of the status bar on every screen but Home, and
/// Home beside it when Back would not go to Home (a screen opened from
/// another screen), as a 60 × 60 house. Each is a full 60 px touch target, so the status bar is
/// that high outside camera mode (StatusBar.navigation).
class NavButtons extends StatelessWidget {
  const NavButtons({super.key});

  @override
  Widget build(BuildContext context) {
    final screens = AppScope.of(context).screens;
    return ListenableBuilder(
      listenable: screens,
      builder: (context, _) {
        final previous = screens.previous;
        if (previous == null) return const SizedBox.shrink();
        final p = Palette.of(context);
        const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
        Widget button(String key, String semantics, IconData icon, String? text, VoidCallback onTap) =>
            SizedBox(
              width: text == null ? kMinTouch : 120,
              height: kMinTouch,
              child: TapTarget(
                key: ValueKey(key),
                label: semantics,
                padding: EdgeInsets.zero,
                onTap: onTap,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 26, color: p.text),
                  if (text != null) ...[
                    const SizedBox(width: 6),
                    Text(text, style: label.copyWith(color: p.text)),
                  ],
                ]),
              ),
            );
        return Row(mainAxisSize: MainAxisSize.min, children: [
          button('nav-back', 'Back to ${screenLabels[previous]}', Icons.arrow_back_rounded, 'Back',
              screens.back),
          if (previous != AppScreen.home) ...[
            const SizedBox(width: kGap),
            // Just the house: the left side has room for Back's word and
            // one icon beside the centred link status.
            button('nav-home', 'Home', Icons.home_rounded, null, screens.home),
          ],
        ]);
      },
    );
  }
}
