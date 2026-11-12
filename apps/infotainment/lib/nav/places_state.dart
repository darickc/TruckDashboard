import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Saved places as services/navigation keeps them (f250.nav.v1
/// PlacesService, Phase 6.5.2, ADR-0040): Home, favourites with a name, and
/// the recent destinations, newest first. The dashboard never reads the file
/// itself (CLAUDE.md rule 5); a route to one is RouteSource.setDestination.
enum PlaceKind { home, favourite, recent }

enum PlacesLink { connecting, connected, lost }

@immutable
class Place {
  const Place({
    required this.id,
    required this.kind,
    required this.name,
    required this.location,
    this.detail = '',
  });

  final int id;
  final PlaceKind kind;

  /// "Home", "Feed store"; a recent destination may have none.
  final String name;

  /// A second line: its town or category.
  final String detail;
  final LatLng location;

  /// The name, or the coordinates for an unnamed point.
  String get title =>
      name.isNotEmpty ? name : '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
}

@immutable
class PlacesView {
  const PlacesView({
    required this.link,
    this.home,
    this.favourites = const [],
    this.recents = const [],
    this.writable = false,
    this.location = '',
    this.problem = '',
    this.detail = '',
    this.maxFavourites = 50,
    this.maxNameChars = 40,
  });

  final PlacesLink link;
  final Place? home;
  final List<Place> favourites;

  /// Newest first.
  final List<Place> recents;

  /// The service can change them.
  final bool writable;

  /// Where they are kept: "the data drive", "the SD card: …".
  final String location;

  /// Something wrong with the file the service found or a write that failed.
  final String problem;

  /// Why the link is down.
  final String detail;
  final int maxFavourites;
  final int maxNameChars;

  bool get isEmpty => home == null && favourites.isEmpty && recents.isEmpty;
}

abstract class PlacesSource {
  ValueListenable<PlacesView> get state;
  void start();
  void stop();

  /// Asks the service again: the recent destinations change with every route.
  Future<void> refresh();

  /// Each returns null when done, or why not (never throws).
  Future<String?> save(PlaceKind kind, String name, LatLng at, {String detail = ''});
  Future<String?> rename(int id, String name);
  Future<String?> delete(int id);
}

/// No navigation service (the in-app simulator, the browser preview): no
/// saved places, and says why. Never made-up places.
class UnavailablePlacesSource implements PlacesSource {
  UnavailablePlacesSource([this.why = 'needs services/navigation (make sim)']);

  final String why;

  late final _state = ValueNotifier(PlacesView(link: PlacesLink.lost, detail: why));

  @override
  ValueListenable<PlacesView> get state => _state;
  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<void> refresh() async {}
  @override
  Future<String?> save(PlaceKind kind, String name, LatLng at, {String detail = ''}) async => why;
  @override
  Future<String?> rename(int id, String name) async => why;
  @override
  Future<String?> delete(int id) async => why;
}
