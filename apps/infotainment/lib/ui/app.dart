import 'package:flutter/material.dart';

import '../core/settings.dart';
import 'app_scope.dart';
import 'shell/app_shell.dart';
import 'shell/preview_frame.dart';
import 'theme.dart';

class InfotainmentApp extends StatelessWidget {
  const InfotainmentApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'F-250',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(services.settings.theme),
          builder: (context, child) => PreviewFrame(child: child!),
          home: const AppShell(),
        ),
      ),
    );
  }
}

/// Shown instead of the dashboard if configuration fails to load. A bad
/// config must never come up looking like a working dashboard.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(DayNight.night),
      builder: (context, child) => PreviewFrame(child: child!),
      home: Builder(builder: (context) {
        final p = Palette.of(context);
        return ColoredBox(
          color: p.background,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Startup failed — no vehicle data is shown',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.critical)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text('$error', style: TextStyle(fontSize: 15, color: p.text)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
