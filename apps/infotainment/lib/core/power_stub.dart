import 'power.dart';

/// Web builds cannot power anything off.
PowerControl platformPowerControl() => const NoPowerControl();
