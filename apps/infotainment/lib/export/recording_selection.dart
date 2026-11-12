import 'package:flutter/foundation.dart';

import 'export_state.dart';

/// Which recordings the list shows.
enum RecordingFilter { all, front, rear, saved }

/// Whether the chosen recordings fit on a stick.
enum Fit { nothingChosen, noStick, fits, tooBig, fileTooBig }

/// The recordings chosen on the Recordings screen (ADR-0037): one at a time,
/// everything shown, or a range (two taps: the first and the last). Pure
/// state, no I/O: the screen asks the service for the list and hands it
/// here.
class RecordingSelection extends ChangeNotifier {
  List<RecordingFile> _all = const [];
  final Set<String> _chosen = {};
  RecordingFilter _filter = RecordingFilter.all;
  bool _rangeMode = false;
  String? _anchor;

  RecordingFilter get filter => _filter;

  /// The next two taps choose everything between them.
  bool get rangeMode => _rangeMode;

  /// The first tap of a range, waiting for the second.
  String? get anchor => _anchor;

  List<RecordingFile> get all => _all;

  /// The list after the filter, oldest first.
  List<RecordingFile> get shown => [
    for (final r in _all)
      if (_matches(r)) r,
  ];

  /// Chosen, in list order. A chosen recording hidden by the filter stays
  /// chosen.
  List<RecordingFile> get chosen => [
    for (final r in _all)
      if (_chosen.contains(r.key)) r,
  ];

  int get chosenBytes => chosen.fold(0, (a, r) => a + r.bytes);

  bool isChosen(RecordingFile r) => _chosen.contains(r.key);

  bool _matches(RecordingFile r) => switch (_filter) {
    RecordingFilter.all => true,
    RecordingFilter.front => r.camera == 'front',
    RecordingFilter.rear => r.camera == 'rear',
    RecordingFilter.saved => r.protected,
  };

  /// A new list from the service. Choices it still has are kept; ones gone
  /// (deleted by retention, moved by Save clip) or now being written are
  /// dropped.
  void setRecordings(List<RecordingFile> list) {
    _all = List.unmodifiable(list);
    final keep = {
      for (final r in list)
        if (!r.beingWritten) r.key,
    };
    _chosen.removeWhere((k) => !keep.contains(k));
    if (_anchor != null && !keep.contains(_anchor)) _anchor = null;
    notifyListeners();
  }

  set filter(RecordingFilter f) {
    if (f == _filter) return;
    _filter = f;
    _anchor = null;
    notifyListeners();
  }

  /// Starts (or stops) choosing a range.
  void toggleRangeMode() {
    _rangeMode = !_rangeMode;
    _anchor = null;
    notifyListeners();
  }

  /// A tap on a recording. Outside range mode it flips that one. In range
  /// mode the first tap marks the start (and chooses it), the second chooses
  /// everything shown between the two, either way round, and range mode
  /// ends. A recording being written can't be chosen.
  void tap(RecordingFile r) {
    if (r.beingWritten) return;
    if (!_rangeMode) {
      if (!_chosen.remove(r.key)) _chosen.add(r.key);
      notifyListeners();
      return;
    }
    final a = _anchor;
    if (a == null) {
      _anchor = r.key;
      _chosen.add(r.key);
      notifyListeners();
      return;
    }
    final list = shown;
    var i = list.indexWhere((x) => x.key == a);
    var j = list.indexWhere((x) => x.key == r.key);
    if (i < 0) i = j;
    if (i > j) (i, j) = (j, i);
    for (final x in list.sublist(i, j + 1)) {
      if (!x.beingWritten) _chosen.add(x.key);
    }
    _anchor = null;
    _rangeMode = false;
    notifyListeners();
  }

  /// Chooses every recording shown that can be copied.
  void chooseAllShown() {
    for (final r in shown) {
      if (!r.beingWritten) _chosen.add(r.key);
    }
    notifyListeners();
  }

  void clear() {
    _chosen.clear();
    _anchor = null;
    notifyListeners();
  }

  /// Whether the chosen recordings fit on [stick] by its last free space
  /// (the service checks again when it copies, counting files already
  /// there).
  Fit fitOn(UsbStick? stick) {
    final c = chosen;
    if (c.isEmpty) return Fit.nothingChosen;
    if (stick == null || stick.role != StickRole.export) return Fit.noStick;
    if (stick.maxFileBytes > 0 && c.any((r) => r.bytes > stick.maxFileBytes)) return Fit.fileTooBig;
    return chosenBytes <= stick.freeBytes ? Fit.fits : Fit.tooBig;
  }
}

/// `1.2 GB`, `340 MB`: decimal, as sticks are sold.
String formatSize(int bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1e3).ceil()} kB';
}
