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

/// The connection to camera-manager.
enum CameraLink { connecting, up, down }

@immutable
class CameraStatus {
  const CameraStatus({required this.link, this.view, this.detail, this.simulated = false});

  final CameraLink link;

  /// camera-manager's view; only while [link] is up. Without a link the
  /// dashboard doesn't know what is on screen, so it claims nothing.
  final CameraView? view;

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
      other.detail == detail &&
      other.simulated == simulated;

  @override
  int get hashCode => Object.hash(link, view, detail, simulated);

  @override
  String toString() => 'CameraStatus($link, $view, $detail, simulated: $simulated)';
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
}

String cameraName(CameraId c) => switch (c) {
      CameraId.front => 'Front camera',
      CameraId.left => 'Left camera',
      CameraId.right => 'Right camera',
      CameraId.rear => 'Rear camera',
    };
