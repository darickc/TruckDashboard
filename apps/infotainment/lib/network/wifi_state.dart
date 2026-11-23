import 'dart:async';

import 'package:flutter/foundation.dart';

/// Wi-Fi as services/network reports it from connman (f250.network.v1,
/// ADR-0052). The dashboard never talks to connman: it asks the service,
/// which hands passphrases to connman and keeps none.
enum Connectivity { unknown, offline, connected, online }

enum WifiSecurity { unknown, open, psk, wep, enterprise }

enum WifiNetworkState { unknown, idle, connecting, connected, online, disconnecting, failed }

enum WifiLink { connecting, connected, lost }

@immutable
class WifiNetwork {
  const WifiNetwork({
    required this.id,
    required this.name,
    this.strength = 0,
    this.security = WifiSecurity.unknown,
    this.saved = false,
    this.state = WifiNetworkState.idle,
    this.error = '',
  });

  /// connman's service id: what the calls take.
  final String id;
  final String name;

  /// 0–100.
  final int strength;
  final WifiSecurity security;

  /// connman remembers it and its passphrase, and joins it by itself.
  final bool saved;
  final WifiNetworkState state;
  final String error;

  bool get isConnected => state == WifiNetworkState.connected || state == WifiNetworkState.online;

  /// A passphrase is needed to join it the first time.
  bool get needsPassphrase => !saved && (security == WifiSecurity.psk || security == WifiSecurity.wep);

  /// 802.1X: can't be joined from the dashboard.
  bool get joinable => security != WifiSecurity.enterprise;

  WifiNetwork copyWith({bool? saved, WifiNetworkState? state, String? error}) => WifiNetwork(
    id: id,
    name: name,
    strength: strength,
    security: security,
    saved: saved ?? this.saved,
    state: state ?? this.state,
    error: error ?? this.error,
  );

  @override
  bool operator ==(Object other) =>
      other is WifiNetwork &&
      other.id == id &&
      other.name == name &&
      other.strength == strength &&
      other.security == security &&
      other.saved == saved &&
      other.state == state &&
      other.error == error;

  @override
  int get hashCode => Object.hash(id, name, strength, security, saved, state, error);
}

/// What Settings › Wi-Fi and the Nav screen see.
@immutable
class WifiView {
  const WifiView({
    required this.link,
    this.available = false,
    this.enabled = false,
    this.connectivity = Connectivity.unknown,
    this.networks = const [],
    this.detail = '',
    this.simulated = false,
    this.address = '',
    this.scanning = false,
  });

  final WifiLink link;

  /// The service reaches connman and there is a Wi-Fi device.
  final bool available;
  final bool enabled;
  final Connectivity connectivity;

  /// The connected network first, then saved ones, then by strength.
  final List<WifiNetwork> networks;

  /// Why Wi-Fi is unavailable, or why the service is unreachable.
  final String detail;
  final bool simulated;
  final String address;
  final bool scanning;

  /// On a network now: the Nav screen may use the online map (ADR-0052
  /// decision 7). connman's state covers every connection, so Ethernet on
  /// the bench counts with Wi-Fi off (seen on the Pi, 2026-11-23). Its
  /// "ready" counts: its own internet check may be off, and failing tiles
  /// catch a network without internet.
  bool get onNetwork =>
      link == WifiLink.connected &&
      available &&
      (connectivity == Connectivity.connected || connectivity == Connectivity.online);

  WifiNetwork? get current {
    for (final n in networks) {
      if (n.isConnected) return n;
    }
    return null;
  }
}

/// The outcome of joining a network.
@immutable
class WifiJoin {
  const WifiJoin({required this.connected, this.detail = ''});
  final bool connected;
  final String detail;
}

/// services/network, or a stand-in. Calls return an error to show, or null.
abstract class WifiSource {
  ValueListenable<WifiView> get view;
  void start();
  void stop();
  Future<String?> setEnabled(bool on);
  Future<String?> scan();
  Future<WifiJoin> connect(String id, {String passphrase = ''});
  Future<String?> disconnect(String id);
  Future<String?> forget(String id);
}

/// No network service: Wi-Fi can't be set, and the Nav screen stays offline.
class UnavailableWifiSource implements WifiSource {
  UnavailableWifiSource([String why = 'no network service in this build'])
    : _view = ValueNotifier(WifiView(link: WifiLink.lost, detail: why));

  final ValueNotifier<WifiView> _view;

  @override
  ValueListenable<WifiView> get view => _view;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<String?> setEnabled(bool on) async => _view.value.detail;
  @override
  Future<String?> scan() async => _view.value.detail;
  @override
  Future<WifiJoin> connect(String id, {String passphrase = ''}) async =>
      WifiJoin(connected: false, detail: _view.value.detail);
  @override
  Future<String?> disconnect(String id) async => _view.value.detail;
  @override
  Future<String?> forget(String id) async => _view.value.detail;
}

/// Made-up networks for the browser preview and tests, labelled simulated:
/// the truck's hotspot saved and online. A passphrase shorter than 8
/// characters, or "wrongpass", is refused as wrong (as services/network's
/// --simulate).
class SimulatedWifiSource implements WifiSource {
  SimulatedWifiSource({this.joinTime = const Duration(milliseconds: 800)});

