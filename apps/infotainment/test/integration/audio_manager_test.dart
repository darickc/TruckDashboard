// Runs the real services/audio-manager binary with its simulated phone and
// reads it through the app's audio source: the Rust server and the Dart
// client agree on f250.audio.v1 (now playing, controls, the pairing window
// and the speaker settings), and killing audio-manager takes the phone and
// its track off the dashboard. Skipped unless the binary is built:
// `cargo build -p audio-manager` (make ui-test does this).
@Tags(['integration'])
library;

import 'dart:io';

import 'package:f250_infotainment/audio/audio_state.dart';
import 'package:f250_infotainment/audio/grpc_audio_source.dart';
import 'package:f250_infotainment/data/gateway_connection.dart';
import 'package:flutter_test/flutter_test.dart';

final _root = Directory.current.parent.parent.path; // apps/infotainment → repo
final _bin = File('$_root/target/debug/audio-manager');

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('condition not met within $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final skip = _bin.existsSync() ? false : 'build audio-manager first: cargo build -p audio-manager';

  test('now playing, controls, pairing and speakers; stopping audio-manager clears the phone', () async {
    final dir = Directory.systemTemp.createTempSync('f250-audioit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sock = '${dir.path}/a.sock';
    final am = await Process.start(_bin.path, [
      '--listen', 'unix:$sock',
      '--simulate',
      '--settings-file', '${dir.path}/speakers.json',
    ]);
    addTearDown(() => am.kill());
    am.stdout.listen((_) {});
    am.stderr.listen((_) {});
    await _until(() => File(sock).existsSync());

    final src = GrpcAudioSource(endpoint: UnixEndpoint(sock), retryDelay: const Duration(milliseconds: 200))
      ..start();
    addTearDown(src.stop);
    AudioReport? r() => src.status.value.report;

    await _until(() => r()?.nowPlaying != null);
    expect(r()!.simulated, isTrue);
    expect(r()!.phone!.name, 'Simulated phone');
    expect(r()!.nowPlaying!.title, 'Simulated Track One');
    expect(r()!.nowPlaying!.duration, const Duration(seconds: 185));
    expect(r()!.pairing.phase, PairingPhase.closed);

    expect((await src.control(MediaCommand.next)).ok, isTrue);
    await _until(() => r()?.nowPlaying?.title == 'Second Simulated Song');

    // Pairing: the simulated second phone asks after 5 s.
    expect((await src.openPairing(60)).ok, isTrue);
    await _until(() => r()?.pairing.phase == PairingPhase.open);
    expect(r()!.pairing.secondsLeft, inInclusiveRange(59, 60));
    await _until(() => r()?.pairing.question != null, timeout: const Duration(seconds: 15));
    final q = r()!.pairing.question!;
    expect(q.code, '246810');
    expect((await src.confirm(q.id, true)).ok, isTrue);
    await _until(() => r()?.phone?.name == 'Simulated phone 2' && r()?.pairing.phase == PairingPhase.closed);

    // Speakers: refused outside the limits, kept inside them.
    final snap = await src.getSpeakers();
    expect(snap.limits.crossoverMaxHz, 120);
    expect((await src.setSpeakers(const SpeakerSettings(crossoverHz: 500))).ok, isFalse);
    final ok = await src.setSpeakers(const SpeakerSettings(fader: 2, crossoverHz: 90));
    expect(ok.ok, isTrue);
    expect(ok.detail, contains('not applied'));
    expect((await src.getSpeakers()).settings, const SpeakerSettings(fader: 2, crossoverHz: 90));

    am.kill();
    await _until(() => src.status.value.link == AudioLink.down);
    expect(src.status.value.report, isNull, reason: 'nothing current without audio-manager');
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));
}
