import 'package:f250_infotainment/model/units.dart';
import 'package:f250_infotainment/nav/places_state.dart';
import 'package:f250_infotainment/ui/screens/nav_places.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const truck = LatLng(39.83, -98.53);

  test('directions on the eight compass points', () {
    expect(placeDistance(truck, const LatLng(39.93, -98.53), UnitSystem.imperial).$2, 'N');
    expect(placeDistance(truck, const LatLng(39.73, -98.53), UnitSystem.imperial).$2, 'S');
    expect(placeDistance(truck, const LatLng(39.83, -98.40), UnitSystem.imperial).$2, 'E');
    expect(placeDistance(truck, const LatLng(39.83, -98.66), UnitSystem.imperial).$2, 'W');
    expect(placeDistance(truck, const LatLng(39.90, -98.44), UnitSystem.imperial).$2, 'NE');
    expect(placeDistance(truck, const LatLng(39.76, -98.62), UnitSystem.imperial).$2, 'SW');
  });

  test('whole units from 10 up, the banner\'s format below, "here" within 50 m', () {
    // 0.1° of latitude is about 11.1 km (6.9 mi).
    expect(placeDistance(truck, const LatLng(39.93, -98.53), UnitSystem.imperial).$1, '6.9 mi');
    expect(placeDistance(truck, const LatLng(39.93, -98.53), UnitSystem.metric).$1, '11 km');
    expect(placeDistance(truck, const LatLng(40.13, -98.53), UnitSystem.imperial).$1, '21 mi');
    expect(placeDistance(truck, const LatLng(39.8303, -98.53), UnitSystem.metric), ('30 m', 'here'));
    expect(placeDistance(truck, truck, UnitSystem.imperial), ('0 ft', 'here'));
  });

  test('an unnamed place is a dropped pin, with where it is underneath', () {
    const pin = Place(id: 1, kind: PlaceKind.recent, name: '', location: LatLng(39.81, -98.5));
    expect(placeLines(pin), ('Dropped pin', '39.8100, -98.5000'));
    const near = Place(id: 2, kind: PlaceKind.recent, name: '', detail: 'Smith Center', location: LatLng(39.81, -98.5));
    expect(placeLines(near), ('Dropped pin', 'Smith Center · 39.8100, -98.5000'));
    const named = Place(id: 3, kind: PlaceKind.favourite, name: 'Feed store', detail: 'Hiawatha', location: truck);
    expect(placeLines(named), ('Feed store', 'Hiawatha'));
  });
}
