import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Offline address and place search as services/navigation answers it
/// (f250.nav.v1 SearchService, Phase 6.5.3, ADR-0038). The dashboard never
/// reads the index itself (CLAUDE.md rule 5).
///
/// What a result is. OpenStreetMap's house numbers are sparse outside towns,
/// so a search often finds only the street or the town, and the screen says
/// so.
enum SearchMatch { address, street, locality, place }

enum RankedFrom { none, current, lastKnown }

@immutable
class SearchResult {
  const SearchResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.location,
    this.distanceM,
    this.houseNumberMissing = false,
    this.unmatchedWords = const [],
  });

  final SearchMatch kind;

  /// "120 North Main Street", "Casey's General Store", "Fairview".
  final String title;

  /// Its town ("near Fairview"), category or kind of place.
  final String subtitle;

  /// Where a route to it ends.
  final LatLng location;

  /// Straight line from where the search was ranked from; null without a
  /// position.
  final double? distanceM;

  /// The query had a house number this result doesn't have.
  final bool houseNumberMissing;

  /// Query words this result doesn't match.
  final List<String> unmatchedWords;
}

@immutable
class SearchAnswer {
  const SearchAnswer({
    required this.query,
    required this.available,
    this.detail = '',
    this.results = const [],
    this.regions = const [],
    this.dataDate = '',
    this.rankedFrom = RankedFrom.none,
    this.positionAgeS = 0,
  });

  /// The query this answers.
  final String query;

  /// Search data is installed and the service answered.
  final bool available;

  /// Why not, when not available.
  final String detail;
  final List<SearchResult> results;

  /// What the search data covers ("Kansas") and its OpenStreetMap date.
  final List<String> regions;
  final String dataDate;
  final RankedFrom rankedFrom;
  final double positionAgeS;
}

abstract class SearchSource {
  void start();
  void stop();

  /// Never throws: a failure is an answer that isn't [SearchAnswer.available].
  Future<SearchAnswer> search(String query, {int limit = 8});
}

/// No navigation service (the in-app simulator, the browser preview): search
/// is unavailable, and says why. Never made-up places.
class UnavailableSearchSource implements SearchSource {
  const UnavailableSearchSource([this.why = 'needs services/navigation (make sim)']);

  final String why;

  @override
  void start() {}
  @override
  void stop() {}
  @override
  Future<SearchAnswer> search(String query, {int limit = 8}) async =>
      SearchAnswer(query: query, available: false, detail: why);
}

/// The house number at the start of a query, as the service reads it
/// ("120", "12b"; not "3rd"), or null.
String? queryHouseNumber(String query) {
  final m = RegExp(r'^\s*(\d+[a-zA-Z]{0,2})(?=[\s,]|$)').firstMatch(query);
  final n = m?.group(1);
  if (n == null) return null;
  final suffix = n.replaceAll(RegExp(r'\d'), '').toLowerCase();
  if (const {'st', 'nd', 'rd', 'th'}.contains(suffix)) return null;
  return n;
}

/// What the screen says a result is, and what it isn't: the honest line
/// under each result. Null for a full match.
String? matchNote(SearchResult r, String query) {
  final missing = r.unmatchedWords.join(' ');
  switch (r.kind) {
    case SearchMatch.address:
      return null;
    case SearchMatch.street:
      if (r.houseNumberMissing) {
        final n = queryHouseNumber(query);
        return 'Street only: no house number${n == null ? '' : ' $n'} in the map data';
      }
      return missing.isEmpty ? null : 'Street only: “$missing” not found';
    case SearchMatch.locality:
      if (missing.isNotEmpty) return 'Town only: “$missing” not found';
      return r.houseNumberMissing ? 'Town only' : null;
    case SearchMatch.place:
      if (r.houseNumberMissing) return 'Place name only: no house number in the map data';
      return missing.isEmpty ? null : 'Not matched: “$missing”';
  }
}

/// The kind of result in a word, for its chip.
String matchLabel(SearchMatch m) => switch (m) {
  SearchMatch.address => 'ADDRESS',
  SearchMatch.street => 'STREET',
  SearchMatch.locality => 'TOWN',
  SearchMatch.place => 'PLACE',
};
