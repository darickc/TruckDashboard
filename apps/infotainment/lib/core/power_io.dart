import 'dart:io';

import 'power.dart';

PowerControl platformPowerControl() => Platform.environment['F250_POWER_OFF'] == '1'
    ? const _ExitPowerControl()
    : const NoPowerControl();

class _ExitPowerControl implements PowerControl {
  const _ExitPowerControl();

  @override
  bool get canPowerOff => true;

  @override
  void powerOff() => exit(powerOffExitCode);
}
