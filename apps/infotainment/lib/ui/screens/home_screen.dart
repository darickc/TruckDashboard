import 'package:flutter/material.dart';

import '../../audio/audio_state.dart';
import '../../cameras/camera_state.dart';
import '../../config/app_config.dart';
import '../../core/settings.dart';
import '../../model/units.dart';
import '../../display/display_state.dart';
import '../../nav/position_state.dart';
import '../../nav/route_state.dart';
import '../../telemetry/telemetry_store.dart';
import '../../telemetry/warnings.dart';
import '../app_scope.dart';
import '../presentation.dart';
import '../shell/nav_buttons.dart';
import '../theme.dart';
import '../widgets/badges.dart';
import '../widgets/tap_target.dart';
import '../tone.dart';

export '../tone.dart' show HomeTone, homeToneColor;

/// The screens Home opens, in the order its buttons show them.
const homeButtons = [
  AppScreen.gauges,
  AppScreen.media,
  AppScreen.navigation,
  AppScreen.cameras,
  AppScreen.phones,
  AppScreen.settings,
];

/// One Home button's live state: a chip at its top right (optional) and one
/// or two lines under its name. Only what the screen it opens would show:
/// never a value that isn't current (CLAUDE.md rule 4), never a guess.
@immutable
class HomeStatus {
  const HomeStatus({
    this.badge,
    this.badgeTone = HomeTone.dim,
    required this.line,
    this.line2 = '',
    this.lineTone = HomeTone.dim,
  });

  final String? badge;
  final HomeTone badgeTone;
  final String line;
  final String line2;
  final HomeTone lineTone;

  @override
  String toString() => 'HomeStatus($badge/$badgeTone, "$line", "$line2", $lineTone)';
}

/// Gauges: the vehicle's state, then the selected gauge profile's first two
/// tiles. A value that isn't current shows as "—", never its last reading.
HomeStatus gaugesStatus(AppServices s) {
  final store = s.store;
  final units = s.settings.units;
  final profiles = s.config.profiles;
  final profile = profiles.firstWhere((x) => x.id == s.settings.profileId, orElse: () => profiles.first);
  final readouts = readoutLine(store, profile, units);
  switch (store.link) {
    case LinkState.connecting:
      return HomeStatus(badge: 'CONNECTING', badgeTone: HomeTone.stale, line: readouts);
    case LinkState.down:
      return HomeStatus(
        badge: 'NO DATA',
        badgeTone: HomeTone.critical,
        line: 'Vehicle data lost',
        lineTone: HomeTone.critical,
        line2: readouts,
      );
    case LinkState.up || LinkState.degraded:
      break;
  }
  final alerts = store.alerts;
  final worst = alerts.isEmpty
      ? AlertLevel.none
      : alerts.map((a) => a.level).reduce((a, b) => a.index >= b.index ? a : b);
  if (worst == AlertLevel.none) {
    return HomeStatus(badge: 'NORMAL', badgeTone: HomeTone.ok, line: readouts);
  }
  final first = alerts.firstWhere((a) => a.level == worst);
  final (title, _) = describeAlert(first, store, units);
  final more = alerts.length > 1 ? ' +${alerts.length - 1}' : '';
  final tone = worst == AlertLevel.critical ? HomeTone.critical : HomeTone.advisory;
  return HomeStatus(
    badge: worst == AlertLevel.critical ? 'CRITICAL' : 'ADVISORY',
    badgeTone: tone,
    line: '$title$more',
    lineTone: tone,
    line2: readouts,
  );
}

/// "EOT 198 °F · ECT 190 °F": the profile's first two tiles, "—" for one
/// that isn't current.
String readoutLine(TelemetryStore store, GaugeProfile profile, UnitSystem units) {
  return [
    for (final t in profile.tiles.take(2))
      if (store[t.signalId] case final st?)
        () {
          // Only the text is used; the palette only colours a status.
          final v = SignalView.of(store, t.signalId, units, Palette.night);
          return v.isCurrent && v.primary != '—'
              ? '${st.def.shortName} ${v.primary} ${v.unit}'
              : '${st.def.shortName} —';
        }(),
  ].join(' · ');
}

