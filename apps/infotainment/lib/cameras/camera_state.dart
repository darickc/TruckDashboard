import 'package:flutter/foundation.dart';

/// What camera-manager shows, as the dashboard needs it (f250.camera.v1,
/// ADR-0026). The dashboard never touches a camera: camera-manager runs the
/// pipelines and its own window; this is only what it reports.
enum CameraId { front, left, right, rear }

/// Why the camera is up.
enum CameraReason { reverse, cameraSwitch }

enum FeedState { starting, live, unavailable }

/// What camera-manager knows about reverse. `off`: automatic reverse is
/// switched off (it is until the reverse decoder is verified, ADR-0024).
enum ReverseStatus { off, unknown, notEngaged, engaged }

/// A move of the 5-way camera switch, or the dashboard's camera buttons.
enum SwitchMove { left, right, back, forward, press }

@immutable
class CameraView {
  const CameraView({
    this.camera,
    this.reason,
    this.feed,
    this.feedDetail = '',
    this.reverse = ReverseStatus.off,
    this.blockedBySpeed = false,
  });

  /// Null: no camera; the dashboard shows its screens.
  final CameraId? camera;
  final CameraReason? reason;

  /// Null when no camera is up.
  final FeedState? feed;

  /// Why the feed is unavailable, from camera-manager.
  final String feedDetail;
  final ReverseStatus reverse;

  /// The switch's choice is hidden by the optional speed limit.
  final bool blockedBySpeed;

  static const none = CameraView();

  @override
  bool operator ==(Object other) =>
      other is CameraView &&
      other.camera == camera &&
      other.reason == reason &&
      other.feed == feed &&
      other.feedDetail == feedDetail &&
      other.reverse == reverse &&
      other.blockedBySpeed == blockedBySpeed;

  @override
  int get hashCode => Object.hash(camera, reason, feed, feedDetail, reverse, blockedBySpeed);

  @override
  String toString() => 'CameraView($camera, $reason, $feed, "$feedDetail", $reverse, '
      'blocked: $blockedBySpeed)';
}

/// One recorded camera's state (f250.camera.v1 RecordingState, ADR-0027
/// decision 9).
enum RecordingState { starting, recording, notRecording }

@immutable
class CameraRecording {
  const CameraRecording({
    required this.camera,
    required this.state,
    this.detail = '',
    this.segment = '',
  });

  /// Null: a camera this dashboard doesn't know (a newer camera-manager).
  final CameraId? camera;
  final RecordingState state;

  /// Why it isn't recording, or what it is waiting for.
  final String detail;

  /// The segment being written (file name), while recording.
  final String segment;

  @override
  bool operator ==(Object other) =>
      other is CameraRecording &&
      other.camera == camera &&
      other.state == state &&
      other.detail == detail &&
      other.segment == segment;

  @override
  int get hashCode => Object.hash(camera, state, detail, segment);

  @override
  String toString() => 'CameraRecording($camera, $state, "$detail", "$segment")';
}

/// Front and rear recording, as camera-manager reports it (ADR-0027). The
/// dashboard shows REC only from this; it never assumes a recording.
@immutable
class RecordingStatus {
  const RecordingStatus({
    this.cameras = const [],
    this.driveMounted = false,
    this.driveFreeBytes = 0,
    this.recordedBytes = 0,
    this.protectedBytes = 0,
    this.protectedMaxBytes = 0,
    this.clipSegmentsPending = 0,
    this.clockTrusted = false,
    this.problem = '',
  });

  /// The cameras set to record (RECORD_CAMERAS). Empty: recording is off.
  final List<CameraRecording> cameras;
  final bool driveMounted;

  /// Meaningful only while [driveMounted].
  final int driveFreeBytes;
  final int recordedBytes;
  final int protectedBytes;
  final int protectedMaxBytes;
  final int clipSegmentsPending;
  final bool clockTrusted;

  /// Not one camera's: the drive is full, or the minutes before an unclean
  /// stop didn't all fit in the saved clips. Empty when nothing is wrong.
  final String problem;

  static const off = RecordingStatus();

  /// No camera is set to record: no REC and no advisory.
  bool get isOff => cameras.isEmpty;

  Iterable<CameraRecording> inState(RecordingState s) => cameras.where((c) => c.state == s);

