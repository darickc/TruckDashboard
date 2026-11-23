import 'package:f250_infotainment/gen/f250/network/v1/wifi.pb.dart' as pb;
import 'package:f250_infotainment/gen/f250/network/v1/wifi.pbenum.dart' as pbe;
import 'package:f250_infotainment/nav/online_map.dart';
import 'package:f250_infotainment/network/grpc_wifi_source.dart';
import 'package:f250_infotainment/network/wifi_state.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wi-Fi's model and the online map's choice (ADR-0052).
void main() {
  group('Wi-Fi', () {
    test('the service status becomes the model, unknown values as unknown', () {
      final v = wifiViewFromPb(pb.WifiStatus(
        available: true,
        enabled: true,
        connectivity: pbe.Connectivity.CONNECTIVITY_CONNECTED,
        address: '172.20.10.4',
        networks: [
          pb.WifiNetwork(
            id: 'wifi_a_managed_psk',
            name: 'Hotspot',
            strength: 70,
            security: pbe.Security.SECURITY_PSK,
            saved: true,
            state: pbe.NetworkState.NETWORK_STATE_CONNECTED,
          ),
          pb.WifiNetwork(id: 'wifi_b', name: 'Odd', state: pbe.NetworkState.NETWORK_STATE_UNSPECIFIED),
        ],
      ));
      expect(v.link, WifiLink.connected);
      expect(v.connectivity, Connectivity.connected);
      expect(v.current!.name, 'Hotspot');
      expect(v.networks[0].security, WifiSecurity.psk);
      expect(v.networks[1].state, WifiNetworkState.unknown);
      expect(v.networks[1].security, WifiSecurity.unknown);
      expect(v.onNetwork, isTrue, reason: "connman's ready counts");
    });

    test('on a network only when connected, enabled, available and reachable', () {
      const base = WifiView(link: WifiLink.connected, available: true, enabled: true, connectivity: Connectivity.online);
      expect(base.onNetwork, isTrue);
      for (final v in [
        const WifiView(link: WifiLink.lost, available: true, enabled: true, connectivity: Connectivity.online),
        const WifiView(link: WifiLink.connected, available: false, enabled: true, connectivity: Connectivity.online),
        const WifiView(link: WifiLink.connected, available: true, enabled: false, connectivity: Connectivity.online),
        const WifiView(link: WifiLink.connected, available: true, enabled: true, connectivity: Connectivity.offline),
        const WifiView(link: WifiLink.connected, available: true, enabled: true),
      ]) {
        expect(v.onNetwork, isFalse);
      }
    });

    test('a secured network not saved needs a passphrase; enterprise is not joinable', () {
      expect(const WifiNetwork(id: 'a', name: 'a', security: WifiSecurity.psk).needsPassphrase, isTrue);
      expect(const WifiNetwork(id: 'a', name: 'a', security: WifiSecurity.psk, saved: true).needsPassphrase, isFalse);
      expect(const WifiNetwork(id: 'a', name: 'a', security: WifiSecurity.open).needsPassphrase, isFalse);
      expect(const WifiNetwork(id: 'a', name: 'a', security: WifiSecurity.enterprise).joinable, isFalse);
    });

    test('connected first, then saved, then strongest', () {
      final sorted = sortNetworks(const [
        WifiNetwork(id: '1', name: 'strong', strength: 90),
        WifiNetwork(id: '2', name: 'saved', strength: 10, saved: true),
        WifiNetwork(id: '3', name: 'mine', strength: 40, saved: true, state: WifiNetworkState.online),
      ]);
      expect(sorted.map((n) => n.name), ['mine', 'saved', 'strong']);
      expect(wifiErrorWords('invalid-key'), 'Wrong passphrase');
      expect(wifiErrorWords('weird'), "Couldn't connect (weird)");
    });

    test('the simulation joins with a right passphrase and refuses a wrong one', () async {
      final w = SimulatedWifiSource(joinTime: Duration.zero)..start();
      expect(w.view.value.onNetwork, isTrue);
      final wrong = await w.connect('wifi_sim_shop_managed_psk', passphrase: 'short');
      expect(wrong.connected, isFalse);
      expect(wrong.detail, 'Wrong passphrase');
      final right = await w.connect('wifi_sim_shop_managed_psk', passphrase: 'long enough');
      expect(right.connected, isTrue);
      expect(w.view.value.current!.name, 'Shop Wi-Fi');
      await w.setEnabled(false);
      expect(w.view.value.onNetwork, isFalse);
      expect(w.view.value.networks, isEmpty);
    });
  });

  group('online map', () {
    test('online only on a network with a token', () {
      final c = OnlineMapChooser();
      expect(c.useOnline(onNetwork: true, configured: true), isTrue);
      expect(c.useOnline(onNetwork: false, configured: true), isFalse);
      expect(c.useOnline(onNetwork: true, configured: false), isFalse);
    });

    test('three failures within the window set it aside for the backoff, then it comes back', () {
      var now = DateTime(2026, 11, 23, 12);
      final c = OnlineMapChooser(now: () => now);
      var changes = 0;
      c.addListener(() => changes++);
      c.report(ok: false, why: 'Mapbox unreachable');
      now = now.add(const Duration(seconds: 10));
      c.report(ok: false, why: 'Mapbox unreachable');
      expect(c.backingOff, isFalse);
      now = now.add(const Duration(seconds: 10));
      c.report(ok: false, why: 'Mapbox unreachable');
      expect(c.backingOff, isTrue);
      expect(changes, 1);
      expect(c.backedOffBecause, 'Mapbox unreachable');
      expect(c.useOnline(onNetwork: true, configured: true), isFalse);
      now = now.add(const Duration(seconds: 61));
      expect(c.backingOff, isFalse);
      expect(c.backedOffBecause, '');
      expect(c.useOnline(onNetwork: true, configured: true), isTrue);
    });

    test('failures spread out, or broken by a tile that loads, do not set it aside', () {
      var now = DateTime(2026, 11, 23, 12);
      final c = OnlineMapChooser(now: () => now);
      for (var i = 0; i < 5; i++) {
        c.report(ok: false);
        now = now.add(const Duration(seconds: 20));
      }
      expect(c.backingOff, isFalse, reason: 'never three within 30 s');
      now = now.add(const Duration(minutes: 1));
      c.report(ok: false);
      c.report(ok: false);
      c.report(ok: true);
      c.report(ok: false);
      expect(c.backingOff, isFalse, reason: 'a tile that loads clears the count');
    });

    test("512-pixel tiles are asked for one zoom behind the layer's", () {
      final src = UnavailableOnlineMapSource();
      final p = OnlineTileProvider(src, night: true);
      final layer = TileLayer(tileProvider: p, tileDimension: 512, zoomOffset: -1);
      final img = p.getImage(const TileCoordinates(3, 5, 15), layer) as OnlineTileImage;
      expect((img.z, img.x, img.y, img.night), (14, 3, 5, true));
      expect(img, OnlineTileImage(src, z: 14, x: 3, y: 5, night: true));
    });
  });
}
