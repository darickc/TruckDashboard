import 'power_stub.dart' if (dart.library.io) 'power_io.dart' as impl;

/// The app's exit code for "power the head unit off". The app only exits;
/// its launcher sees this code and powers the Pi off: on AGL
/// agl/rootfs/opt/f250/libexec/dashboard-stopped, on Raspberry Pi OS
/// tools/pi/run.sh after stopping the recorder and gateway cleanly. Keep
/// them in step (make agl-test checks).
const powerOffExitCode = 42;

/// The app's exit code for "restart the head unit": the same launchers
/// reboot the Pi instead.
const restartExitCode = 43;

/// Shutting the head unit down, or restarting it, from the Settings screen
/// (MX+ trial, Phase 3.5.3: there is no ignition sensing yet, so the driver
/// shuts down before key-off).
abstract class PowerControl {
  /// False unless the launcher said it can power off and restart: then the
  /// app shows neither button.
  bool get canPowerOff;

  /// Ends the app with [powerOffExitCode]. Does not return on the Pi.
  void powerOff();

  /// Ends the app with [restartExitCode]. Does not return on the Pi.
  void restart();

  /// `F250_POWER_OFF=1` from the launcher (the AGL dashboard unit, or run.sh
  /// in the kiosk when logind lets the session power off). It handles both
  /// exit codes. Never available on the web build.
  static PowerControl forPlatform() => impl.platformPowerControl();
}

/// No Power or Restart button: the web preview, the macOS window, tests by
/// default.
class NoPowerControl implements PowerControl {
  const NoPowerControl();

  @override
  bool get canPowerOff => false;

  @override
  void powerOff() => throw UnsupportedError('This build cannot power the head unit off');

  @override
  void restart() => throw UnsupportedError('This build cannot restart the head unit');
}
