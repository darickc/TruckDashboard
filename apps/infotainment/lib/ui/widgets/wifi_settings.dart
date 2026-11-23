import 'package:flutter/material.dart';

import '../../network/wifi_state.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'on_screen_keyboard.dart';
import 'tap_target.dart';

/// Settings › System › Wi-Fi (ADR-0052): the networks connman sees, through
/// services/network. Tap a network to choose it, then Join (a secured
/// network not joined before asks for its passphrase, typed on the
/// on-screen keyboard), Leave or Forget. Wi-Fi on or off, and Scan. The
/// passphrase goes to connman, which keeps it; nothing here keeps it after
/// the attempt. Being on a network is what lets the Nav screen use the
/// online map and Mapbox's routes.
class WifiSettingsView extends StatefulWidget {
  const WifiSettingsView({super.key, this.leading});

  /// Shown at the left of the top row (Settings › System's back button).
  final Widget? leading;

  @override
  State<WifiSettingsView> createState() => _WifiSettingsViewState();
}

class _WifiSettingsViewState extends State<WifiSettingsView> {
  /// The network tapped, by id.
  String? _selected;

  /// The network whose passphrase is being typed, and what is typed.
  WifiNetwork? _asking;
  String _passphrase = '';
  bool _showPassphrase = false;

  /// A call running (its words), and the last outcome.
  String? _busy;
  String? _message;
  bool _messageIsError = false;
  bool _scannedOnce = false;

