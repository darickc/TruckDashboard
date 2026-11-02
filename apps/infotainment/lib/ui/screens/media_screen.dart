import 'package:flutter/material.dart';

import '../widgets/panel.dart';

class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotImplementedScreen(
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Media — not implemented yet',
        lines: [
          'Bluetooth audio (A2DP), track info and playback controls arrive in Phase 6.',
          'Nothing is connected. No audio is playing from this unit.',
        ],
      );
}