/// Media: what the phone is playing, as audio-manager reports it.
HomeStatus mediaStatus(AudioStatus a) {
  final r = a.report;
  if (a.link == AudioLink.down) {
    return const HomeStatus(
      badge: 'OFFLINE',
      badgeTone: HomeTone.advisory,
      line: 'Audio service not reachable',
    );
  }
  if (r == null) return const HomeStatus(line: 'Connecting…');
  if (r.phone == null) return const HomeStatus(line: 'No phone connected');
  final np = r.nowPlaying;
  if (np == null || np.title.isEmpty) return HomeStatus(line: 'Nothing playing', line2: r.phone!.name);
  final badge = switch (np.state) {
    PlayState.playing || PlayState.forwardSeek || PlayState.reverseSeek => ('PLAYING', HomeTone.ok),
    PlayState.paused => ('PAUSED', HomeTone.dim),
    PlayState.stopped => ('STOPPED', HomeTone.dim),
    PlayState.error => ('ERROR', HomeTone.advisory),
    PlayState.unknown => (null, HomeTone.dim),
  };
  return HomeStatus(
    badge: badge.$1,
    badgeTone: badge.$2,
    line: np.title,
    line2: np.artist,
    lineTone: HomeTone.text,
  );
}

/// Nav: the route if there is one (its destination only: distances that
/// aren't current are the Nav screen's to judge), else the GPS state.
HomeStatus navStatus(RouteView route, PositionState position) {
  final g = route.guidance;
  final to = g == null || g.destinationName.isEmpty ? '' : 'To ${g.destinationName}';
  switch (route.state) {
    case RouteState.active:
      return HomeStatus(badge: 'ROUTE', badgeTone: HomeTone.accent, line: to.isEmpty ? 'Route active' : to);
    case RouteState.routing:
      return HomeStatus(badge: 'ROUTING', badgeTone: HomeTone.accent, line: 'Finding a route…', line2: to);
    case RouteState.arrived:
      return HomeStatus(badge: 'ARRIVED', badgeTone: HomeTone.ok, line: to.isEmpty ? 'Arrived' : to);
    case RouteState.failed:
      return HomeStatus(badge: 'NO ROUTE', badgeTone: HomeTone.advisory, line: 'Routing failed', line2: to);
    case RouteState.idle || RouteState.unavailable || null:
      break;
  }
  final report = position.report;
  final sim = report?.simulated == true ? 'SIM ' : '';
  final (String? badge, HomeTone tone) = switch (position.link) {
    PositionLink.lost => ('NO GPS', HomeTone.advisory),
    PositionLink.connecting => (null, HomeTone.dim),
    PositionLink.connected => switch (report?.status) {
      FixStatus.fix2d || FixStatus.fix3d when report!.current => (
        '${sim}GPS FIX',
        sim.isEmpty ? HomeTone.ok : HomeTone.simulated,
      ),
      FixStatus.fix2d || FixStatus.fix3d => ('GPS STALE', HomeTone.advisory),
      FixStatus.noFix => ('NO FIX', HomeTone.advisory),
      _ => ('NO GPS', HomeTone.advisory),
    },
  };
  return HomeStatus(badge: badge, badgeTone: tone, line: 'No route · Places, Search');
}

/// Cameras: recording, as camera-manager reports it (the status bar's REC
/// chip, in words).
HomeStatus camerasStatus(CameraStatus c) {
  if (c.link == CameraLink.down) {
    return const HomeStatus(
      badge: 'OFFLINE',
      badgeTone: HomeTone.advisory,
      line: 'Camera service not reachable',
    );
  }
  final r = c.recording;
  if (c.link == CameraLink.connecting || r == null) return const HomeStatus(line: 'Front, left, right, rear');
  if (r.isOff) return const HomeStatus(line: 'Recording off');
  String names(Iterable<CameraRecording> cams) =>
      cams.map((x) => cameraShortName(x.camera).toLowerCase()).join(', ');
  final sim = c.simulated ? 'SIM ' : '';
  final down = r.inState(RecordingState.notRecording);
  final rec = r.inState(RecordingState.recording);
  if (down.isNotEmpty) {
    return HomeStatus(
      badge: '${sim}NOT REC',
      badgeTone: HomeTone.advisory,
      line: 'Not recording: ${names(down)}',
      lineTone: HomeTone.advisory,
    );
  }
  if (rec.isNotEmpty) {
    return HomeStatus(
      badge: '${sim}REC',
      badgeTone: c.simulated ? HomeTone.simulated : HomeTone.critical,
      line: 'Recording ${names(rec)}',
    );
  }
  return HomeStatus(badge: '${sim}REC', badgeTone: HomeTone.stale, line: 'Recording starting');
}

