import 'package:flutter/material.dart';

import '../widgets/panel.dart';

class NavigationScreen extends StatelessWidget {
  const NavigationScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotImplementedScreen(
        icon: Icons.map_outlined,
        title: 'Navigation — not implemented yet',
        lines: [
          'Offline OpenStreetMap display, GPS position and routing arrive in Phase 6.',
          'Routing will not be guaranteed safe for heavy vehicles or trailers.',
        ],
      );
}
