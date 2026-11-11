import 'dart:convert';

/// What the map import (ADR-0033, `/opt/f250/libexec/map-import`) is doing,
/// from its status file.
enum MapUpdateState { checking, copying, updated, failed }

class MapUpdateStatus {
  const MapUpdateStatus({
    required this.state,
    required this.percent,
    required this.message,
    required this.id,
    this.at,
  });

  final MapUpdateState state;
  final int percent;
  final String message;

  /// One import; a new "updated" id means a new map on the drive.
  final String id;
  final DateTime? at;

  /// How long a finished import (updated or failed) stays on screen.
  static const shownFor = Duration(minutes: 10);

  bool get inProgress => state == MapUpdateState.copying || state == MapUpdateState.checking;

  /// Shown: an import in progress, or one that finished in the last
  /// [shownFor].
  bool shownAt(DateTime now) =>
      inProgress || (at != null && now.difference(at!) < shownFor);

  /// What the screen says about it.
  String get text => switch (state) {
    MapUpdateState.copying => 'Copying the map from USB: $percent%. Leave the stick in.',
    _ => message,
  };

  /// The status file's JSON, or null if it isn't one.
  static MapUpdateStatus? parse(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, dynamic>) return null;
      final state = MapUpdateState.values.where((s) => s.name == j['state']).firstOrNull;
      final id = j['id'];
      if (state == null || id is! String) return null;
      final percent = j['percent'];
      final at = j['at'];
      return MapUpdateStatus(
        state: state,
        percent: percent is int ? percent.clamp(0, 100) : 0,
        message: j['message'] is String ? j['message'] as String : '',
        id: id,
        at: at is String ? DateTime.tryParse(at) : null,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MapUpdateStatus &&
      other.state == state &&
      other.percent == percent &&
      other.message == message &&
      other.id == id &&
      other.at == at;

  @override
  int get hashCode => Object.hash(state, percent, message, id, at);
}
