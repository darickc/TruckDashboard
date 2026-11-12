import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import 'tap_target.dart';

/// How long the Power or Restart question stays up without an answer.
const kPowerConfirmTimeout = Duration(seconds: 8);

enum PowerAction { restart, powerOff }

enum _State { idle, confirming, working }

/// A row of [leading] (the Settings sections), then Restart and Power when
/// the launcher can do them (PowerControl.canPowerOff). Each asks first:
/// the question takes the row's place for [kPowerConfirmTimeout], with
/// Cancel and the action. In place, not a dialog, which would cover the
/// alert banner.
class PowerRow extends StatefulWidget {
  const PowerRow({super.key, required this.leading});

  final Widget leading;

  @override
  State<PowerRow> createState() => _PowerRowState();
}

class _PowerRowState extends State<PowerRow> {
  var _state = _State.idle;
  var _action = PowerAction.powerOff;
  Timer? _timeout;

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  void _ask(PowerAction a) {
    _timeout?.cancel();
    _timeout = Timer(kPowerConfirmTimeout, _cancel);
    setState(() {
      _action = a;
      _state = _State.confirming;
    });
  }

  void _cancel() {
    _timeout?.cancel();
    if (mounted) setState(() => _state = _State.idle);
  }

  void _confirm() {
    _timeout?.cancel();
    setState(() => _state = _State.working);
    final power = AppScope.of(context).power;
    switch (_action) {
      case PowerAction.powerOff:
        power.powerOff();
      case PowerAction.restart:
        power.restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      height: kMinTouch,
      child: switch (_state) {
        _State.idle => _idle(p),
        _State.confirming => _question(p),
        _State.working => Center(
            child: Text(
                _action == PowerAction.powerOff
                    ? 'Shutting down. Wait until the screen goes dark before turning the key off.'
                    : 'Restarting. The dashboard comes back once the head unit has started again.',
                key: const ValueKey('power-progress'),
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text))),
      },
    );
  }

  Widget _idle(Palette p) {
    final s = AppScope.of(context);
    if (!s.power.canPowerOff) return widget.leading;
    Widget button(PowerAction a, String key, String semantics, IconData icon, String text) =>
        SizedBox(
          width: 140,
          child: TapTarget(
            key: ValueKey(key),
            label: semantics,
            onTap: () => _ask(a),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 24, color: p.text),
                const SizedBox(width: 6),
                Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
              ]),
            ),
          ),
        );
    return Row(children: [
      Expanded(child: widget.leading),
      const SizedBox(width: 16),
      button(PowerAction.restart, 'settings-restart', 'Restart the head unit',
          Icons.restart_alt_rounded, 'Restart'),
      const SizedBox(width: kGap),
      button(PowerAction.powerOff, 'settings-power', 'Shut down the head unit',
          Icons.power_settings_new_rounded, 'Power'),
    ]);
  }

  Widget _question(Palette p) {
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
    final off = _action == PowerAction.powerOff;
    return Row(children: [
      SizedBox(
        width: 150,
        child: TapTarget(
            key: const ValueKey('power-cancel'),
            label: off ? 'Cancel shutdown' : 'Cancel restart',
            onTap: _cancel,
            child: const Text('Cancel', style: label)),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
              off
                  ? 'Shut down the head unit? Data is saved first.'
                  : 'Restart the head unit? Data is saved first.',
              key: const ValueKey('power-question'),
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
        ),
      ),
      SizedBox(
        width: 150,
        child: TapTarget(
            key: const ValueKey('power-confirm'),
            label: off ? 'Shut down now' : 'Restart now',
            onTap: _confirm,
            child: Text(off ? 'Shut down' : 'Restart',
                style: label.copyWith(color: off ? p.critical : p.advisory))),
      ),
    ]);
  }
}
