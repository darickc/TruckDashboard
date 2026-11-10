import 'dart:async';

import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../screens/cameras_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/gauges_screen.dart';
import '../screens/home_screen.dart';
import '../screens/media_screen.dart';
import '../screens/navigation_screen.dart';
import '../theme.dart';
import 'alert_banner.dart';
import 'camera_mode.dart';
import 'nav_bar.dart';
import 'status_bar.dart';

/// Status bar, alert banner, the active screen and the nav bar.
///
/// The alert banner sits *above* the screen area, outside any screen, so no
/// screen can hide it. While camera-manager shows a camera, the shell
/// switches to camera mode (camera_mode.dart) on every tab: the camera's
/// window covers x 220–800, y 44–480 whatever the dashboard shows, and an
/// alert takes the status bar's place above it.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Timer? _refresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    _refresh?.cancel();
    final period = s.refreshPeriod;
    if (period != null) {
      _refresh = Timer.periodic(period, (_) => s.store.refresh());
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    // Material supplies the default text style; without it every Text renders
    // with the debug "missing Material" underline.
    return Material(
      color: Palette.of(context).background,
      child: ValueListenableBuilder(
        valueListenable: s.cameras.status,
        builder: (context, cameras, _) {
          final view = cameras.view;
          if (cameras.camera != null && view != null) return _cameraMode(s, view, cameras.simulated);
          return _screens(s);
        },
      ),
    );
  }

  Widget _cameraMode(AppServices s, CameraView view, bool simulated) {
    return Column(children: [
      // Always 44 high, so the camera area stays where the compositor puts
      // the window: an alert takes the status bar's place, never moves it.
      SizedBox(
        height: kStatusBarHeight,
        child: ListenableBuilder(
          listenable: s.store,
          builder: (context, _) =>
              s.store.alerts.isEmpty ? const StatusBar() : const AlertBanner(compact: true),
        ),
      ),
      Expanded(
        child: Row(children: [
          CameraControls(view: view),
          Expanded(child: CameraArea(view: view, simulated: simulated)),
        ]),
      ),
    ]);
  }

  Widget _screens(AppServices s) {
    return Column(children: [
        const StatusBar(),
        const AlertBanner(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(kGap),
            child: ValueListenableBuilder(
              valueListenable: s.tab,
              builder: (context, tab, _) => KeyedSubtree(
                key: ValueKey('screen-${tab.name}'),
                child: switch (tab) {
                  AppTab.home => const HomeScreen(),
                  AppTab.gauges => const GaugesScreen(),
                  AppTab.media => const MediaScreen(),
                  AppTab.navigation => const NavigationScreen(),
                  AppTab.cameras => const CamerasScreen(),
                  AppTab.diagnostics => const DiagnosticsScreen(),
                },
              ),
            ),
          ),
        ),
        const NavBar(),
      ]);
  }
}
