import 'dart:async';

import 'package:flutter/material.dart';

import '../../cameras/camera_state.dart';
import '../app_scope.dart';
import '../banner_alerts.dart';
import '../screens/cameras_screen.dart';
import '../screens/diagnostics_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/gauges_screen.dart';
import '../screens/home_screen.dart';
import '../screens/media_screen.dart';
import '../screens/navigation_screen.dart';
import '../theme.dart';
import 'alert_banner.dart';
import 'camera_mode.dart';
import 'status_bar.dart';

/// Status bar, alert banner, then the screen showing: Home's buttons, or
/// another screen, with Back (and Home) at the status bar's left
/// (nav_buttons.dart).
///
/// The alert banner sits *above* the screen area, outside any screen, so no
/// screen can hide it. While camera-manager shows a camera, the shell
/// switches to camera mode (camera_mode.dart) on every screen: the camera's
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
          if (cameras.camera != null && view != null) return _cameraMode(s, view, cameras);
          return _screens(s);
        },
      ),
    );
  }

  Widget _cameraMode(AppServices s, CameraView view, CameraStatus cameras) {
    return Column(children: [
      // Always 44 high, so the camera area stays where the compositor puts
      // the window: an alert takes the status bar's place, never moves it.
      SizedBox(
        height: kStatusBarHeight,
        child: ListenableBuilder(
          listenable: Listenable.merge([s.store, s.cameras.status]),
          builder: (context, _) =>
              bannerAlerts(s).isEmpty ? const StatusBar() : const AlertBanner(compact: true),
        ),
      ),
      Expanded(
        child: Row(children: [
          CameraControls(view: view, recording: cameras.recording, simulated: cameras.simulated),
          Expanded(child: CameraArea(view: view, simulated: cameras.simulated)),
        ]),
      ),
    ]);
  }

  Widget _screens(AppServices s) {
    return Column(children: [
      const StatusBar(navigation: true),
      const AlertBanner(),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(kGap),
          child: ListenableBuilder(
            listenable: s.screens,
            builder: (context, _) {
              final screen = s.screens.value;
              return KeyedSubtree(
                key: ValueKey('screen-${screen.name}'),
                child: switch (screen) {
                  AppScreen.home => const HomeScreen(),
                  AppScreen.gauges => const GaugesScreen(),
                  AppScreen.media => const MediaScreen(),
                  AppScreen.navigation => const NavigationScreen(),
                  AppScreen.cameras => const CamerasScreen(),
                  AppScreen.settings => const SettingsScreen(),
                  AppScreen.diagnostics => const DiagnosticsScreen(),
                },
              );
            },
          ),
        ),
      ),
    ]);
  }
}