  WifiSource get _wifi => AppScope.of(context).wifi;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Look for networks once when the page opens.
    if (!_scannedOnce) {
      _scannedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wifi.view.value.enabled) _wifi.scan();
      });
    }
  }

  Future<void> _run(String what, Future<String?> Function() call, {String? done}) async {
    setState(() {
      _busy = what;
      _message = null;
    });
    final err = await call();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _message = err ?? done;
      _messageIsError = err != null;
    });
  }

  Future<void> _join(WifiNetwork n, {String passphrase = ''}) async {
    setState(() {
      _busy = 'Joining ${n.name}…';
      _message = null;
      _asking = null;
    });
    final r = await _wifi.connect(n.id, passphrase: passphrase);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _passphrase = '';
      _showPassphrase = false;
      _messageIsError = !r.connected;
      _message = r.connected ? 'Joined ${n.name}' : '${n.name}: ${r.detail.isEmpty ? "couldn't join" : r.detail}';
    });
  }

  void _choose(WifiNetwork n) {
    if (!n.joinable) {
      setState(() {
        _selected = n.id;
        _messageIsError = true;
        _message = "${n.name} uses 802.1X (enterprise) sign-in, which can't be set from here";
      });
      return;
    }
    setState(() {
      _selected = _selected == n.id ? null : n.id;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ValueListenableBuilder(
      valueListenable: _wifi.view,
      builder: (context, view, _) {
        final asking = _asking;
        if (asking != null) return _passphraseEntry(p, asking);
        return Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(p, view),
              const SizedBox(height: kGap),
              if (_busy != null || _message != null) ...[
                Text(
                  _busy ?? _message!,
                  key: const ValueKey('wifi-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _busy != null ? p.accent : (_messageIsError ? p.advisory : p.ok),
                  ),
                ),
                const SizedBox(height: kGap),
              ],
              Expanded(child: _list(p, view)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(Palette p, WifiView view) {
    final current = view.current;
    final status = switch (view) {
      WifiView(link: WifiLink.connecting) => 'Connecting to the network service…',
      WifiView(link: WifiLink.lost) => 'Unavailable: ${view.detail}',
      WifiView(available: false) => view.detail.isEmpty ? 'Wi-Fi unavailable' : view.detail,
      WifiView(enabled: false) => 'Wi-Fi is off',
      _ when current != null => [
        'On ${current.name}',
        if (view.address.isNotEmpty) view.address,
        switch (view.connectivity) {
          Connectivity.online => 'internet reached',
          Connectivity.connected => 'connected',
          _ => 'no network',
        },
      ].join(' · '),
      _ => 'Not on a network',
    };
    final usable = view.link == WifiLink.connected && view.available;
    return Row(
      children: [
        if (widget.leading case final l?) ...[l, const SizedBox(width: kGap)],
        SizedBox(
          width: 130,
          child: TapTarget(
            key: const ValueKey('wifi-power'),
            label: view.enabled ? 'Turn Wi-Fi off' : 'Turn Wi-Fi on',
            selected: view.enabled,
            onTap: usable && _busy == null
                ? () => _run(
                    view.enabled ? 'Turning Wi-Fi off…' : 'Turning Wi-Fi on…',
                    () => _wifi.setEnabled(!view.enabled),
                  )
                : () {},
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(view.enabled ? Icons.wifi : Icons.wifi_off, size: 24),
                  const SizedBox(width: 6),
                  Text(view.enabled ? 'Wi-Fi on' : 'Wi-Fi off', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: kGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                key: const ValueKey('wifi-status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: usable ? p.text : p.advisory),
              ),
              if (view.simulated)
                Text(
                  'SIMULATED: made-up networks, not the truck',
                  key: const ValueKey('wifi-simulated'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.simulated),
                ),
            ],
          ),
        ),
        const SizedBox(width: kGap),
        SizedBox(
          width: 110,
          child: TapTarget(
            key: const ValueKey('wifi-scan'),
            label: 'Look for networks',
            onTap: usable && view.enabled && _busy == null && !view.scanning
                ? () => _run('Looking for networks…', _wifi.scan)
                : () {},
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(view.scanning ? 'Scanning…' : 'Scan', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _list(Palette p, WifiView view) {
    if (!view.enabled || view.link != WifiLink.connected || !view.available) return const SizedBox.shrink();
    if (view.networks.isEmpty) {
      return Center(
        child: Text('No networks seen yet', style: TextStyle(fontSize: 16, color: p.textDim)),
      );
    }
    return ListView.separated(
      key: const ValueKey('wifi-list'),
      itemCount: view.networks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final n = view.networks[i];
        final selected = n.id == _selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TapTarget(
              key: ValueKey('wifi-network-${n.id}'),
              label: '${n.name}, ${_stateWords(n)}',
              selected: selected,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onTap: () => _choose(n),
              child: Row(
                children: [
                  Icon(_strengthIcon(n.strength), size: 26, color: n.isConnected ? p.accent : p.text),
                  if (n.security != WifiSecurity.open) Icon(Icons.lock, size: 16, color: p.textDim),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      n.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _stateWords(n),
                    style: TextStyle(
                      fontSize: 14,
                      color: n.state == WifiNetworkState.failed ? p.advisory : (n.isConnected ? p.ok : p.textDim),
                    ),
                  ),
                ],
              ),
            ),
            if (selected && n.joinable) ...[
              const SizedBox(height: 6),
              _actions(n),
            ],
          ],
        );
      },
    );
  }

  Widget _actions(WifiNetwork n) {
    final idle = _busy == null;
    Widget button(String key, String text, IconData icon, VoidCallback onTap) => Expanded(
      child: TapTarget(
        key: ValueKey(key),
        label: '$text ${n.name}',
        onTap: idle ? onTap : () {},
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 6),
              Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
    final buttons = <Widget>[
      if (n.isConnected)
        button('wifi-leave', 'Leave', Icons.link_off, () => _run('Leaving ${n.name}…', () => _wifi.disconnect(n.id)))
      else
        button('wifi-join', 'Join', Icons.wifi, () {
          if (n.needsPassphrase) {
            setState(() {
              _asking = n;
              _passphrase = '';
              _message = null;
            });
          } else {
            _join(n);
          }
        }),
      if (n.saved)
        button(
          'wifi-forget',
          'Forget',
          Icons.delete_outline,
          () => _run('Forgetting ${n.name}…', () => _wifi.forget(n.id), done: '${n.name} forgotten'),
        ),
    ];
    final spaced = <Widget>[];
    for (final (i, b) in buttons.indexed) {
      if (i > 0) spaced.add(const SizedBox(width: kGap));
      spaced.add(b);
    }
    return Row(children: spaced);
  }

  Widget _passphraseEntry(Palette p, WifiNetwork n) {
    final shown = _showPassphrase ? _passphrase : '•' * _passphrase.length;
    // Cancel is the way back from here. The field's row and the keyboard
    // just fit the Settings panel at 800×480; under an alert banner the
    // page scrolls rather than squeezing the 60-pixel keys.
    return SingleChildScrollView(
      child: Column(
        key: const ValueKey('wifi-passphrase-entry'),
        children: [
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TapTarget(
                  key: const ValueKey('wifi-passphrase-cancel'),
                  label: 'Cancel',
                  onTap: () => setState(() {
                    _asking = null;
                    _passphrase = '';
                    _showPassphrase = false;
                  }),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Cancel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: kGap),
              Expanded(
                child: Container(
                  height: kMinTouch,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: p.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.accent),
                  ),
                  child: Text(
                    _passphrase.isEmpty ? 'Passphrase for ${n.name}' : shown,
                    key: const ValueKey('wifi-passphrase'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 20, color: _passphrase.isEmpty ? p.textDim : p.text),
                  ),
                ),
              ),
              const SizedBox(width: kGap),
              SizedBox(
                width: 90,
                child: TapTarget(
                  key: const ValueKey('wifi-passphrase-show'),
                  label: _showPassphrase ? 'Hide the passphrase' : 'Show the passphrase',
                  selected: _showPassphrase,
                  onTap: () => setState(() => _showPassphrase = !_showPassphrase),
                  child: Icon(_showPassphrase ? Icons.visibility_off : Icons.visibility, size: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          OnScreenKeyboard(
            caseSensitive: true,
            onText: (t) => setState(() => _passphrase += t),
            onBackspace: () => setState(() {
              if (_passphrase.isNotEmpty) _passphrase = _passphrase.substring(0, _passphrase.length - 1);
            }),
            onDone: () {
              if (_passphrase.isNotEmpty) _join(n, passphrase: _passphrase);
            },
            doneLabel: 'Join',
          ),
        ],
      ),
    );
  }
}

String _stateWords(WifiNetwork n) => switch (n.state) {
  WifiNetworkState.online => 'Connected',
  WifiNetworkState.connected => 'Connected',
  WifiNetworkState.connecting => 'Joining…',
  WifiNetworkState.disconnecting => 'Leaving…',
  WifiNetworkState.failed => wifiErrorWords(n.error).isEmpty ? 'Failed' : wifiErrorWords(n.error),
  _ when n.saved => 'Saved',
  _ when n.security == WifiSecurity.enterprise => '802.1X',
  _ when n.security == WifiSecurity.open => 'Open',
  _ => '',
};

IconData _strengthIcon(int s) => switch (s) {
  >= 70 => Icons.signal_wifi_4_bar,
  >= 45 => Icons.network_wifi_3_bar,
  >= 20 => Icons.network_wifi_2_bar,
  _ => Icons.network_wifi_1_bar,
};
