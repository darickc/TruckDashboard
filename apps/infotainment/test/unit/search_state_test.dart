import 'package:f250_infotainment/gen/f250/nav/v1/route.pb.dart' as route_pb;
import 'package:f250_infotainment/gen/f250/nav/v1/search.pb.dart' as pb;
import 'package:f250_infotainment/nav/grpc_search_source.dart';
import 'package:f250_infotainment/nav/search_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

SearchResult result(SearchMatch kind, {bool numberMissing = false, List<String> unmatched = const []}) => SearchResult(
  kind: kind,
  title: 'Main Street',
  subtitle: 'near Fairview',
  location: const LatLng(26, -90),
  houseNumberMissing: numberMissing,
  unmatchedWords: unmatched,
);

void main() {
  test('house numbers at the start of a query', () {
    expect(queryHouseNumber('120 n main st'), '120');
    expect(queryHouseNumber('  12b elm'), '12b');
    expect(queryHouseNumber('3rd street'), isNull);
    expect(queryHouseNumber('1st ave'), isNull);
    expect(queryHouseNumber('main 120'), isNull);
    expect(queryHouseNumber('120'), '120');
  });

  test('each result says what it is and is not', () {
    expect(matchNote(result(SearchMatch.address), '120 main st'), isNull);
    expect(
      matchNote(result(SearchMatch.street, numberMissing: true), '125 main st'),
      'Street only: no house number 125 in the map data',
    );
    expect(matchNote(result(SearchMatch.street), 'main st'), isNull);
    expect(
      matchNote(result(SearchMatch.street, unmatched: ['smallville']), 'main st smallville'),
      'Street only: “smallville” not found',
    );
    expect(
      matchNote(result(SearchMatch.locality, unmatched: ['elm', 'avenue']), 'elm avenue fairview'),
      'Town only: “elm avenue” not found',
    );
    expect(matchNote(result(SearchMatch.locality), 'fairview'), isNull);
    expect(
      matchNote(result(SearchMatch.place, numberMissing: true), '9 caseys'),
      'Place name only: no house number in the map data',
    );
    expect(matchLabel(SearchMatch.locality), 'TOWN');
  });

  test("navigation's answer becomes the model", () {
    final r = pb.SearchResponse(
      available: true,
      query: '125 main st',
      regions: ['Kansas'],
      dataDate: '2026-11-11',
      rankedFrom: pb.RankedFrom.RANKED_FROM_LAST_KNOWN,
      positionAgeS: 90,
      results: [
        pb.SearchResult(
          kind: pb.MatchKind.MATCH_KIND_STREET,
          title: 'Main Street',
          subtitle: 'near Fairview',
          location: route_pb.LatLon(latitudeDeg: 26.001, longitudeDeg: -90),
          distanceM: 120,
          houseNumberMissing: true,
        ),
        // No location: can't be routed to, so not shown.
        pb.SearchResult(kind: pb.MatchKind.MATCH_KIND_PLACE, title: 'Nowhere'),
        // A kind this dashboard doesn't know: the least it can claim.
        pb.SearchResult(
          kind: pb.MatchKind.valueOf(99) ?? pb.MatchKind.MATCH_KIND_UNSPECIFIED,
          title: 'Odd',
          location: route_pb.LatLon(latitudeDeg: 26, longitudeDeg: -90),
          unmatchedWords: ['x'],
        ),
      ],
    );
    final a = searchAnswerFromPb(r, 'ignored');
    expect(a.query, '125 main st');
    expect(a.available, isTrue);
    expect(a.regions, ['Kansas']);
    expect(a.dataDate, '2026-11-11');
    expect(a.rankedFrom, RankedFrom.lastKnown);
    expect(a.positionAgeS, 90);
    expect(a.results, hasLength(2));
    expect(a.results[0].kind, SearchMatch.street);
    expect(a.results[0].location, const LatLng(26.001, -90));
    expect(a.results[0].distanceM, 120);
    expect(a.results[0].houseNumberMissing, isTrue);
    expect(a.results[1].kind, SearchMatch.place);
    expect(a.results[1].distanceM, isNull);
    expect(a.results[1].unmatchedWords, ['x']);

    final down = searchAnswerFromPb(pb.SearchResponse(available: false, detail: 'no search data at /x'), 'q');
    expect(down.query, 'q');
    expect(down.available, isFalse);
    expect(down.detail, 'no search data at /x');
  });

  test('without the service, search says why', () async {
    final a = await const UnavailableSearchSource().search('main');
    expect(a.available, isFalse);
    expect(a.detail, contains('services/navigation'));
  });
}
