import 'power_stub.dart' if (dart.library.io) 'power_io.dart' as impl;

/// The app's exit code for "power the head unit off". The app only exits;
/// tools/pi/run.sh sees this code, stops the recorder and gateway cleanly,
/// then powers the Pi off. Keep the two in step.
const powerOffExitCode = 42;

/// Shutting the head unit down from the screen (MX+ trial, Phase 3.5.3: there
/// is no ignition sensing yet, so the driver shuts down before key-off).
abstract class PowerControl {
  /// False unless the launcher said it can power off: then the app shows no
  /// shutdown button at all.
  bool get canPowerOff;

  /// Ends the app with [powerOffExitCode]. Does not return on the Pi.
  void powerOff();

  /// `F250_POWER_OFF=1` from run.sh (kiosk under cage, and logind lets the
  /// session power off).
  /// Never available on the web build.
  static PowerControl forPlatform() => impl.platformPowerControl();
}

/// No shutdown button: the web preview, the macOS window, tests by default.
class NoPowerControl implements PowerControl {
  const NoPowerControl();

  @override
  bool get canPowerOff => false;

  @override
  void powerOff() => throw UnsupportedError('This build cannot power the head unit off');
}
