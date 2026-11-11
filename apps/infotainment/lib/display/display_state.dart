import 'package:flutter/foundation.dart';

import '../core/settings.dart';

/// Day/night and the backlight, as power-manager reports them
/// (f250.power.v1, ADR-0028). power-manager decides the mode and sets the
/// backlight; the dashboard only follows the mode for its palette and sends
/// the driver's changes.
enum DisplayChoice { auto, day, night }

/// What decided the mode.
enum ModeBasis { sun, manual, fallback }

/// Whether the sun is known, and if not, why.
enum SunStatus { known, noLocation, clockNotSynchronized, clockNotSet }

/// Where the display state comes from.
enum DisplayLink {
  /// No power-manager: the browser preview, the macOS window, tests.
  simulated,
  connecting,
  connected,

  /// It was, or never answered: the screen keeps its last theme and the
  /// backlight isn't controlled.
  lost,
}

/// power-manager's state, as sent.
@immutable
class DisplayReport {
  const DisplayReport({
    required this.mode,
    required this.choice,
    required this.basis,
    required this.sun,
    this.sunElevationDeg,
    required this.dayPct,
    required this.nightPct,
    required this.minPct,
    this.backlight,
    required this.brightnessPct,
    this.backlightProblem = '',
  });

  final DayNight mode;
  final DisplayChoice choice;
  final ModeBasis basis;
  final SunStatus sun;

  /// Only while [sun] is known.
  final double? sunElevationDeg;
  final int dayPct;
  final int nightPct;
  final int minPct;

  /// The backlight's name; null: none found.
  final String? backlight;

  /// The level being set for the current mode, percent.
  final int brightnessPct;

  /// Why the backlight isn't following; empty when it is.
  final String backlightProblem;

  int pctFor(DayNight m) => m == DayNight.day ? dayPct : nightPct;

  @override
  bool operator ==(Object other) =>
      other is DisplayReport &&
      other.mode == mode &&
      other.choice == choice &&
      other.basis == basis &&
      other.sun == sun &&
      other.sunElevationDeg == sunElevationDeg &&
      other.dayPct == dayPct &&
      other.nightPct == nightPct &&
      other.minPct == minPct &&
      other.backlight == backlight &&
      other.brightnessPct == brightnessPct &&
      other.backlightProblem == backlightProblem;

  @override
  int get hashCode => Object.hash(mode, choice, basis, sun, sunElevationDeg, dayPct, nightPct,
      minPct, backlight, brightnessPct, backlightProblem);
}

/// What the dashboard shows and offers.
@immutable
class DisplayStatus {
  const DisplayStatus({
    required this.link,
    required this.mode,
    required this.choice,
    this.report,
    this.dayPct,
    this.nightPct,
    this.minPct = 10,
    this.detail = '',
  });

  final DisplayLink link;

  /// The palette in use.
  final DayNight mode;

  /// The choice the buttons show as selected.
  final DisplayChoice choice;

  /// power-manager's last report while connected; null otherwise.
  final DisplayReport? report;

  /// The brightness levels, percent; null when not known (no
  /// power-manager connected).
  final int? dayPct;
  final int? nightPct;

  /// Neither level goes below this.
  final int minPct;

  /// Why the link is down, from the client.
  final String detail;

  /// The level for the current mode, if known.
  int? get pct => mode == DayNight.day ? dayPct : nightPct;

  /// Auto needs power-manager (the sun and the clock are its).
  bool get canAuto => link == DisplayLink.connected;

  /// Brightness changes reach a backlight, or the simulation's stand-in.
  bool get canSetBrightness => pct != null;

  @override
  bool operator ==(Object other) =>
      other is DisplayStatus &&
      other.link == link &&
      other.mode == mode &&
      other.choice == choice &&
      other.report == report &&
      other.dayPct == dayPct &&
      other.nightPct == nightPct &&
      other.minPct == minPct &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(link, mode, choice, report, dayPct, nightPct, minPct, detail);
}

String _modeName(DayNight m) => m == DayNight.day ? 'Day' : 'Night';