  final Duration joinTime;

  final ValueNotifier<WifiView> _view = ValueNotifier(
    const WifiView(
      link: WifiLink.connected,
      available: true,
      enabled: true,
      connectivity: Connectivity.online,
      simulated: true,
      address: '192.0.2.10',
      detail: 'Simulated Wi-Fi: no real networks',
      networks: [
        WifiNetwork(
          id: 'wifi_sim_hotspot_managed_psk',
          name: 'F-250 Hotspot',
          strength: 72,
          security: WifiSecurity.psk,
          saved: true,
          state: WifiNetworkState.online,
        ),
        WifiNetwork(id: 'wifi_sim_shop_managed_psk', name: 'Shop Wi-Fi', strength: 48, security: WifiSecurity.psk),
        WifiNetwork(
          id: 'wifi_sim_stop_managed_none',
          name: 'Truck Stop Free',
          strength: 30,
          security: WifiSecurity.open,
        ),
        WifiNetwork(
          id: 'wifi_sim_corp_managed_ieee8021x',
          name: 'Corp',
          strength: 22,
          security: WifiSecurity.enterprise,
        ),
      ],
    ),
  );

  List<WifiNetwork> _all = const [];

  @override
  ValueListenable<WifiView> get view => _view;

  @override
  void start() {
    if (_all.isEmpty) _all = _view.value.networks;
  }

  @override
  void stop() {}

  void _publish({bool? enabled}) {
    final on = enabled ?? _view.value.enabled;
    final list = on ? sortNetworks(_all) : const <WifiNetwork>[];
    final connected = list.any((n) => n.isConnected);
    _view.value = WifiView(
      link: WifiLink.connected,
      available: true,
      enabled: on,
      connectivity: connected ? Connectivity.online : Connectivity.offline,
      networks: list,
      simulated: true,
      address: connected ? '192.0.2.10' : '',
      detail: _view.value.detail,
    );
  }

  void _set(String id, WifiNetwork Function(WifiNetwork) f) {
    _all = [for (final n in _all) n.id == id ? f(n) : n];
  }

  @override
  Future<String?> setEnabled(bool on) async {
    start();
    _all = [
      for (final n in _all)
        n.copyWith(
          state: on && n.saved && n.id == 'wifi_sim_hotspot_managed_psk'
              ? WifiNetworkState.online
              : WifiNetworkState.idle,
        ),
    ];
    _publish(enabled: on);
    return null;
  }

  @override
  Future<String?> scan() async {
    start();
    return null;
  }

  @override
  Future<WifiJoin> connect(String id, {String passphrase = ''}) async {
    start();
    if (!_view.value.enabled) return const WifiJoin(connected: false, detail: 'Wi-Fi is off');
    final n = _all.where((n) => n.id == id).firstOrNull;
    if (n == null) return const WifiJoin(connected: false, detail: 'That network is gone');
    if (!n.joinable) {
      return const WifiJoin(
        connected: false,
        detail: "Enterprise (802.1X) networks can't be joined from the dashboard",
      );
    }
    _all = [
      for (final m in _all)
        m.id == id
            ? m.copyWith(state: WifiNetworkState.connecting, error: '')
            : m.copyWith(state: WifiNetworkState.idle),
    ];
    _publish();
    await Future<void>.delayed(joinTime);
    if (n.needsPassphrase && (passphrase.length < 8 || passphrase == 'wrongpass')) {
      _set(id, (m) => m.copyWith(state: WifiNetworkState.failed, error: 'invalid-key'));
      _publish();
      return const WifiJoin(connected: false, detail: 'Wrong passphrase');
    }
    _set(id, (m) => m.copyWith(state: WifiNetworkState.online, saved: true, error: ''));
    _publish();
    return const WifiJoin(connected: true);
  }

  @override
  Future<String?> disconnect(String id) async {
    start();
    _set(id, (m) => m.copyWith(state: WifiNetworkState.idle));
    _publish();
    return null;
  }

  @override
  Future<String?> forget(String id) async {
    start();
    _set(id, (m) => m.copyWith(saved: false, state: WifiNetworkState.idle));
    _publish();
    return null;
  }
}

/// The connected network first, then saved ones, then by strength (as the
/// service sorts them).
List<WifiNetwork> sortNetworks(List<WifiNetwork> networks) {
  int rank(WifiNetwork n) => switch (n.state) {
    WifiNetworkState.online || WifiNetworkState.connected => 0,
    WifiNetworkState.connecting || WifiNetworkState.disconnecting => 1,
    _ when n.saved => 2,
    _ => 3,
  };
  return [...networks]..sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final s = b.strength.compareTo(a.strength);
    return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

/// connman's error names in the driver's words (as services/network's).
String wifiErrorWords(String e) => switch (e) {
  'invalid-key' => 'Wrong passphrase',
  'auth-failed' => 'The network refused the login',
  'connect-failed' => "Couldn't connect",
  'dhcp-failed' => 'No address from the network (DHCP)',
  'out-of-range' => 'Out of range',
  '' => '',
  _ => "Couldn't connect ($e)",
};
