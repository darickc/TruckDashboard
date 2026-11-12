import 'package:f250_infotainment/gen/f250/nav/v1/places.pb.dart' as pb;
import 'package:f250_infotainment/gen/f250/nav/v1/route.pb.dart' as route_pb;
import 'package:f250_infotainment/nav/grpc_places_source.dart';
import 'package:f250_infotainment/nav/places_state.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

pb.Place place(int id, pb.PlaceKind kind, String name, {bool located = true}) => pb.Place(
  id: Int64(id),
  kind: kind,
  name: name,
  detail: 'Fairview',
  location: located ? route_pb.LatLon(latitudeDeg: 39.84, longitudeDeg: -98.54) : null,
);

void main() {
  test('placesFromPb: every kind, the storage, the limits', () {
    final v = placesFromPb(
      pb.Places(
        home: place(1, pb.PlaceKind.PLACE_KIND_HOME, 'Home'),
        favourites: [
          place(2, pb.PlaceKind.PLACE_KIND_FAVOURITE, 'Feed store'),
          place(3, pb.PlaceKind.PLACE_KIND_FAVOURITE, 'No location', located: false),
        ],
        recents: [place(4, pb.PlaceKind.PLACE_KIND_RECENT, ''), place(5, pb.PlaceKind.valueOf(99) ?? pb.PlaceKind.PLACE_KIND_UNSPECIFIED, 'x')],
        storage: pb.PlacesStorage(writable: true, location: 'the data drive', problem: '1 saved place was left out'),
        maxFavourites: 50,
        maxRecents: 10,
        maxNameChars: 40,
      ),
    );
    expect(v.link, PlacesLink.connected);
    expect(v.home!.kind, PlaceKind.home);
    expect(v.home!.location, const LatLng(39.84, -98.54));
    expect(v.favourites.map((f) => f.name), ['Feed store'], reason: 'a place without a location is left out');
    expect(v.recents.first.kind, PlaceKind.recent);
    expect(v.recents.first.title, '39.8400, -98.5400', reason: 'an unnamed point shows where it is');
    expect(v.recents.last.kind, PlaceKind.recent, reason: 'an unknown kind reads as recent');
    expect((v.writable, v.location, v.problem), (true, 'the data drive', '1 saved place was left out'));
    expect((v.maxFavourites, v.maxNameChars), (50, 40));
  });

  test('UnavailablePlacesSource says why and changes nothing', () async {
    final s = UnavailablePlacesSource('needs services/navigation (make sim)');
    expect(s.state.value.link, PlacesLink.lost);
    expect(s.state.value.isEmpty, isTrue);
    expect(await s.save(PlaceKind.home, 'Home', const LatLng(39, -98)), 'needs services/navigation (make sim)');
    expect(await s.delete(1), isNotNull);
  });
}