/// Phone: the connected phone, or why there is none.
HomeStatus phoneStatus(AudioStatus a) {
  final r = a.report;
  if (a.link == AudioLink.down) {
    return const HomeStatus(
      badge: 'OFFLINE',
      badgeTone: HomeTone.advisory,
      line: 'Phone service not reachable',
    );
  }
  if (r == null) return const HomeStatus(line: 'Connecting…');
  if (!r.bluetoothReady) {
    return HomeStatus(
      badge: 'BLUETOOTH OFF',
      badgeTone: HomeTone.advisory,
      line: r.bluetoothDetail.isEmpty ? 'Bluetooth not ready' : r.bluetoothDetail,
    );
  }
  final phone = r.phone;
  if (phone == null) {
    return HomeStatus(
      line: 'No phone connected',
      line2: r.connect.busy ? 'Connecting ${r.connect.name}…' : '',
    );
  }
  final call = r.call;
  if (call != null) {
    return HomeStatus(
      badge: 'CALL',
      badgeTone: HomeTone.ok,
      line: call.caller,
      line2: phone.name,
      lineTone: HomeTone.text,
    );
  }
  return HomeStatus(badge: 'CONNECTED', badgeTone: HomeTone.ok, line: phone.name, lineTone: HomeTone.text);
}

/// Settings: the theme and the backlight's level.
HomeStatus settingsStatus(DisplayStatus d) {
  final mode = d.mode == DayNight.day ? 'Day' : 'Night';
  final theme = d.choice == DisplayChoice.auto ? 'Auto: $mode' : mode;
  final pct = d.pct;
  return HomeStatus(line: pct == null ? theme : '$theme · $pct %', line2: 'Diagnostics');
}

/// Home: one large button per screen, three across and two down
/// (ADR-0034), each with a live line saying what that screen would show
/// (ADR-0034 amendment, 2026-11-18). Diagnostics is opened from Settings,
/// Recordings from Cameras. Every other screen has Back at its top left
/// (shell/nav_buttons.dart). Alerts show above it in the banner, as on
/// every screen.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final rows = [
      for (var i = 0; i < homeButtons.length; i += _columns)
        homeButtons.sublist(i, (i + _columns).clamp(0, homeButtons.length)),
    ];
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.store,
        s.settings,
        s.audio.status,
        s.cameras.status,
        s.route.state,
        s.position.status,
        s.display.status,
      ]),
      builder: (context, _) {
        HomeStatus statusOf(AppScreen screen) => switch (screen) {
          AppScreen.gauges => gaugesStatus(s),
          AppScreen.media => mediaStatus(s.audio.status.value),
          AppScreen.navigation => navStatus(s.route.state.value, s.position.status.value),
          AppScreen.cameras => camerasStatus(s.cameras.status.value),
          AppScreen.phones => phoneStatus(s.audio.status.value),
          AppScreen.settings => settingsStatus(s.display.status.value),
          _ => const HomeStatus(line: ''),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (r, row) in rows.indexed) ...[
              if (r > 0) const SizedBox(height: kGap),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (c, screen) in row.indexed) ...[
                      if (c > 0) const SizedBox(width: kGap),
                      Expanded(
                        child: () {
                          final status = statusOf(screen);
                          return TapTarget(
                            key: ValueKey('home-${screen.name}'),
                            label: [
                              screenLabels[screen]!,
                              status.badge,
                              status.line,
                            ].where((x) => x != null && x.isNotEmpty).join(', '),
                            padding: const EdgeInsets.all(14),
                            onTap: () => s.screens.open(screen),
                            child: _HomeButton(screen, status),
                          );
                        }(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HomeButton extends StatelessWidget {
  const _HomeButton(this.screen, this.status);

  final AppScreen screen;
  final HomeStatus status;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final badge = status.badge;
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(screenIcons[screen], size: 30, color: p.accent),
              ),
              const SizedBox(width: 8),
              // The chip sits at the top right and ellipsizes rather than
              // overflow on a narrow button.
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: badge == null
                      ? const SizedBox.shrink()
                      : Pill(
                          badge,
                          key: ValueKey('home-badge-${screen.name}'),
                          color: homeToneColor(status.badgeTone, p),
                        ),
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                screenLabels[screen]!,
                maxLines: 1,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: p.text),
              ),
              const SizedBox(height: 2),
              Text(
                status.line,
                key: ValueKey('home-line-${screen.name}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: status.lineTone == HomeTone.dim ? FontWeight.w400 : FontWeight.w600,
                  fontFeatures: tabular,
                  color: status.lineTone == HomeTone.dim ? p.textDim : homeToneColor(status.lineTone, p),
                ),
              ),
              if (status.line2.isNotEmpty)
                Text(
                  status.line2,
                  key: ValueKey('home-line2-${screen.name}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontFeatures: tabular, color: p.textDim),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
