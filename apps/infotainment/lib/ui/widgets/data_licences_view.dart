import 'package:flutter/material.dart';

import '../../nav/data_licences.dart';
import '../../nav/offline_map.dart';
import '../app_scope.dart';
import '../theme.dart';

/// Data licences (Diagnostics → Licences): every source of the navigation
/// data, its licence, and openstreetmap.org/copyright, which the screen
/// can't open as a link, with the installed map's own credit and date. The
/// OSMF attribution guideline asks for this to be findable on the device
/// (docs/setup/map-data.md).
class DataLicencesView extends StatelessWidget {
  const DataLicencesView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder<MapFileState>(
      valueListenable: AppScope.of(context).map.state,
      builder: (context, state, _) {
        final reader = state is MapReady ? state.reader : null;
        final installed = reader == null
            ? 'No map installed.'
            : [
                'Installed map: ${reader.attribution ?? kOsmCredit}',
                if (reader.dataDate != null) 'data ${reader.dataDate}',
              ].join(' · ');
        return ListView(children: [
          Text('Data licences', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text)),
          const SizedBox(height: 4),
          Text(installed,
              key: const ValueKey('licences-installed-map'), style: TextStyle(fontSize: 14, color: p.textDim)),
          for (final l in dataLicences) ...[
            const SizedBox(height: 8),
            Text(l.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: p.text)),
            Text(l.text, key: ValueKey('licences-${l.key}'), style: TextStyle(fontSize: 14, color: p.text)),
          ],
        ]);
      },
    );
  }
}
