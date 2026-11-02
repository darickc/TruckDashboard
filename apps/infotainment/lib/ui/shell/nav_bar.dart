import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/tap_target.dart';

const tabIcons = {
  AppTab.home: Icons.home_rounded,
  AppTab.gauges: Icons.speed_rounded,
  AppTab.media: Icons.music_note_rounded,
  AppTab.navigation: Icons.map_rounded,
  AppTab.cameras: Icons.videocam_rounded,
  AppTab.diagnostics: Icons.monitor_heart_rounded,
};

const tabLabels = {
  AppTab.home: 'Home',
  AppTab.gauges: 'Gauges',
  AppTab.media: 'Media',
  AppTab.navigation: 'Nav',
  AppTab.cameras: 'Cameras',
  AppTab.diagnostics: 'Diagnostics',
};

class NavBar extends StatelessWidget {
  const NavBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tab = AppScope.of(context).tab;
    final p = Palette.of(context);
    return ValueListenableBuilder(
      valueListenable: tab,
      builder: (context, current, _) => Container(
        height: kNavBarHeight,
        color: p.surface,
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(children: [
          for (final t in AppTab.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TapTarget(
                  key: ValueKey('nav-${t.name}'),
                  label: tabLabels[t]!,
                  selected: t == current,
                  padding: EdgeInsets.zero,
                  onTap: () => tab.value = t,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(tabIcons[t], size: 26, color: t == current ? p.accent : p.textDim),
                    Text(tabLabels[t]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t == current ? p.accent : p.textDim)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