/// One line for the screen: what decides the theme now, and why Auto can't
/// follow the sun when it can't. Never claims a control it doesn't have.
String describeMode(DisplayStatus s) {
  final r = s.report;
  switch (s.link) {
    case DisplayLink.simulated:
      return 'Simulated: no power-manager, so Auto can\'t follow the sun and '
          'nothing sets the backlight. ${_modeName(s.mode)} theme.';
    case DisplayLink.connecting:
    case DisplayLink.lost:
      final why = s.detail.isEmpty ? '' : ' (${s.detail})';
      return 'power-manager not connected$why: the theme is set on this screen only, '
          'and the backlight isn\'t controlled.';
    case DisplayLink.connected:
      if (r == null) return 'Waiting for power-manager.';
      final sun = r.sunElevationDeg == null
          ? ''
          : 'sun ${r.sunElevationDeg! >= 0 ? '' : '−'}${r.sunElevationDeg!.abs().toStringAsFixed(1)}°';
      return switch (r.basis) {
        ModeBasis.sun => 'Auto: ${_modeName(r.mode)} by the sun ($sun).',
        ModeBasis.manual => '${_modeName(r.mode)}, chosen by hand${sun.isEmpty ? '' : ' ($sun)'}.',
        ModeBasis.fallback => 'Auto unavailable: ${switch (r.sun) {
            SunStatus.noLocation => 'no location configured',
            SunStatus.clockNotSynchronized => 'clock not synchronized',
            SunStatus.clockNotSet => 'clock not set',
            SunStatus.known => 'sun unknown',
          }}. Showing ${_modeName(r.mode)}.',
      };
  }
}

/// One line about the backlight, or null when there is nothing to say
/// beyond the level.
String? describeBacklight(DisplayStatus s) {
  final r = s.report;
  if (s.link != DisplayLink.connected || r == null) return null;
  if (r.backlight == null) {
    return 'No backlight: ${r.backlightProblem.isEmpty ? 'none found' : r.backlightProblem}.';
  }
  if (r.backlightProblem.isNotEmpty) return 'Backlight ${r.backlight}: ${r.backlightProblem}.';
  return null;
}

/// Where the display state comes from: power-manager, or a simulation.
abstract class DisplaySource {
  ValueListenable<DisplayStatus> get status;

  void start();
  void stop();

  /// Auto, Day or Night. Auto only while connected.
  Future<void> setChoice(DisplayChoice choice);

  /// The brightness for [mode], in percent (power-manager clamps it).
  Future<void> setBrightness(DayNight mode, int pct);
}

/// No power-manager: Day or Night by hand, and brightness levels kept but
/// applied to nothing. Auto isn't offered: there is no sun here.
class SimulatedDisplaySource implements DisplaySource {
  SimulatedDisplaySource({DayNight mode = DayNight.night})
      : _status = ValueNotifier(_make(mode, 100, 40));

  static const minPct = 10;
  final ValueNotifier<DisplayStatus> _status;

  static DisplayStatus _make(DayNight mode, int day, int night) => DisplayStatus(
      link: DisplayLink.simulated,
      mode: mode,
      choice: mode == DayNight.day ? DisplayChoice.day : DisplayChoice.night,
      dayPct: day,
      nightPct: night,
      minPct: minPct);

  @override
  ValueListenable<DisplayStatus> get status => _status;

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Future<void> setChoice(DisplayChoice choice) async {
    final s = _status.value;
    final mode = switch (choice) {
      DisplayChoice.auto => null, // not offered
      DisplayChoice.day => DayNight.day,
      DisplayChoice.night => DayNight.night,
    };
    if (mode != null) _status.value = _make(mode, s.dayPct!, s.nightPct!);
  }

  @override
  Future<void> setBrightness(DayNight mode, int pct) async {
    final s = _status.value;
    final v = pct.clamp(minPct, 100);
    _status.value = _make(s.mode, mode == DayNight.day ? v : s.dayPct!,
        mode == DayNight.night ? v : s.nightPct!);
  }
}
