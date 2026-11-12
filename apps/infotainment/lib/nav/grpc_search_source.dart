import 'dart:io';

import 'package:grpc/grpc.dart';
import 'package:latlong2/latlong.dart';

import '../data/gateway_connection.dart';
import '../gen/f250/nav/v1/search.pbgrpc.dart' as pb;
import 'search_state.dart';

SearchSource createGrpcSearchSource(GatewayEndpoint endpoint) => GrpcSearchSource(endpoint: endpoint);

/// services/navigation's `SearchService` over gRPC. One call per search; a
/// failed call is an unavailable answer, never an exception.
class GrpcSearchSource implements SearchSource {
  GrpcSearchSource({required this.endpoint, this.timeout = const Duration(seconds: 5)});

  final GatewayEndpoint endpoint;

  /// A search slower than this is reported as failed.
  final Duration timeout;

  ClientChannel? _channel;
  pb.SearchServiceClient? _client;

  @override
  void start() {
    if (_channel != null) return;
    final (host, port) = switch (endpoint) {
      UnixEndpoint(:final path) => (InternetAddress(path, type: InternetAddressType.unix), 0),
      TcpEndpoint(:final host, :final port) => (host as Object, port),
    };
    _channel = ClientChannel(
      host,
      port: port,
      options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
    );
    _client = pb.SearchServiceClient(_channel!);
  }

  @override
  void stop() {
    _channel?.shutdown();
    _channel = null;
    _client = null;
  }

  @override
  Future<SearchAnswer> search(String query, {int limit = 8}) async {
    final client = _client;
    if (client == null) {
      return SearchAnswer(query: query, available: false, detail: 'not connected to the navigation service');
    }
    try {
      final r = await client.search(
        pb.SearchRequest(query: query, limit: limit),
        options: CallOptions(timeout: timeout),
      );
      return searchAnswerFromPb(r, query);
    } catch (e) {
      final why = e is GrpcError ? (e.message ?? e.codeName) : '$e';
      return SearchAnswer(query: query, available: false, detail: 'navigation service unavailable: $why');
    }
  }
}

/// navigation's answer as the dashboard's model. An unknown match kind (a
/// newer service) reads as a place name, the least it can claim.
SearchAnswer searchAnswerFromPb(pb.SearchResponse r, String asked) => SearchAnswer(
  query: r.query.isEmpty ? asked : r.query,
  available: r.available,
  detail: r.detail,
  results: [
    for (final h in r.results)
      if (h.hasLocation())
        SearchResult(
          kind: switch (h.kind) {
            pb.MatchKind.MATCH_KIND_ADDRESS => SearchMatch.address,
            pb.MatchKind.MATCH_KIND_STREET => SearchMatch.street,
            pb.MatchKind.MATCH_KIND_LOCALITY => SearchMatch.locality,
            _ => SearchMatch.place,
          },
          title: h.title,
          subtitle: h.subtitle,
          location: LatLng(h.location.latitudeDeg, h.location.longitudeDeg),
          distanceM: h.hasDistanceM() ? h.distanceM : null,
          houseNumberMissing: h.houseNumberMissing,
          unmatchedWords: List.unmodifiable(h.unmatchedWords),
        ),
  ],
  regions: List.unmodifiable(r.regions),
  dataDate: r.dataDate,
  rankedFrom: switch (r.rankedFrom) {
    pb.RankedFrom.RANKED_FROM_CURRENT => RankedFrom.current,
    pb.RankedFrom.RANKED_FROM_LAST_KNOWN => RankedFrom.lastKnown,
    _ => RankedFrom.none,
  },
  positionAgeS: r.positionAgeS,
);
