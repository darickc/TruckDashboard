import 'dart:convert';

/// What the map import (ADR-0033, `/opt/f250/libexec/map-import`) is doing,
/// from its status file. A stick carries the map, routing data (ADR-0033
/// amendment, ADR-0035), or both. `current`: what the stick carries is
/// already installed, so nothing was copied (a stick left in the truck).
enum MapUpdateState { checking, copying, updated, current, failed }

class MapUpdateStatus {
  const MapUpdateStatus({
    required this.state,
    required this.percent,
    required this.message,
    required this.id,
    this.item = 'map',
    this.changed,
    this.at,
  });

  final MapUpdateState state;
  final int percent;
  final String message;

  /// One import; a new "updated" id means new files on the drive.
  final String id;

  /// What is being checked or copied: `map` or `routing`.
  final String item;

  /// What the import replaced (`map`, `routing`), also when it then failed
  /// on the routing data. Null from an import that doesn't say, which only
  /// ever imported maps.
  final List<String>? changed;

  /// Whether this import put a new map on the drive, so the map is reopened.
  bool get mapChanged => switch (state) {
    MapUpdateState.updated => changed == null || changed!.contains('map'),
    MapUpdateState.failed => changed?.contains('map') ?? false,
    _ => false,
  };
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
    MapUpdateState.copying => item == 'routing'
        ? 'Copying routing data from USB: $percent%. Leave the stick in.'
        : 'Copying the map from USB: $percent%. Leave the stick in.',
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
      final item = j['item'];
      final changed = j['changed'];
      return MapUpdateStatus(
        state: state,
        percent: percent is int ? percent.clamp(0, 100) : 0,
        message: j['message'] is String ? j['message'] as String : '',
        id: id,
        item: item == 'routing' ? 'routing' : 'map',
        changed: changed is List ? changed.whereType<String>().toList() : null,
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
      other.item == item &&
      _sameList(other.changed, changed) &&
      other.at == at;

  @override
  int get hashCode => Object.hash(state, percent, message, id, item, Object.hashAll(changed ?? const []), at);

  static bool _sameList(List<String>? a, List<String>? b) =>
      a == null ? b == null : b != null && a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);
}
