import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../presentation.dart';
import '../theme.dart';

/// Rebuilds when telemetry or settings change, handing over a ready-made
/// [SignalView].
class SignalBuilder extends StatelessWidget {
  const SignalBuilder({super.key, required this.signalId, required this.builder});

  final String signalId;
  final Widget Function(BuildContext context, SignalView view) builder;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.store, services.settings]),
      builder: (context, _) => builder(
        context,
        SignalView.of(services.store, signalId, services.settings.units, Palette.of(context)),
      ),
    );
  }
}
