import 'package:flutter/material.dart';

import '../widgets/panel.dart';

class CamerasScreen extends StatelessWidget {
  const CamerasScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotImplementedScreen(
        icon: Icons.videocam_off_rounded,
        title: 'Cameras — not implemented yet',
        lines: [
          'Rear and side cameras, and reverse / turn-signal switching, arrive in Phase 6.',
          'This is not a safety camera system. Always use the mirrors.',
        ],
      );
}
