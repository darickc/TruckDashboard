import 'dart:async';

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

/// How long the shutdown question stays up without an answer.
const kShutdownConfirmTimeout = Duration(seconds: 8);

class NavBar extends StatefulWidget {
  const NavBar({super.key});

  @override
  State<NavBar> createState() => _NavBarState();
}

enum _Power { idle, confirming, shuttingDown }

class _NavBarState extends State<NavBar> {
  var _power = _Power.idle;
  Timer? _confirmTimeout;

  @override
  void dispose() {
    _confirmTimeout?.cancel();
    super.dispose();
  }

  void _ask() {
    _confirmTimeout?.cancel();
    _confirmTimeout = Timer(kShutdownConfirmTimeout, _cancel);
    setState(() => _power = _Power.confirming);
  }

  void _cancel() {
    _confirmTimeout?.cancel();
    if (mounted) setState(() => _power = _Power.idle);
  }

  void _shutDown() {
    _confirmTimeout?.cancel();
    setState(() => _power = _Power.shuttingDown);
    AppScope.of(context).power.powerOff();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    // The question replaces the tabs in place: a dialog would cover the
    // alert banner, which stays visible on every screen.
    return Container(
      height: kNavBarHeight,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: switch (_power) {
        _Power.idle => _tabs(s, p),
        _Power.confirming => _confirm(p),
        _Power.shuttingDown => Center(
            child: Text('Shutting down. Wait until the screen goes dark before turning the key off.',
                key: const ValueKey('shutdown-progress'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
      },
    );
  }

  Widget _tabs(AppServices s, Palette p) {
    return ValueListenableBuilder(
      valueListenable: s.tab,
      builder: (context, current, _) => Row(children: [
        for (final t in AppTab.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: TapTarget(
                key: ValueKey('nav-${t.name}'),
                label: tabLabels[t]!,
                selected: t == current,
                padding: EdgeInsets.zero,
                onTap: () => s.tab.value = t,
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
        if (s.power.canPowerOff)
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 2),
            child: TapTarget(
              key: const ValueKey('nav-power'),
              label: 'Shut down the head unit',
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: _ask,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.power_settings_new_rounded, size: 26, color: p.textDim),
                Text('Power',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: p.textDim)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _confirm(Palette p) {
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    return Row(children: [
      SizedBox(
        width: 150,
        child: TapTarget(
            key: const ValueKey('shutdown-cancel'),
            label: 'Cancel shutdown',
            onTap: _cancel,
            child: const Text('Cancel', style: label)),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('Shut down the head unit? Data is saved first.',
              key: const ValueKey('shutdown-question'),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        ),
      ),
      SizedBox(
        width: 150,
        child: TapTarget(
            key: const ValueKey('shutdown-confirm'),
            label: 'Shut down now',
            onTap: _shutDown,
            child: Text('Shut down', style: label.copyWith(color: p.critical))),
      ),
    ]);
  }
}