  /// Whether this camera is recording now.
  bool records(CameraId camera) =>
      cameras.any((c) => c.camera == camera && c.state == RecordingState.recording);

  @override
  bool operator ==(Object other) =>
      other is RecordingStatus &&
      listEquals(other.cameras, cameras) &&
      other.driveMounted == driveMounted &&
      other.driveFreeBytes == driveFreeBytes &&
      other.recordedBytes == recordedBytes &&
      other.protectedBytes == protectedBytes &&
      other.protectedMaxBytes == protectedMaxBytes &&
      other.clipSegmentsPending == clipSegmentsPending &&
      other.clockTrusted == clockTrusted &&
      other.problem == problem;

  @override
  int get hashCode => Object.hash(Object.hashAll(cameras), driveMounted, driveFreeBytes,
      recordedBytes, protectedBytes, protectedMaxBytes, clipSegmentsPending, clockTrusted, problem);

  @override
  String toString() => 'RecordingStatus($cameras, drive: $driveMounted, free: $driveFreeBytes, '
      'protected: $protectedBytes/$protectedMaxBytes, pending: $clipSegmentsPending, '
      'clock: $clockTrusted, "$problem")';
}

/// What "Save clip" did (f250.camera.v1 SaveClipResponse).
@immutable
class SaveClipResult {
  const SaveClipResult({
    required this.saved,
    this.detail = '',
    this.segmentsProtected = 0,
    this.segmentsToCome = 0,
  });

  /// False: nothing was protected; [detail] says why.
  final bool saved;
  final String detail;
  final int segmentsProtected;
  final int segmentsToCome;

  @override
  String toString() => 'SaveClipResult($saved, "$detail", $segmentsProtected, $segmentsToCome)';
}

/// The connection to camera-manager.
enum CameraLink { connecting, up, down }

@immutable
class CameraStatus {
  const CameraStatus(
      {required this.link,
      this.view,
      RecordingStatus? recording,
      this.detail,
      this.simulated = false})
      : _recording = recording;

  final CameraLink link;

  /// camera-manager's view; only while [link] is up. Without a link the
  /// dashboard doesn't know what is on screen, so it claims nothing.
  final CameraView? view;

  final RecordingStatus? _recording;

  /// camera-manager's recording state, only while [link] is up, and null
  /// until it has said (or if it doesn't serve it). Without it the dashboard
  /// claims no recording.
  RecordingStatus? get recording => link == CameraLink.up ? _recording : null;

  /// Why the link is down, or what is connecting.
  final String? detail;

  /// No camera-manager behind it: the browser preview and the in-app
  /// simulator. There is no picture.
  final bool simulated;

  /// The camera on screen, if the dashboard knows of one.
  CameraId? get camera => link == CameraLink.up ? view?.camera : null;

  @override
  bool operator ==(Object other) =>
      other is CameraStatus &&
      other.link == link &&
      other.view == view &&
      other._recording == _recording &&
      other.detail == detail &&
      other.simulated == simulated;

  @override
  int get hashCode => Object.hash(link, view, _recording, detail, simulated);

  @override
  String toString() =>
      'CameraStatus($link, $view, $_recording, $detail, simulated: $simulated)';
}

/// Where the camera view comes from: camera-manager over gRPC, or a
/// simulation.
abstract class CameraSource {
  ValueListenable<CameraStatus> get status;

  void start();
  void stop();

  /// Sends a move, as the switch would. Completes with the view that follows;
  /// throws when camera-manager can't be reached.
  Future<CameraView> move(SwitchMove move);

  /// "Save clip": protects the segment being written and the minutes around
  /// it (ADR-0027 decision 8). A refusal comes back with `saved` false and
  /// why; throws when camera-manager can't be reached.
  Future<SaveClipResult> saveClip();
}

String cameraName(CameraId c) => switch (c) {
      CameraId.front => 'Front camera',
      CameraId.left => 'Left camera',
      CameraId.right => 'Right camera',
      CameraId.rear => 'Rear camera',
    };

/// "Front", "Rear": a camera's short name for the status bar and lists.
String cameraShortName(CameraId? c) => c == null ? 'Camera' : cameraName(c).split(' ').first;

/// Bytes as GB with one decimal (decimal GB, as the retention settings are).
String formatGb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';
